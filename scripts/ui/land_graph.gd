class_name LandGraph
extends Control

# Line graph of the local player's land share over the match (recap screen).

var _samples: PackedFloat32Array = PackedFloat32Array()
var _sample_sec: float = 5.0
var _color: Color = Color(0.25, 0.55, 1.0)


func _init() -> void:
	custom_minimum_size = Vector2(560, 180)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(samples: PackedFloat32Array, sample_sec: float, color: Color) -> void:
	_samples = samples
	_sample_sec = sample_sec
	_color = color
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.04, 0.05, 0.08, 0.9))
	var font: Font = get_theme_default_font()
	var top: float = 10.0
	for s in _samples:
		top = maxf(top, s)
	top = ceilf(top / 10.0) * 10.0
	for g in range(1, 4):
		var gy: float = size.y * (1.0 - float(g) / 4.0)
		draw_line(Vector2(0, gy), Vector2(size.x, gy), Color(1, 1, 1, 0.08), 1.0)
	draw_string(font, Vector2(6, 18), "%d%%" % int(top), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.6))
	if _samples.size() < 2:
		draw_string(font, Vector2(0, size.y * 0.5), "Not enough match time to chart", HORIZONTAL_ALIGNMENT_CENTER, size.x, 16, Color(1, 1, 1, 0.5))
		return
	var end_sec: float = float(_samples.size() - 1) * _sample_sec
	draw_string(font, Vector2(0, size.y - 6), GameState.format_time(end_sec), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, 14, Color(1, 1, 1, 0.6))
	var line := PackedVector2Array()
	for i in range(_samples.size()):
		var x: float = size.x * float(i) / float(_samples.size() - 1)
		var y: float = size.y * (1.0 - _samples[i] / top)
		line.append(Vector2(x, y))
	# Fill under the line one strip at a time (a single polygon can fail to
	# triangulate when stretches sit flat on the bottom edge).
	var fill_col := Color(_color, 0.25)
	for i in range(line.size() - 1):
		if _samples[i] <= 0.0 and _samples[i + 1] <= 0.0:
			continue
		draw_primitive(PackedVector2Array([line[i], line[i + 1], Vector2(line[i + 1].x, size.y), Vector2(line[i].x, size.y)]),
			PackedColorArray([fill_col, fill_col, fill_col, fill_col]), PackedVector2Array())
	draw_polyline(line, _color.lightened(0.2), 3.0, true)
