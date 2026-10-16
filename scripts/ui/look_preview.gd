class_name LookPreview
extends Control

# A patch of territory showing a look: colour, pattern, Crown icon, name and title.

const CELL: float = 22.0

var look: Dictionary = {}
var player_name: String = "Player"


func _init() -> void:
	custom_minimum_size = Vector2(CELL * 14, CELL * 11)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_look(l: Dictionary, name_: String) -> void:
	look = l
	player_name = name_
	queue_redraw()


func _draw() -> void:
	var col: Color = Cosmetics.COLORS[int(look.get(Cosmetics.CAT_COLOR, 0))]
	var grass: Color = Balance.TERRAIN_COLORS[Balance.TERRAIN_PLAINS]
	var tint: Color = col.lerp(grass, Balance.OWNER_TERRAIN_TINT)
	var pattern: int = int(look.get(Cosmetics.CAT_PATTERN, 0))
	var cols: int = int(size.x / CELL)
	var rows: int = int(size.y / CELL)
	for y in range(rows):
		for x in range(cols):
			draw_rect(Rect2(x * CELL, y * CELL, CELL, CELL), Look.patterned(tint, pattern, x, y))
	var centre := Vector2(size.x * 0.5, size.y * 0.5)
	draw_rect(Rect2(centre - Vector2(CELL * 1.5, CELL * 0.5), Vector2(CELL * 3, CELL * 3)), col.lightened(0.35))
	Look.draw_crown(self, int(look.get(Cosmetics.CAT_CROWN, 0)), centre + Vector2(0, -CELL * 1.2), CELL * 1.4, Color(1.0, 0.85, 0.2))
	var title: String = Cosmetics.TITLE_NAMES[int(look.get(Cosmetics.CAT_TITLE, 0))]
	var text: String = player_name if title == "" else "%s the %s" % [player_name, title]
	var font: Font = get_theme_default_font()
	draw_string_outline(font, Vector2(0, size.y - 14), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, 5, Color.BLACK)
	draw_string(font, Vector2(0, size.y - 14), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color.WHITE)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.7), false, 3.0)
