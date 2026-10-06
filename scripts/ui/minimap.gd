class_name Minimap
extends PanelContainer

# The whole map in a corner: the live map texture, a box for what the camera
# shows, and every Crown. Tap or drag on it to jump the camera there.

signal jump_to(world_pos: Vector2)

const MAP_SIZE: Vector2 = Vector2(300, 180)   # all map sizes are 5:3

var _map: Map
var _state: GameState
var _view: Control
var _local_id: int = 1
var _held: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # keeps drawing behind the pause menu
	add_theme_stylebox_override("panel", UIStyle.panel_style(8))
	_view = Control.new()
	_view.custom_minimum_size = MAP_SIZE
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_input)
	add_child(_view)


func setup(map: Map, state: GameState, local_player_id: int) -> void:
	_map = map
	_state = state
	_local_id = local_player_id


func _process(_delta: float) -> void:
	_view.queue_redraw()


func _map_rect() -> Rect2:
	if _state == null:
		return Rect2(Vector2.ZERO, MAP_SIZE)
	var s: float = minf(MAP_SIZE.x / float(_state.width), MAP_SIZE.y / float(_state.height))
	var fit: Vector2 = Vector2(_state.width, _state.height) * s
	return Rect2((MAP_SIZE - fit) * 0.5, fit)


func _draw_view() -> void:
	if _state == null or _map == null or _map.texture() == null:
		return
	var r: Rect2 = _map_rect()
	_view.draw_texture_rect(_map.texture(), r, false)
	var k: float = r.size.x / float(_state.width)
	# Camera view box.
	var inv: Transform2D = get_viewport().canvas_transform.affine_inverse()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var a: Vector2 = inv * Vector2.ZERO
	var b: Vector2 = inv * vp
	var box := Rect2(r.position + a * k, (b - a) * k).intersection(r)
	_view.draw_rect(box, Color(1, 1, 1, 0.9), false, 2.0)
	# Crowns.
	for p: Player in _state.players:
		if not p.is_alive or p.crown_x < 0:
			continue
		var c: Vector2 = r.position + (Vector2(p.crown_x, p.crown_y) + Vector2(0.5, 0.5)) * k
		var radius: float = 5.0 if p.id == _local_id else 3.5
		_view.draw_circle(c, radius + 1.5, Color.BLACK)
		_view.draw_circle(c, radius, Icons.GOLD if p.id == _local_id else Palette.player(p.id).lightened(0.3))


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_held = (event as InputEventMouseButton).pressed
		if _held:
			_jump((event as InputEventMouseButton).position)
		_view.accept_event()
	elif event is InputEventMouseMotion and _held:
		_jump((event as InputEventMouseMotion).position)
		_view.accept_event()


func _jump(local_pos: Vector2) -> void:
	if _state == null:
		return
	var r: Rect2 = _map_rect()
	var world: Vector2 = (local_pos - r.position) / (r.size.x / float(_state.width))
	jump_to.emit(world.clamp(Vector2.ZERO, Vector2(_state.width, _state.height)))
