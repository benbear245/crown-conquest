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


# The 8 Crown icons you can pick in Customize (Progression.CROWN_NAMES).
static func crown_style(ci: CanvasItem, c: Vector2, s: float, style: int, col: Color = GOLD) -> void:
	var w: float = s * 0.12
	match style:
		1:   # Tiara: a low arc with one tall middle point
			var pts := PackedVector2Array([c + Vector2(-1.0, 0.55) * s, c + Vector2(-1.0, 0.15) * s, c + Vector2(-0.45, -0.05) * s,
				c + Vector2(0.0, -0.85) * s, c + Vector2(0.45, -0.05) * s, c + Vector2(1.0, 0.15) * s, c + Vector2(1.0, 0.55) * s])
			_outlined(ci, pts, col, w)
			ci.draw_circle(c + Vector2(0.0, -0.2) * s, s * 0.16, Color(0.55, 0.85, 1.0))
		2:   # Laurel: a wreath of leaves, open at the top
			var green: Color = col.lerp(Color(0.55, 0.8, 0.3), 0.35)
			var centre: Vector2 = c + Vector2(0, -0.1) * s
			for side: float in [-1.0, 1.0]:
				for k in range(5):
					var ang: float = deg_to_rad(95.0 + 22.0 * k) if side < 0.0 else deg_to_rad(85.0 - 22.0 * k)
					var p: Vector2 = centre + Vector2(cos(ang), sin(ang)) * s * 0.78
					var along: Vector2 = Vector2(-sin(ang), cos(ang)) * side * -1.0
					var across: Vector2 = Vector2(cos(ang), sin(ang))
					var leaf := PackedVector2Array([p + along * s * 0.26, p + across * s * 0.11, p - along * s * 0.12, p - across * s * 0.11])
					_outlined(ci, leaf, green, w * 0.6)
			ci.draw_circle(centre + Vector2(0, 0.78) * s, s * 0.12, Color(0.9, 0.2, 0.25))
		3:   # Star crown: band with a star on top
			var band := PackedVector2Array([c + Vector2(-0.9, 0.65) * s, c + Vector2(-0.9, 0.15) * s, c + Vector2(0.9, 0.15) * s, c + Vector2(0.9, 0.65) * s])
			_outlined(ci, band, col, w)
			star(ci, c + Vector2(0, -0.35) * s, s * 0.6, col)
		4:   # Horned: band with two horns curving out
			var band2 := PackedVector2Array([c + Vector2(-0.7, 0.65) * s, c + Vector2(-0.7, 0.1) * s, c + Vector2(0.7, 0.1) * s, c + Vector2(0.7, 0.65) * s])
			_outlined(ci, band2, col, w)
			for side2: float in [-1.0, 1.0]:
				var horn := PackedVector2Array([c + Vector2(0.35 * side2, 0.15) * s, c + Vector2(0.75 * side2, 0.1) * s,
					c + Vector2(1.05 * side2, -0.4) * s, c + Vector2(0.95 * side2, -0.9) * s, c + Vector2(0.75 * side2, -0.35) * s])
				_outlined(ci, horn, Color(0.95, 0.92, 0.82), w)
		5:   # Jewel: the classic shape with three gems
			crown(ci, c, s, col)
			ci.draw_circle(c + Vector2(-0.55, 0.38) * s, s * 0.13, Color(0.9, 0.15, 0.2))
			ci.draw_circle(c + Vector2(0.0, 0.38) * s, s * 0.15, Color(0.2, 0.5, 1.0))
			ci.draw_circle(c + Vector2(0.55, 0.38) * s, s * 0.13, Color(0.15, 0.8, 0.4))
		6:   # Circlet: a thin band with one gem
			var ring := PackedVector2Array([c + Vector2(-1.0, 0.45) * s, c + Vector2(-0.9, 0.1) * s, c + Vector2(0.9, 0.1) * s,
				c + Vector2(1.0, 0.45) * s, c + Vector2(0.0, 0.3) * s])
			_outlined(ci, ring, col, w)
			ci.draw_circle(c + Vector2(0.0, 0.1) * s, s * 0.22, Color(0.75, 0.3, 0.95))
		7:   # Imperial: classic with an arch and a cross
			crown(ci, c, s, col)
			ci.draw_arc(c + Vector2(0, 0.0) * s, s * 0.75, PI * 1.15, PI * 1.85, 12, col, w * 1.4, true)
			ci.draw_line(c + Vector2(0, -1.15) * s, c + Vector2(0, -0.7) * s, col, w * 1.6, true)
			ci.draw_line(c + Vector2(-0.18, -0.98) * s, c + Vector2(0.18, -0.98) * s, col, w * 1.6, true)
		_:
			crown(ci, c, s, col)


static func _outlined(ci: CanvasItem, pts: PackedVector2Array, col: Color, w: float) -> void:
	ci.draw_colored_polygon(pts, col)
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, EDGE, w, true)
