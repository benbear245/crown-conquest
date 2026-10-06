class_name Map
extends Node2D

# The Map node only draws. It never mutates game state.
# World coords are 1:1 with tiles; the Camera2D handles screen fitting.

var _image: Image
var _texture: ImageTexture
var _state: GameState
var _ready_to_draw: bool = false


func setup(state: GameState) -> void:
	_state = state
	_image = Image.create(_state.width, _state.height, false, Image.FORMAT_RGBA8)
	_paint_all()
	_texture = ImageTexture.create_from_image(_image)
	_state.dirty_tiles.clear()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ready_to_draw = true
	queue_redraw()


func render() -> void:
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


func world_size() -> Vector2:
	if _state == null:
		return Vector2.ZERO
	return Vector2(_state.width, _state.height)


func _paint_all() -> void:
	for i in range(_state.tile_count()):
		var p := _state.idx_to_xy(i)
		_image.set_pixel(p.x, p.y, _color_for_tile(i))


func _color_for_tile(i: int) -> Color:
	var t: int = _state.terrain[i]
	var owner_id: int = _state.owners[i]
	var terrain_color := _terrain_color(t)
	# Crown tiles overlay regardless of owner, so they're always visible.
	if _state.crown_tiles.has(i):
		var crown_owner: int = _state.crown_tiles[i]
		var centre: int = _state.crown_centres.get(crown_owner, -1)
		if i == centre:
			return Color(0.98, 0.86, 0.22)
		return Balance.color_for_player(crown_owner).lightened(0.35)
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
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, Vector2(_state.width, _state.height)), false)
