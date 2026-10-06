extends Node2D

# Root of the game scene. Owns the Simulation, drives it at fixed ticks,
# tells the Map to render dirty tiles, and routes input into the sim, the
# HUD panels or the camera. Targeting modes (walls, boats, Bombard, Crown
# move) live in Targeting.

const DRAG_THRESHOLD_PX: float = 8.0
const LONG_PRESS_SEC: float = 0.4
const MAX_TICKS_PER_FRAME: int = 5

@onready var _map: Map = $Map
@onready var _overlay: WorldOverlay = $Overlay
@onready var _hud: HUD = $HUD
@onready var _camera: CameraRig = $Camera2D

var _simulation: Simulation
var _targeting: Targeting
var _tick_accumulator: float = 0.0

var _pointer_down: bool = false
var _pointer_dragged: bool = false
var _pointer_press_pos: Vector2 = Vector2.ZERO
var _pointer_down_time: float = 0.0
var _long_press_fired: bool = false
var _prev_crown_alert: bool = false


func _ready() -> void:
	_simulation = Simulation.new()
	_simulation.start_default_match(_random_seed())
	_hud.setup(_simulation)
	_targeting = Targeting.new(_simulation, _hud, _overlay)
	_hud.new_map_pressed.connect(_start_new_match)
	_hud.end_overlay.play_again_pressed.connect(_start_new_match)
	_hud.jump_to_crown_pressed.connect(_jump_to_crown)
	_hud.build_menu.build_requested.connect(_on_build_requested)
	_hud.build_menu.wall_mode_requested.connect(func() -> void: _targeting.enter(Targeting.Mode.WALL))
	_hud.build_menu.boat_requested.connect(func(x: int, y: int) -> void: _targeting.enter_boat(Vector2i(x, y)))
	_hud.keep_panel.buy_keep_requested.connect(func(lvl: int) -> void: _simulation.player_buy_keep(_simulation.local_player_id, lvl))
	_hud.keep_panel.move_crown_requested.connect(func() -> void: _targeting.enter(Targeting.Mode.CROWN_MOVE))
	_hud.ability_bar.ability_pressed.connect(_on_ability_pressed)
	_hud.enemy_panel.offer_truce_requested.connect(func(id: int) -> void: _simulation.player_offer_truce(_simulation.local_player_id, id))
	_hud.truce_panel.respond.connect(func(from_id: int, ok: bool) -> void: _simulation.player_respond_truce(_simulation.local_player_id, from_id, ok))
	_bind_match()


func _bind_match() -> void:
	_map.setup(_simulation.state)
	_overlay.state = _simulation.state
	_overlay.local_player_id = _simulation.local_player_id
	_camera.fit_to_world(_map.world_size())
	_prev_crown_alert = false
	_targeting.exit()


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
	_targeting.sync_overlay()


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
	_targeting.begin_wall_stroke()


func _end_pointer(pos: Vector2) -> void:
	if _pointer_down and not _pointer_dragged and not _long_press_fired:
		_on_tap(pos)
	_pointer_down = false
	_pointer_dragged = false
	_long_press_fired = false


func _pointer_drag(pos: Vector2, relative: Vector2) -> void:
	if not _pointer_down:
		return
	var wall_mode: bool = _targeting.mode == Targeting.Mode.WALL
	if not _pointer_dragged and pos.distance_to(_pointer_press_pos) > DRAG_THRESHOLD_PX:
		_pointer_dragged = true
		if wall_mode:
			_targeting.paint_wall_to(_screen_to_tile(_pointer_press_pos))
	if not _pointer_dragged:
		return
	if wall_mode:
		_targeting.paint_wall_to(_screen_to_tile(pos))
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
	if tile.x < 0 or st.phase != Balance.PHASE_MATCH or _targeting.is_active():
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
	if st.phase == Balance.PHASE_PLACEMENT:
		_simulation.player_place_crown(_simulation.local_player_id, tile.x, tile.y)
		return
	if st.phase != Balance.PHASE_MATCH:
		return
	# A tap on the map closes any open panel first.
	if _hud.any_panel_open():
		_hud.close_panels()
		return
	if _targeting.is_active():
		_targeting.tap(tile)
	else:
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
			_targeting.enter_boat(tile)
		return
	var frac: float = _hud.send_fraction()
	if owner_id == 0 or owner_id == GameState.RUINS_OWNER_ID:
		_simulation.player_expand(me.id, tile.x, tile.y, frac)
	elif TrucesOps.has_truce(me, owner_id, st.match_time):
		_targeting.confirm_truce_break(tile, frac, st.get_player(owner_id))
	else:
		_simulation.player_attack(me.id, tile.x, tile.y, frac)


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
			_targeting.enter(Targeting.Mode.BOMBARD)


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
