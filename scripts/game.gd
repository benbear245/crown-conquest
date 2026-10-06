extends Node2D

# Root of the game scene. Owns the Simulation, drives it at fixed ticks,
# tells the Map node to render dirty tiles, and routes input into the sim
# or into the Camera2D (pan / zoom / tap).

const DRAG_THRESHOLD_PX: float = 8.0
const ZOOM_STEP: float = 1.15
const ZOOM_MIN_FACTOR: float = 0.6         # vs. fit-to-screen zoom
const ZOOM_MAX_FACTOR: float = 6.0
const LONG_PRESS_SEC: float = 0.4

@onready var _map: Map = $Map
@onready var _hud: HUD = $HUD
@onready var _camera: Camera2D = $Camera2D

var _simulation: Simulation
var _tick_accumulator: float = 0.0

var _fit_zoom: float = 1.0

var _pointer_down: bool = false
var _pointer_dragged: bool = false
var _pointer_press_pos: Vector2 = Vector2.ZERO
var _pointer_down_time: float = 0.0
var _long_press_fired: bool = false

# Boat launch state: when set, the next tap on a target coast launches a boat.
var _pending_boat_port: Vector2i = Vector2i(-1, -1)
# Last wall tile painted during a drag, so we don't try to re-build the same tile.
var _last_wall_drag_tile: Vector2i = Vector2i(-9999, -9999)

var _prev_crown_alert: bool = false


func _ready() -> void:
	_simulation = Simulation.new()
	_simulation.start_default_match(_random_seed())
	_map.setup(_simulation.state)
	_hud.setup(_simulation)
	_hud.new_map_pressed.connect(_on_new_map_pressed)
	_hud.play_again_pressed.connect(_on_play_again_pressed)
	_hud.jump_to_crown_pressed.connect(_on_jump_to_crown_pressed)
	_hud.build_fort_requested.connect(_on_build_fort_requested)
	_hud.upgrade_fort_requested.connect(_on_upgrade_fort_requested)
	_hud.build_barracks_requested.connect(_on_build_barracks_requested)
	_hud.build_port_requested.connect(_on_build_port_requested)
	_hud.buy_keep_requested.connect(_on_buy_keep_requested)
	_hud.wall_mode_toggled.connect(_on_wall_mode_toggled)
	_hud.boat_launch_requested.connect(_on_boat_launch_requested)
	_init_camera()


func _process(delta: float) -> void:
	_tick_accumulator += delta
	var ticks_this_frame := 0
	while _tick_accumulator >= Balance.TICK_DELTA and ticks_this_frame < 5:
		_tick_accumulator -= Balance.TICK_DELTA
		_simulation.advance_tick()
		ticks_this_frame += 1
	_map.render()
	_hud.update_from_state()
	_handle_crown_alert_vibration()
	_check_long_press(delta)


func _check_long_press(delta: float) -> void:
	if not _pointer_down or _pointer_dragged or _long_press_fired:
		return
	_pointer_down_time += delta
	if _pointer_down_time >= LONG_PRESS_SEC:
		_long_press_fired = true
		_handle_long_press(_pointer_press_pos)


func _handle_crown_alert_vibration() -> void:
	var local: Player = _simulation.state.get_player(_simulation.local_player_id)
	var active: bool = local != null and local.is_alive and local.crown_alert_until > _simulation.state.match_time
	if active and not _prev_crown_alert:
		Input.vibrate_handheld()
	_prev_crown_alert = active


# --- Input ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMagnifyGesture:
		_zoom_by(event.factor)
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			_begin_pointer(st.position)
		else:
			_end_pointer(st.position)
	elif event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		_handle_pointer_drag(sd.position, sd.relative)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_begin_pointer(event.position)
			else:
				_end_pointer(event.position)
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_by(ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_by(1.0 / ZOOM_STEP)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _pointer_down:
		_handle_pointer_drag(event.position, event.relative)


func _begin_pointer(pos: Vector2) -> void:
	_pointer_down = true
	_pointer_dragged = false
	_pointer_press_pos = pos
	_pointer_down_time = 0.0
	_long_press_fired = false
	_last_wall_drag_tile = Vector2i(-9999, -9999)


func _end_pointer(pos: Vector2) -> void:
	if _pointer_down and not _pointer_dragged and not _long_press_fired:
		_try_tap(pos)
	_pointer_down = false
	_pointer_dragged = false
	_long_press_fired = false
	_pointer_down_time = 0.0


func _handle_pointer_drag(pos: Vector2, relative: Vector2) -> void:
	if not _pointer_down:
		return
	if not _pointer_dragged and pos.distance_to(_pointer_press_pos) > DRAG_THRESHOLD_PX:
		_pointer_dragged = true
	if _pointer_dragged:
		# Wall-drawing drag: build a wall at each new tile dragged over.
		if _hud.wall_mode_active():
			var tile: Vector2i = _screen_to_tile(pos)
			if tile.x >= 0 and tile != _last_wall_drag_tile:
				_last_wall_drag_tile = tile
				_simulation.player_build_wall(_simulation.local_player_id, tile.x, tile.y)
			return
		_camera.position -= relative / _camera.zoom.x
		_clamp_camera()


func _handle_long_press(screen_pos: Vector2) -> void:
	var tile: Vector2i = _screen_to_tile(screen_pos)
	if tile.x < 0:
		return
	if _simulation.state.phase != Balance.PHASE_MATCH:
		return
	var ti: int = _simulation.state.idx(tile.x, tile.y)
	if _simulation.state.owners[ti] != _simulation.local_player_id:
		return
	_hud.open_build_menu(tile.x, tile.y)


func _try_tap(screen_pos: Vector2) -> void:
	var tile: Vector2i = _screen_to_tile(screen_pos)
	if tile.x < 0:
		return
	if _simulation.state.players.is_empty():
		return
	# Close menus if open — a tap outside dismisses them.
	if _hud.is_build_menu_open():
		_hud.close_build_menu()
		return
	if _hud.is_keep_panel_open():
		_hud.close_keep_panel()
		return
	var local_id: int = _simulation.local_player_id
	match _simulation.state.phase:
		Balance.PHASE_PLACEMENT:
			_simulation.player_place_crown(local_id, tile.x, tile.y)
		Balance.PHASE_MATCH:
			# Boat landing selection.
			if _pending_boat_port.x >= 0:
				var frac := _hud.send_fraction()
				_simulation.player_launch_boat(local_id, _pending_boat_port.x, _pending_boat_port.y, tile.x, tile.y, frac)
				_pending_boat_port = Vector2i(-1, -1)
				return
			# Wall mode: tap on own land builds one wall tile.
			if _hud.wall_mode_active():
				_simulation.player_build_wall(local_id, tile.x, tile.y)
				return
			# Tap on our own Crown centre opens Keep panel.
			var local: Player = _simulation.state.get_player(local_id)
			if local != null and local.crown_x >= 0:
				var ccx: int = local.crown_x
				var ccy: int = local.crown_y
				if abs(tile.x - ccx) <= 1 and abs(tile.y - ccy) <= 1:
					_hud.open_keep_panel()
					return
			var target_owner: int = _simulation.state.owners[_simulation.state.idx(tile.x, tile.y)]
			var frac: float = _hud.send_fraction()
			if target_owner == 0 or target_owner == GameState.RUINS_OWNER_ID:
				_simulation.player_expand(local_id, tile.x, tile.y, frac)
			elif target_owner != local_id:
				_simulation.player_attack(local_id, tile.x, tile.y, frac)


func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var world := get_canvas_transform().affine_inverse() * screen_pos
	var w: int = _simulation.state.width
	var h: int = _simulation.state.height
	if world.x < 0.0 or world.y < 0.0 or world.x >= float(w) or world.y >= float(h):
		return Vector2i(-1, -1)
	return Vector2i(int(world.x), int(world.y))


# --- Camera -----------------------------------------------------------------

func _init_camera() -> void:
	var world := _map.world_size()
	_camera.position = world * 0.5
	var vp := get_viewport_rect().size
	_fit_zoom = minf(vp.x / world.x, vp.y / world.y)
	_camera.zoom = Vector2(_fit_zoom, _fit_zoom)


func _zoom_by(factor: float) -> void:
	var cur: float = _camera.zoom.x
	var new_zoom: float = clampf(cur * factor, _fit_zoom * ZOOM_MIN_FACTOR, _fit_zoom * ZOOM_MAX_FACTOR)
	_camera.zoom = Vector2(new_zoom, new_zoom)
	_clamp_camera()


func _clamp_camera() -> void:
	var world := _map.world_size()
	var vp := get_viewport_rect().size
	var half := (vp / _camera.zoom.x) * 0.5
	var min_x: float = minf(half.x, world.x * 0.5)
	var max_x: float = maxf(world.x - half.x, world.x * 0.5)
	var min_y: float = minf(half.y, world.y * 0.5)
	var max_y: float = maxf(world.y - half.y, world.y * 0.5)
	_camera.position.x = clampf(_camera.position.x, min_x, max_x)
	_camera.position.y = clampf(_camera.position.y, min_y, max_y)


# --- Debug ------------------------------------------------------------------

func _on_new_map_pressed() -> void:
	_start_new_match()


func _on_play_again_pressed() -> void:
	_start_new_match()


func _on_jump_to_crown_pressed() -> void:
	var local: Player = _simulation.state.get_player(_simulation.local_player_id)
	if local == null or local.crown_x < 0:
		return
	_camera.position = Vector2(float(local.crown_x) + 0.5, float(local.crown_y) + 0.5)
	_clamp_camera()


func _start_new_match() -> void:
	var next_seed := _random_seed()
	_simulation.start_match(_simulation.size_preset, _simulation.map_type, next_seed)
	_map.setup(_simulation.state)
	_hud.reset_overlay_dismissal()
	_prev_crown_alert = false
	_init_camera()


func _random_seed() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) ^ randi()


# --- HUD signal handlers for buildings and Keep ------------------------------

func _on_build_fort_requested(x: int, y: int) -> void:
	_simulation.player_build_fort(_simulation.local_player_id, x, y)


func _on_upgrade_fort_requested(x: int, y: int) -> void:
	_simulation.player_upgrade_fort(_simulation.local_player_id, x, y)


func _on_build_barracks_requested(x: int, y: int) -> void:
	_simulation.player_build_barracks(_simulation.local_player_id, x, y)


func _on_build_port_requested(x: int, y: int) -> void:
	_simulation.player_build_port(_simulation.local_player_id, x, y)


func _on_buy_keep_requested(level: int) -> void:
	_simulation.player_buy_keep(_simulation.local_player_id, level)
	_hud.open_keep_panel()


func _on_wall_mode_toggled(_enabled: bool) -> void:
	# Nothing extra to do; game.gd checks _hud.wall_mode_active() per tap.
	pass


func _on_boat_launch_requested(port_x: int, port_y: int) -> void:
	_pending_boat_port = Vector2i(port_x, port_y)
