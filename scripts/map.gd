class_name Map
extends Node2D

# The Map node only draws. It never mutates game state.
# World coords are 1:1 with tiles; the Camera2D handles screen fitting.
# At most MAX_PIXELS_PER_FRAME changed tiles are repainted per frame, so a
# Crown falling (thousands of tiles turning to Ruins at once) is spread over a
# few frames instead of causing a hitch.

const MAX_PIXELS_PER_FRAME: int = 1200

var _image: Image
var _texture: ImageTexture
var _state: GameState
var _ready_to_draw: bool = false
var _painted_colorblind: bool = false
# Your territory pattern (Customize; 0 = none) and whose land gets it.
var pattern: int = 0
var pattern_owner: int = 1
# Plain owned-land colour per (owner, terrain), rebuilt on every full repaint.
var _land_colors: Dictionary = {}
# Progressive full repaint (after a Crown falls): next row to repaint, -1 = idle.
var _sweep_row: int = -1


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
	if _state.repaint_all:
		_state.repaint_all = false
		_sweep_row = 0
	var swept: int = _sweep_step()
	var dirty: Dictionary = _state.dirty_tiles
	if dirty.is_empty():
		if swept > 0:
			_texture.update(_image)
			queue_redraw()
		return
	var w: int = _state.width
	# The sweep and single-tile updates share one per-frame pixel budget.
	var allowed: int = maxi(200, MAX_PIXELS_PER_FRAME - swept)
	if dirty.size() <= allowed:
		for i: int in dirty.keys():
			@warning_ignore("integer_division")
			_image.set_pixel(i % w, i / w, _color_for_tile(i))
		dirty.clear()
	else:
		var n: int = 0
		for i: int in dirty.keys():
			@warning_ignore("integer_division")
			_image.set_pixel(i % w, i / w, _color_for_tile(i))
			dirty.erase(i)
			n += 1
			if n >= allowed:
				break
	_texture.update(_image)
	queue_redraw()


# Repaints the next band of rows of a full repaint (MAX_PIXELS_PER_FRAME
# pixels' worth). Returns how many pixels it painted.
func _sweep_step() -> int:
	if _sweep_row < 0:
		return 0
	var w: int = _state.width
	@warning_ignore("integer_division")
	var rows: int = maxi(1, MAX_PIXELS_PER_FRAME / w)
	var end_row: int = mini(_state.height, _sweep_row + rows)
	for y in range(_sweep_row, end_row):
		var row: int = y * w
		for x in range(w):
			_image.set_pixel(x, y, _color_for_tile(row + x))
	var painted: int = (end_row - _sweep_row) * w
	_sweep_row = end_row if end_row < _state.height else -1
	return painted


# Whether the image was last painted with the colour-blind palette.
func uses_colorblind() -> bool:
	return _painted_colorblind


# Repaint every tile (after the colour-blind setting changes).
func repaint_all() -> void:
	if _state == null or _image == null:
		return
	_paint_all()
	_texture.update(_image)
	queue_redraw()


func texture() -> Texture2D:
	return _texture


func world_size() -> Vector2:
	if _state == null:
		return Vector2.ZERO
	return Vector2(_state.width, _state.height)


func _paint_all() -> void:
	_painted_colorblind = Settings.colorblind
	_land_colors.clear()
	_sweep_row = -1
	for i in range(_state.tile_count()):
		var p := _state.idx_to_xy(i)
		_image.set_pixel(p.x, p.y, _color_for_tile(i))


func _color_for_tile(i: int) -> Color:
	var base := _base_color_for_tile(i)
	if _state.flash_tiles.has(i) and _state.match_time < _state.flash_tiles[i]:
		return base.lerp(Color(1, 1, 1), 0.55)
	# Bombard: tiles inside an active bombard area look cracked.
	if _state.bombards.size() > 0:
		var pos := _state.idx_to_xy(i)
		var r2: int = Balance.BOMBARD_AREA_RADIUS_TILES * Balance.BOMBARD_AREA_RADIUS_TILES
		for b_v in _state.bombards:
			var b: Dictionary = b_v
			if _state.match_time >= float(b["until"]):
				continue
			var dx: int = pos.x - int(b["target_x"])
			var dy: int = pos.y - int(b["target_y"])
			if dx * dx + dy * dy <= r2:
				return base.lerp(Color(0.08, 0.06, 0.10), 0.45)
	return base


func _base_color_for_tile(i: int) -> Color:
	var t: int = _state.terrain[i]
	var owner_id: int = _state.owners[i]
	var terrain_color := _terrain_color(t)
	# Crown tiles overlay only while the Crown's rightful owner still holds the tile.
	if _state.crown_tiles.has(i):
		var crown_owner: int = _state.crown_tiles[i]
		if owner_id == crown_owner:
			var centre: int = _state.crown_centres.get(crown_owner, -1)
			if i == centre:
				return Color(0.98, 0.86, 0.22)
			return Palette.player(crown_owner).lightened(0.35)
	# Wall tile: dark stripe on top of the owner tint.
	if _state.wall_tiles.has(i) and owner_id == _state.wall_tiles[i]:
		return Color(0.08, 0.08, 0.10)
	# Building marker tile: strong tint by building type.
	if _state.building_at_tile.has(i):
		var b: Building = _state.building_at_tile[i]
		if b.owner_id == owner_id:
			return _building_color(b, owner_id)
	if owner_id == 0:
		return terrain_color
	var key: int = owner_id * 8 + t
	var c: Color
	if _land_colors.has(key):
		c = _land_colors[key]
	else:
		var base: Color = Balance.RUINS_COLOR if owner_id == GameState.RUINS_OWNER_ID else Palette.player(owner_id)
		c = base.lerp(terrain_color, Palette.owner_tint())
		_land_colors[key] = c
	if pattern != 0 and owner_id == pattern_owner:
		var shade: float = Progression.pattern_shade(pattern, i % _state.width, int(i / float(_state.width)))
		if shade > 0.0:
			c = c.darkened(shade)
	return c


func _building_color(b: Building, owner_id: int) -> Color:
	var owner_color := Palette.player(owner_id)
	match b.type:
		Balance.BUILDING_FORT:
			return owner_color.darkened(0.35)
		Balance.BUILDING_FORT2:
			return owner_color.darkened(0.55)
		Balance.BUILDING_BARRACKS:
			return owner_color.lightened(0.15).lerp(Color(0.75, 0.60, 0.35), 0.4)
		Balance.BUILDING_PORT:
			return Color(0.95, 0.95, 1.0).lerp(owner_color, 0.3)
		_:
			return owner_color


func _terrain_color(t: int) -> Color:
	if t < 0 or t >= Balance.TERRAIN_COLORS.size():
		return Color.BLACK
	return Balance.TERRAIN_COLORS[t]


func _draw() -> void:
	if not _ready_to_draw or _texture == null:
		return
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, Vector2(_state.width, _state.height)), false)
