extends Node2D

# Root of the game scene. Owns the Simulation, drives it at fixed ticks,
# tells the Map node to render dirty tiles, and routes input into the sim
# or into the Camera2D (pan / zoom / tap).

const DRAG_THRESHOLD_PX: float = 8.0
const ZOOM_STEP: float = 1.15
const ZOOM_MIN_FACTOR: float = 0.6         # vs. fit-to-screen zoom
const ZOOM_MAX_FACTOR: float = 6.0

@onready var _map: Map = $Map
@onready var _hud: HUD = $HUD
@onready var _camera: Camera2D = $Camera2D

var _simulation: Simulation
var _tick_accumulator: float = 0.0

var _fit_zoom: float = 1.0

var _pointer_down: bool = false
var _pointer_dragged: bool = false
var _pointer_press_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	_simulation = Simulation.new()
	_simulation.start_default_match(_random_seed())
	_map.setup(_simulation.state)
	_hud.setup(_simulation.state)
	_hud.new_map_pressed.connect(_on_new_map_pressed)
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


func _end_pointer(pos: Vector2) -> void:
	if _pointer_down and not _pointer_dragged:
		_try_tap(pos)
	_pointer_down = false
	_pointer_dragged = false


func _handle_pointer_drag(pos: Vector2, relative: Vector2) -> void:
	if not _pointer_down:
		return
	if not _pointer_dragged and pos.distance_to(_pointer_press_pos) > DRAG_THRESHOLD_PX:
		_pointer_dragged = true
	if _pointer_dragged:
		_camera.position -= relative / _camera.zoom.x
		_clamp_camera()


func _try_tap(screen_pos: Vector2) -> void:
	var tile: Vector2i = _screen_to_tile(screen_pos)
	if tile.x < 0:
		return
	if _simulation.state.players.is_empty():
		return
	var local_id: int = _simulation.local_player_id
	match _simulation.state.phase:
		Balance.PHASE_PLACEMENT:
			_simulation.player_place_crown(local_id, tile.x, tile.y)
		Balance.PHASE_MATCH:
			_simulation.player_expand(local_id, tile.x, tile.y, _hud.send_fraction())


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
	var next_seed := _random_seed()
	_simulation.start_match(_simulation.size_preset, _simulation.map_type, next_seed)
	_map.setup(_simulation.state)
	_init_camera()


func _random_seed() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) ^ randi()
