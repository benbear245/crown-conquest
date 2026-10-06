class_name CustomizePreview
extends Control

# Live preview of your look: a patch of land in your colour and pattern with
# your Crown in the middle, your title and level underneath.

const TILES: Vector2i = Vector2i(44, 26)

var color: Color = Color(0.25, 0.55, 1.0)
var pattern: int = 0
var crown: int = 0
var _terrain: PackedByteArray = PackedByteArray()


func _init() -> void:
	custom_minimum_size = Vector2(TILES) * 11.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# A fixed little landscape (plains / forest / hills) to sit under the land.
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.12
	_terrain.resize(TILES.x * TILES.y)
	for y in range(TILES.y):
		for x in range(TILES.x):
			var n: float = noise.get_noise_2d(x, y)
			_terrain[y * TILES.x + x] = Balance.TERRAIN_FOREST if n > 0.25 else (Balance.TERRAIN_HILLS if n < -0.3 else Balance.TERRAIN_PLAINS)


func set_look(c: Color, p: int, cr: int) -> void:
	color = c
	pattern = p
	crown = cr
	queue_redraw()


func _draw() -> void:
	var cell: float = minf(size.x / TILES.x, size.y / TILES.y)
	var origin: Vector2 = (size - Vector2(TILES) * cell) * 0.5
	var centre: Vector2 = Vector2(TILES) * 0.5
	for y in range(TILES.y):
		for x in range(TILES.x):
			var terrain_c: Color = Balance.TERRAIN_COLORS[_terrain[y * TILES.x + x]]
			var d: float = (Vector2(x, y) + Vector2(0.5, 0.5) - centre).length()
			var wobble: float = 2.0 * sin(float(x) * 0.6) + 1.5 * cos(float(y) * 0.8)
			var c: Color = terrain_c
			if d < 10.0 + wobble:
				c = color.lerp(terrain_c, Palette.owner_tint()).darkened(Progression.pattern_shade(pattern, x, y))
			draw_rect(Rect2(origin + Vector2(x, y) * cell, Vector2(cell + 0.5, cell + 0.5)), c)
	var cc: Vector2 = origin + centre * cell
	draw_rect(Rect2(cc - Vector2(1.5, 1.5) * cell, Vector2(3, 3) * cell), color.lightened(0.35))
	Icons.crown_style(self, cc + Vector2(0, -0.2) * cell, cell * 1.6, crown)
