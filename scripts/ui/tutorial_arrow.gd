class_name TutorialArrow
extends Control

# A bouncing arrow (and a pulsing ring) pointing at a spot on the screen.
# Off-screen targets get an arrow at the screen edge pointing their way.

const EDGE_MARGIN: float = 90.0

var target: Vector2 = Vector2(-1, -1)     # screen position; x < 0 = hidden
var ring_radius: float = 34.0
var _time: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


# True if the target is on screen (not clamped to an edge).
func target_on_screen() -> bool:
	return target.x >= 0.0 and Rect2(Vector2.ZERO, size).grow(-EDGE_MARGIN * 0.5).has_point(target)


func _draw() -> void:
	if target.x < 0.0:
		return
	var view := Rect2(Vector2.ZERO, size).grow(-EDGE_MARGIN)
	var gold := Color(1.0, 0.85, 0.25)
	var bounce: float = 10.0 * (0.5 + 0.5 * sin(_time * 6.0))
	if view.has_point(target):
		var pulse: float = 0.5 + 0.5 * sin(_time * 5.0)
		draw_arc(target, ring_radius + 6.0 * pulse, 0.0, TAU, 40, Color(gold, 0.9), 5.0, true)
		# Arrow comes from above (or below, near the top of the screen).
		var dir := Vector2(0, 1) if target.y > 220.0 else Vector2(0, -1)
		_arrow(target - dir * (ring_radius + 18.0 + bounce), dir, gold)
	else:
		var clamped := Vector2(clampf(target.x, view.position.x, view.end.x), clampf(target.y, view.position.y, view.end.y))
		var dir2: Vector2 = (target - clamped).normalized()
		_arrow(clamped - dir2 * bounce, dir2, gold)


# Arrow with its tip at `tip`, pointing along `dir`.
func _arrow(tip: Vector2, dir: Vector2, col: Color) -> void:
	var side := Vector2(-dir.y, dir.x)
	var base: Vector2 = tip - dir * 34.0
	var head := PackedVector2Array([tip, base + side * 22.0, base - side * 22.0])
	draw_colored_polygon(head, col)
	draw_polyline(PackedVector2Array([tip, base + side * 22.0, base - side * 22.0, tip]), Color(0.15, 0.1, 0.0), 3.0, true)
	draw_line(base, base - dir * 46.0, col, 14.0, true)
