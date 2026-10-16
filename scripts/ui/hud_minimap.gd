class_name HudMinimap
extends Control

# Corner minimap: the whole map, the camera's view box, Crowns and Shrines.
# Tap (or drag) on it to move the camera there.

signal jump_requested(world_pos: Vector2)

const WIDTH: int = 300

var _texture: Texture2D
var _state: GameState
var _view: Rect2 = Rect2()
var _height: float = 180.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(state: GameState, map_texture: Texture2D) -> void:
	_state = state
	_texture = map_texture
	_height = float(WIDTH) * float(state.height) / float(state.width)


func apply_side(left_handed: bool) -> void:
	# Bottom corner on the thumb side's opposite, above the bottom bar.
	var bottom: float = -(UI.BOTTOM_BAR_H + UI.MARGIN * 2)
	UI.dock_side(self, left_handed, WIDTH, bottom - _height, bottom, true)


func set_view(view: Rect2) -> void:
	_view = view
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
	var dragging: bool = event is InputEventMouseMotion and ((event as InputEventMouseMotion).button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	if (pressed or dragging) and _state != null:
		var local_pos: Vector2 = (event as InputEventMouse).position
		var k: float = float(_state.width) / size.x
		jump_requested.emit(local_pos * k)
		accept_event()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size).grow(3), Color(0, 0, 0, 0.7))
	if _texture == null or _state == null:
		return
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)
	var k: float = size.x / float(_state.width)
	for s: Shrine in _state.shrines:
		var c := Vector2(s.x, s.y) * k
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]), MapOverlay.shrine_color(s.kind))
	for p: Player in _state.players:
		if p.is_alive and p.crown_x >= 0:
			var c := Vector2(p.crown_x, p.crown_y) * k
			draw_circle(c, 4.0, Color(1, 0.85, 0.2))
			draw_arc(c, 4.5, 0.0, TAU, 12, Color.BLACK, 1.0)
	if _view.size.x > 0.0:
		var r := Rect2(_view.position * k, _view.size * k).intersection(Rect2(Vector2.ZERO, size))
		draw_rect(r, Color(1, 1, 1, 0.9), false, 2.0)
