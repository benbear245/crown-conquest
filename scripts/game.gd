extends Node2D

# Root of the game scene. Owns the Simulation, drives it at fixed ticks,
# tells the Map to render dirty tiles, and routes input into the sim, the
# HUD panels or the camera. Targeting (walls, boats, Bombard, Crown move)
# runs through one explicit input mode.

const DRAG_THRESHOLD_PX: float = 8.0
const LONG_PRESS_SEC: float = 0.4
const MAX_TICKS_PER_FRAME: int = 5

enum Mode { NORMAL, WALL, BOAT, BOMBARD, CROWN_MOVE }

@onready var _map: Map = $Map
@onready var _overlay: WorldOverlay = $Overlay
@onready var _hud: HUD = $HUD
@onready var _camera: CameraRig = $Camera2D

var _simulation: Simulation
var _tick_accumulator: float = 0.0

var _pointer_down: bool = false
var _pointer_dragged: bool = false
var _pointer_press_pos: Vector2 = Vector2.ZERO
var _pointer_down_time: float = 0.0
var _long_press_fired: bool = false

var _mode: int = Mode.NORMAL
var _boat_port: Vector2i = Vector2i(-1, -1)
var _wall_last_tile: Vector2i = Vector2i(-1, -1)
var _wall_line_tiles: int = 0
var _prev_crown_alert: bool = false


func _ready() -> void:
	_simulation = Simulation.new()
	_simulation.start_default_match(_random_seed())
	_hud.setup(_simulation)
	_hud.new_map_pressed.connect(_start_new_match)
	_hud.end_overlay.play_again_pressed.connect(_start_new_match)
	_hud.jump_to_crown_pressed.connect(_jump_to_crown)
	_hud.build_menu.build_requested.connect(_on_build_requested)
	_hud.build_menu.wall_mode_requested.connect(func() -> void: _enter_mode(Mode.WALL))
	_hud.build_menu.boat_requested.connect(func(x: int, y: int) -> void: _enter_boat_mode(Vector2i(x, y)))
	_hud.keep_panel.buy_keep_requested.connect(func(lvl: int) -> void: _simulation.player_buy_keep(_simulation.local_player_id, lvl))
	_hud.keep_panel.move_crown_requested.connect(func() -> void: _enter_mode(Mode.CROWN_MOVE))
	_hud.ability_bar.ability_pressed.connect(_on_ability_pressed)
	_hud.enemy_panel.offer_truce_requested.connect(func(id: int) -> void: _simulation.player_offer_truce(_simulation.local_player_id, id))
	_hud.mode_banner.cancel_pressed.connect(_exit_mode)
	_bind_match()


func _bind_match() -> void:
	_map.setup(_simulation.state)
	_overlay.state = _simulation.state
	_overlay.local_player_id = _simulation.local_player_id
	_camera.fit_to_world(_map.world_size())
	_prev_crown_alert = false
	_exit_mode()


func _process(delta: float) -> void:
	_tick_accumulator += delta
	var ticks_this_frame: int = 0
	while _tick_accumulator >= Balance.TICK_DELTA and ticks_this_frame < MAX_TICKS_PER_FRAME:
		_tick_accumulator -= Balance.TICK_DELTA
		_simulation.advance_tick()
		ticks_this_frame += 1
	if ticks_this_frame == MAX_TICKS_PER_FRAME:
		_tick_accumulator = 0.0
	_simulation.state.events.clear()
	_map.render()
	_hud.update_from_state()
	_sync_overlay()
	_handle_crown_alert_vibration()
	_check_long_press(delta)


func _sync_overlay() -> void:
	var sel: Vector2i = _hud.build_menu.selected_tile()
	_overlay.selected_tile = sel
	_overlay.selected_radius = 0
	if sel.x >= 0:
		var b: Building = _simulation.state.building_at_tile.get(_simulation.state.idx(sel.x, sel.y), null)
		_overlay.selected_radius = b.radius() if b != null and b.radius() > 0 else Balance.FORT_RADIUS
	_overlay.boat_port = _boat_port if _mode == Mode.BOAT else Vector2i(-1, -1)
	if _mode != Mode.CROWN_MOVE:
		_overlay.move_preview = Vector2i(-1, -1)
	if _mode != Mode.NORMAL and _simulation.state.phase != Balance.PHASE_MATCH:
		_exit_mode()


func _handle_crown_alert_vibration() -> void:
	var me: Player = _simulation.state.get_player(_simulation.local_player_id)
	var active: bool = me != null and me.is_alive and me.crown_alert_until > _simulation.state.match_time
	if active and not _prev_crown_alert:
		Input.vibrate_handheld()
	_prev_crown_alert = active


# --- Pointer input -----------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin_pointer(mb.position)
			else:
				_end_pointer(mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera.zoom_by(CameraRig.ZOOM_STEP)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera.zoom_by(1.0 / CameraRig.ZOOM_STEP)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		_pointer_drag(mm.position, mm.relative)
	elif event is InputEventMagnifyGesture:
		var mg: InputEventMagnifyGesture = event
		_camera.zoom_by(mg.factor)
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			_begin_pointer(st.position)
		else:
			_end_pointer(st.position)
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		_pointer_drag(sd.position, sd.relative)


func _begin_pointer(pos: Vector2) -> void:
	_pointer_down = true
	_pointer_dragged = false
	_pointer_press_pos = pos
	_pointer_down_time = 0.0
	_long_press_fired = false
	_wall_last_tile = Vector2i(-1, -1)
	_wall_line_tiles = 0


func _end_pointer(pos: Vector2) -> void:
	if _pointer_down and not _pointer_dragged and not _long_press_fired:
		_on_tap(pos)
	_pointer_down = false
	_pointer_dragged = false
	_long_press_fired = false


func _pointer_drag(pos: Vector2, relative: Vector2) -> void:
	if not _pointer_down:
		return
	if not _pointer_dragged and pos.distance_to(_pointer_press_pos) > DRAG_THRESHOLD_PX:
		_pointer_dragged = true
		if _mode == Mode.WALL:
			_paint_wall_to(_screen_to_tile(_pointer_press_pos))
	if not _pointer_dragged:
		return
	if _mode == Mode.WALL:
		_paint_wall_to(_screen_to_tile(pos))
		return
	_camera.pan_screen(relative)


func _check_long_press(delta: float) -> void:
	if not _pointer_down or _pointer_dragged or _long_press_fired:
		return
	_pointer_down_time += delta
	if _pointer_down_time >= LONG_PRESS_SEC:
		_long_press_fired = true
		_on_long_press(_pointer_press_pos)


func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var world: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
	var st: GameState = _simulation.state
	if world.x < 0.0 or world.y < 0.0 or world.x >= float(st.width) or world.y >= float(st.height):
		return Vector2i(-1, -1)
	return Vector2i(int(world.x), int(world.y))


# --- Gestures -> actions -----------------------------------------------------

func _on_long_press(screen_pos: Vector2) -> void:
	var tile: Vector2i = _screen_to_tile(screen_pos)
	var st: GameState = _simulation.state
	if tile.x < 0 or st.phase != Balance.PHASE_MATCH or _mode != Mode.NORMAL:
		return
	_hud.close_panels()
	var owner_id: int = st.owners[st.idx(tile.x, tile.y)]
	if owner_id == _simulation.local_player_id:
		_hud.build_menu.open_at(tile)
	elif owner_id > 0 and owner_id != GameState.RUINS_OWNER_ID:
		_hud.enemy_panel.open_for(owner_id)


func _on_tap(screen_pos: Vector2) -> void:
	var tile: Vector2i = _screen_to_tile(screen_pos)
	if tile.x < 0:
		return
	var st: GameState = _simulation.state
	var me_id: int = _simulation.local_player_id
	if st.phase == Balance.PHASE_PLACEMENT:
		_simulation.player_place_crown(me_id, tile.x, tile.y)
		return
	if st.phase != Balance.PHASE_MATCH:
		return
	# A tap on the map closes any open panel first.
	if _hud.any_panel_open():
		_hud.close_panels()
		return
	match _mode:
		Mode.WALL:
			_paint_wall_to(tile)
		Mode.BOAT:
			_tap_boat_target(tile)
		Mode.BOMBARD:
			if _simulation.player_activate_bombard(me_id, tile.x, tile.y):
				_exit_mode()
			else:
				_hud.mode_banner.set_text("Out of range — pick a spot within %d tiles of your border" % Balance.BOMBARD_RANGE_TILES)
		Mode.CROWN_MOVE:
			_tap_crown_move(tile)
		_:
			_tap_normal(tile)


func _tap_normal(tile: Vector2i) -> void:
	var st: GameState = _simulation.state
	var me: Player = st.get_player(_simulation.local_player_id)
	if me == null or not me.is_alive:
		return
	var ti: int = st.idx(tile.x, tile.y)
	var owner_id: int = st.owners[ti]
	if owner_id == me.id:
		if me.crown_x >= 0 and absi(tile.x - me.crown_x) <= 1 and absi(tile.y - me.crown_y) <= 1:
			_hud.keep_panel.open_panel()
			return
		var b: Building = st.building_at_tile.get(ti, null)
		if b != null and b.type == Balance.BUILDING_PORT:
			_enter_boat_mode(tile)
		return
	var frac: float = _hud.send_fraction()
	if owner_id == 0 or owner_id == GameState.RUINS_OWNER_ID:
		_simulation.player_expand(me.id, tile.x, tile.y, frac)
	else:
		_simulation.player_attack(me.id, tile.x, tile.y, frac)


# --- Modes -------------------------------------------------------------------

func _enter_mode(mode: int) -> void:
	_hud.close_panels()
	_mode = mode
	match mode:
		Mode.WALL:
			_hud.mode_banner.show_mode(_wall_text(), "Done")
		Mode.BOMBARD:
			_hud.mode_banner.show_mode("Bombard: tap an enemy spot within %d tiles of your border" % Balance.BOMBARD_RANGE_TILES)
		Mode.CROWN_MOVE:
			_hud.mode_banner.show_mode("Move Crown: tap your own land at least %d tiles from any enemy" % Balance.CROWN_MOVE_MIN_DIST_FROM_ENEMY)
		_:
			_hud.mode_banner.hide_mode()


func _enter_boat_mode(port: Vector2i) -> void:
	_boat_port = port
	_enter_mode(Mode.BOAT)
	_hud.mode_banner.show_mode("Boat: tap a free or enemy coast across the water (sends %d%%)" % int(round(_hud.send_fraction() * 100.0)))


func _exit_mode() -> void:
	_mode = Mode.NORMAL
	_boat_port = Vector2i(-1, -1)
	_hud.mode_banner.hide_mode()


func _wall_text() -> String:
	var me: Player = _simulation.state.get_player(_simulation.local_player_id)
	var walls: int = me.wall_count if me != null else 0
	return "Wall mode: drag along your land.  This line: %d tiles · %d troops.  Walls %d/%d" % [
		_wall_line_tiles, int(float(_wall_line_tiles) * Balance.WALL_COST_PER_TILE), walls, Balance.WALL_LIMIT]


# Builds walls on every tile of the straight line from the last painted tile to
# `tile`, so a fast drag doesn't leave gaps.
func _paint_wall_to(tile: Vector2i) -> void:
	if tile.x < 0:
		return
	var from: Vector2i = _wall_last_tile if _wall_last_tile.x >= 0 else tile
	for t: Vector2i in _line_tiles(from, tile):
		if t == _wall_last_tile:
			continue
		if _simulation.player_build_wall(_simulation.local_player_id, t.x, t.y):
			_wall_line_tiles += 1
	_wall_last_tile = tile
	_hud.mode_banner.set_text(_wall_text())


static func _line_tiles(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx: int = absi(b.x - a.x)
	var dy: int = -absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var err: int = dx + dy
	var p: Vector2i = a
	while true:
		out.append(p)
		if p == b:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return out


func _tap_boat_target(tile: Vector2i) -> void:
	var me: Player = _simulation.state.get_player(_simulation.local_player_id)
	if me == null:
		return
	var path := PackedInt32Array()
	var reason: String = BoatsOps.launch_block_reason(_simulation, me, _boat_port.x, _boat_port.y, tile.x, tile.y, path)
	if reason != "":
		_hud.mode_banner.set_text("Boat: %s — tap another coast" % reason)
		return
	_simulation.player_launch_boat(me.id, _boat_port.x, _boat_port.y, tile.x, tile.y, _hud.send_fraction())
	_exit_mode()


func _tap_crown_move(tile: Vector2i) -> void:
	var me: Player = _simulation.state.get_player(_simulation.local_player_id)
	if me == null:
		return
	var reason: String = CrownsOps.move_block_reason(_simulation, me, tile.x, tile.y)
	_overlay.move_preview = tile
	_overlay.move_preview_ok = reason == ""
	if reason != "":
		_hud.mode_banner.set_text("Move Crown: %s — tap another spot" % reason)
		return
	_simulation.player_move_crown(me.id, tile.x, tile.y)
	_exit_mode()


# --- HUD actions -------------------------------------------------------------

func _on_build_requested(type: int, x: int, y: int) -> void:
	var id: int = _simulation.local_player_id
	match type:
		Balance.BUILDING_FORT:
			_simulation.player_build_fort(id, x, y)
		Balance.BUILDING_FORT2:
			_simulation.player_upgrade_fort(id, x, y)
		Balance.BUILDING_BARRACKS:
			_simulation.player_build_barracks(id, x, y)
		Balance.BUILDING_PORT:
			_simulation.player_build_port(id, x, y)


func _on_ability_pressed(ability_id: int) -> void:
	var pid: int = _simulation.local_player_id
	match ability_id:
		AbilitiesOps.ID_SWIFT_MARCH:
			_simulation.player_activate_swift_march(pid)
		AbilitiesOps.ID_CROWN_SHIELD:
			_simulation.player_activate_crown_shield(pid)
		AbilitiesOps.ID_RALLY:
			_simulation.player_activate_rally(pid)
		AbilitiesOps.ID_BOMBARD:
			_enter_mode(Mode.BOMBARD)


func _jump_to_crown() -> void:
	var me: Player = _simulation.state.get_player(_simulation.local_player_id)
	if me != null and me.crown_x >= 0:
		_camera.look_at_tile(Vector2i(me.crown_x, me.crown_y))


func _start_new_match() -> void:
	_simulation.start_match(_simulation.size_preset, _simulation.map_type, _random_seed())
	_hud.end_overlay.reset()
	_bind_match()


func _random_seed() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) ^ randi()
