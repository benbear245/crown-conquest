class_name IconView
extends Control

# A Control that just draws one of the Icons. Used inside rows and badges.

enum Kind { NONE, CROWN, STAR, FLAG, UP, DOWN, GEM, BROKEN, SKULL }

var kind: int = Kind.NONE:
	set(value):
		if kind != value:
			kind = value
			queue_redraw()
var tint: Color = Color.WHITE:
	set(value):
		if tint != value:
			tint = value
			queue_redraw()


func _init(icon_kind: int = Kind.NONE, px: float = 20.0) -> void:
	kind = icon_kind
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var s: float = minf(size.x, size.y) * 0.42
	match kind:
		Kind.CROWN:
			Icons.crown(self, c, s)
		Kind.STAR:
			Icons.star(self, c, s, Color(1.0, 0.55, 0.25))
		Kind.FLAG:
			Icons.white_flag(self, c, s)
		Kind.UP:
			Icons.arrow(self, c, s, true, tint)
		Kind.DOWN:
			Icons.arrow(self, c, s, false, tint)
		Kind.GEM:
			Icons.gem(self, c, s)
		Kind.BROKEN:
			Icons.broken_shield(self, c, s)
		Kind.SKULL:
			Icons.skull(self, c, s)
