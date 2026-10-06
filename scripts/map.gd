class_name Map
extends Node2D

# The Map node only draws. It never mutates game state.
# Pixel grid matches tile grid, drawn through one ImageTexture.

var _image: Image
var _texture: ImageTexture
var _state: GameState
var _ready_to_draw: bool = false


func setup(state: GameState) -> void:
	_state = state
	_image = Image.create(_state.width, _state.height, false, Image.FORMAT_RGBA8)
	_paint_all()
	_texture = ImageTexture.create_from_image(_image)
	_ready_to_draw = true
	queue_redraw()


func render() -> void:
	# Apply all dirty tiles into the Image, then push once to the GPU.
	if _state == null or _texture == null:
		return
	if _state.dirty_tiles.is_empty():
		return
	for i: int in _state.dirty_tiles.keys():
		var p := _state.idx_to_xy(i)
		_image.set_pixel(p.x, p.y, _color_for_tile(i))
	_state.dirty_tiles.clear()
	_texture.update(_image)
	queue_redraw()


func _paint_all() -> void:
	for i in range(_state.tile_count()):
		var p := _state.idx_to_xy(i)
		_image.set_pixel(p.x, p.y, _color_for_tile(i))


func _color_for_tile(i: int) -> Color:
	var t: int = _state.terrain[i]
	var owner_id: int = _state.owners[i]
	var terrain_color := _terrain_color(t)
	if owner_id == 0:
		return terrain_color
	if owner_id == GameState.RUINS_OWNER_ID:
		return Balance.RUINS_COLOR.lerp(terrain_color, Balance.OWNER_TERRAIN_TINT)
	var owner_color := Balance.color_for_player(owner_id)
	return owner_color.lerp(terrain_color, Balance.OWNER_TERRAIN_TINT)


func _terrain_color(t: int) -> Color:
	if t < 0 or t >= Balance.TERRAIN_COLORS.size():
		return Color.BLACK
	return Balance.TERRAIN_COLORS[t]


func _draw() -> void:
	if not _ready_to_draw or _texture == null:
		return
	# Fit the map inside the viewport while keeping its aspect ratio.
	var vp_size := get_viewport_rect().size
	var tex_w := float(_state.width)
	var tex_h := float(_state.height)
	var s: float = minf(vp_size.x / tex_w, vp_size.y / tex_h)
	var out_size := Vector2(tex_w * s, tex_h * s)
	var out_pos := (vp_size - out_size) * 0.5
	draw_texture_rect(_texture, Rect2(out_pos, out_size), false)
