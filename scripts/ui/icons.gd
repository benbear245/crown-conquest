class_name Icons
extends RefCounted

# Small vector icons drawn with CanvasItem calls, so they look the same on
# every phone (no emoji or font glyphs needed). `c` is the icon's centre and
# `s` its half-size; call these from a node's _draw().

const GOLD: Color = Color(0.98, 0.84, 0.25)
const EDGE: Color = Color(0.12, 0.08, 0.02)


static func crown(ci: CanvasItem, c: Vector2, s: float, col: Color = GOLD) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-1.0, 0.65) * s, c + Vector2(-1.0, -0.35) * s, c + Vector2(-0.5, 0.1) * s,
		c + Vector2(0.0, -0.75) * s, c + Vector2(0.5, 0.1) * s, c + Vector2(1.0, -0.35) * s,
		c + Vector2(1.0, 0.65) * s,
	])
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, EDGE, s * 0.12, true)


static func star(ci: CanvasItem, c: Vector2, s: float, col: Color = GOLD) -> void:
	var pts := PackedVector2Array()
	for k in range(10):
		var ang: float = -PI * 0.5 + PI * float(k) / 5.0
		var r: float = s if k % 2 == 0 else s * 0.45
		pts.append(c + Vector2(cos(ang), sin(ang)) * r)
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, EDGE, s * 0.1, true)


static func white_flag(ci: CanvasItem, c: Vector2, s: float) -> void:
	ci.draw_line(c + Vector2(-0.6, -1.0) * s, c + Vector2(-0.6, 1.0) * s, Color(0.85, 0.75, 0.55), s * 0.18, true)
	var cloth := PackedVector2Array([
		c + Vector2(-0.55, -0.95) * s, c + Vector2(0.9, -0.75) * s,
		c + Vector2(0.75, -0.1) * s, c + Vector2(-0.55, 0.0) * s,
	])
	ci.draw_colored_polygon(cloth, Color.WHITE)
	cloth.append(cloth[0])
	ci.draw_polyline(cloth, EDGE, s * 0.1, true)


static func arrow(ci: CanvasItem, c: Vector2, s: float, up: bool, col: Color) -> void:
	var d: float = -1.0 if up else 1.0
	var pts := PackedVector2Array([
		c + Vector2(0, d) * s, c + Vector2(0.85, 0.05 * d) * s, c + Vector2(0.35, 0.05 * d) * s,
		c + Vector2(0.35, -d) * s, c + Vector2(-0.35, -d) * s, c + Vector2(-0.35, 0.05 * d) * s,
		c + Vector2(-0.85, 0.05 * d) * s,
	])
	ci.draw_colored_polygon(pts, col)


static func gem(ci: CanvasItem, c: Vector2, s: float) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-0.6, -0.6) * s, c + Vector2(0.6, -0.6) * s, c + Vector2(1.0, -0.15) * s,
		c + Vector2(0.0, 1.0) * s, c + Vector2(-1.0, -0.15) * s,
	])
	ci.draw_colored_polygon(pts, Color(0.75, 0.45, 0.95))
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(0.95, 0.85, 1.0), s * 0.1, true)


static func broken_shield(ci: CanvasItem, c: Vector2, s: float) -> void:
	var col := Color(0.95, 0.35, 0.3)
	var pts := PackedVector2Array([
		c + Vector2(0, -1.0) * s, c + Vector2(0.85, -0.65) * s, c + Vector2(0.8, 0.2) * s,
		c + Vector2(0, 1.0) * s, c + Vector2(-0.8, 0.2) * s, c + Vector2(-0.85, -0.65) * s,
	])
	ci.draw_colored_polygon(pts, Color(col, 0.5))
	pts.append(pts[0])
	ci.draw_polyline(pts, col, s * 0.14, true)
	ci.draw_polyline(PackedVector2Array([c + Vector2(0.05, -1.0) * s, c + Vector2(-0.2, -0.2) * s,
		c + Vector2(0.2, 0.2) * s, c + Vector2(-0.05, 1.0) * s]), Color.BLACK, s * 0.14, true)


static func skull(ci: CanvasItem, c: Vector2, s: float) -> void:
	ci.draw_circle(c + Vector2(0, -0.15) * s, s * 0.75, Color(0.8, 0.8, 0.8))
	ci.draw_rect(Rect2(c + Vector2(-0.4, 0.3) * s, Vector2(0.8, 0.55) * s), Color(0.8, 0.8, 0.8))
	ci.draw_circle(c + Vector2(-0.3, -0.15) * s, s * 0.2, Color.BLACK)
	ci.draw_circle(c + Vector2(0.3, -0.15) * s, s * 0.2, Color.BLACK)
