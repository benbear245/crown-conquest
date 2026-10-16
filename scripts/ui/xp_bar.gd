class_name XpBar
extends Control

# Level and XP bar. animate_to() fills it up over a moment and rolls over
# into the next level, emitting level_up each time it does.

signal level_up(level: int)

const FILL: Color = Color(1.0, 0.80, 0.25)
const BG: Color = Color(0.16, 0.17, 0.22)

var _shown_xp: float = 0.0
var _info: Dictionary = {"level": 1, "into": 0, "need": 500}
var _font_size: int = 16


func _init(h: float = 26.0, font_size: int = 16) -> void:
	custom_minimum_size = Vector2(200, h)
	_font_size = font_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_total(xp: int) -> void:
	_shown_xp = float(xp)
	_info = Progression.level_info(xp)
	queue_redraw()


func animate_to(from_xp: int, to_xp: int, seconds: float = 1.6) -> void:
	set_total(from_xp)
	if to_xp <= from_xp:
		return
	var tw := create_tween()
	tw.tween_method(_set_shown, float(from_xp), float(to_xp), seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _set_shown(v: float) -> void:
	var old_level: int = int(_info["level"])
	_shown_xp = v
	_info = Progression.level_info(int(v))
	if int(_info["level"]) > old_level:
		level_up.emit(int(_info["level"]))
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, BG)
	var frac: float = clampf(float(_info["into"]) / float(maxi(int(_info["need"]), 1)), 0.0, 1.0)
	draw_rect(Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), FILL)
	draw_rect(r, Color(0, 0, 0, 0.6), false, 2.0)
	var font: Font = get_theme_default_font()
	var text: String = "Level %d   %d / %d XP" % [int(_info["level"]), int(_info["into"]), int(_info["need"])]
	var y: float = (size.y + float(_font_size) * 0.7) * 0.5
	draw_string_outline(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, _font_size, 4, Color.BLACK)
	draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, _font_size, Color.WHITE)
