class_name CosmeticArt
extends Control

# Draws one cosmetic choice: a colour swatch, a pattern sample, a Crown icon,
# or a victory-effect hint. Used inside the Customize buttons.

enum Kind { COLOR, PATTERN, CROWN, EFFECT }

var kind: int = Kind.COLOR
var index: int = 0
var locked: bool = false


func _init(art_kind: int, art_index: int) -> void:
	kind = art_kind
	index = art_index
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	var r := Rect2(Vector2(12, 8), size - Vector2(24, 40))
	match kind:
		Kind.COLOR:
			draw_rect(r, Progression.COLORS[index])
		Kind.PATTERN:
			var base: Color = Palette.player(1) if not Settings.colorblind else Color(0.45, 0.6, 0.9)
			var cell: float = 4.0
			var nx: int = int(r.size.x / cell)
			var ny: int = int(r.size.y / cell)
			for y in range(ny):
				for x in range(nx):
					var c: Color = base.darkened(Progression.pattern_shade(index, x, y))
					draw_rect(Rect2(r.position + Vector2(x, y) * cell, Vector2(cell, cell)), c)
		Kind.CROWN:
			Icons.crown_style(self, r.get_center() + Vector2(0, 4), minf(r.size.x, r.size.y) * 0.42, index)
		Kind.EFFECT:
			var cols: Array[Color] = [Color(1, 0.85, 0.3), Color(0.95, 0.35, 0.35), Color(0.4, 0.75, 1.0)]
			match index:
				0:
					draw_line(r.position + Vector2(r.size.x * 0.3, r.size.y * 0.5), r.end - Vector2(r.size.x * 0.3, r.size.y * 0.5), UIStyle.COLOR_DIM, 3.0)
				1:
					for k in range(12):
						var a: float = TAU * k / 12.0
						draw_line(r.get_center(), r.get_center() + Vector2(cos(a), sin(a)) * r.size.y * 0.42, cols[k % 3], 3.0)
				2:
					for k in range(10):
						var p: Vector2 = r.position + Vector2(fmod(k * 37.0, r.size.x), fmod(k * 23.0, r.size.y))
						draw_rect(Rect2(p, Vector2(7, 4)), cols[k % 3])
				3:
					for k in range(8):
						var p2: Vector2 = r.position + Vector2(fmod(k * 41.0, r.size.x), fmod(k * 29.0, r.size.y))
						draw_circle(p2, 5.0, Color(1, 0.82, 0.25))
	if locked:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
