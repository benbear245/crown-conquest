class_name XpPanel
extends VBoxContainer

# End-of-match progress: XP gained (with the breakdown), a bar that fills up
# level by level with a "LEVEL UP!" pop, what unlocked, and new achievements.

const FILL_SEC: float = 1.6
const BAR_SIZE: Vector2 = Vector2(500, 22)

var _gain: Label
var _lines: Label
var _level: Label
var _bar: Control
var _levelup: Label
var _unlocks: Label
var _achievements: Label
var _frac: float = 0.0
var _shown_level: int = 1
var _tween: Tween


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_CENTER
	visible = false
	_gain = _centered(UIStyle.label("", 30, Color(1.0, 0.86, 0.35)))
	_lines = _centered(UIStyle.label("", UIStyle.FONT_SMALL, UIStyle.COLOR_DIM))
	_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lines.custom_minimum_size = Vector2(BAR_SIZE.x, 0)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_level = UIStyle.label("", UIStyle.FONT_NORMAL)
	row.add_child(_level)
	_bar = Control.new()
	_bar.custom_minimum_size = BAR_SIZE
	_bar.draw.connect(_draw_bar)
	row.add_child(_bar)
	_levelup = _centered(UIStyle.label("LEVEL UP!", 34, Color(1.0, 0.92, 0.4)))
	_levelup.modulate.a = 0.0
	_unlocks = _centered(UIStyle.label("", UIStyle.FONT_SMALL + 1, UIStyle.COLOR_GOOD))
	_unlocks.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_unlocks.custom_minimum_size = Vector2(BAR_SIZE.x, 0)
	_achievements = _centered(UIStyle.label("", UIStyle.FONT_SMALL + 1, Color(1.0, 0.86, 0.35)))
	_achievements.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_achievements.custom_minimum_size = Vector2(BAR_SIZE.x, 0)


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(l)
	return l


func clear() -> void:
	visible = false
	if _tween != null:
		_tween.kill()


# summary: SaveData.record_match(); achievements: every one earned this match.
func play(summary: Dictionary, achievements: Array[String]) -> void:
	visible = true
	_gain.text = "+%s XP" % GameState.format_int(int(summary.xp))
	_lines.text = "  ·  ".join(summary.lines)
	_unlocks.text = ""
	var names: Array[String] = []
	for id: String in achievements:
		var a: Dictionary = Progression.achievement(id)
		names.append("%s (title \"%s\")" % [a.name, a.title])
	_achievements.text = ("Achievement: " + ", ".join(names)) if not names.is_empty() else ""
	_achievements.visible = not names.is_empty()
	_shown_level = int(summary.old_level)
	_levelup.modulate.a = 0.0
	_set_xp(float(summary.old_xp))
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_interval(0.4)
	_tween.tween_method(_set_xp, float(summary.old_xp), float(summary.new_xp), FILL_SEC).set_trans(Tween.TRANS_SINE)
	var unlocks: Array = summary.unlocks
	if not unlocks.is_empty():
		_tween.tween_callback(func() -> void: _unlocks.text = "Unlocked: " + ", ".join(unlocks))


func _set_xp(value: float) -> void:
	var info: Dictionary = Progression.level_info(int(value))
	_frac = float(info.into) / float(info.need)
	_level.text = "Level %d · %s" % [int(info.level), str(SaveData.cosmetic("title"))]
	_bar.queue_redraw()
	if int(info.level) > _shown_level:
		_shown_level = int(info.level)
		_pop_level_up(_shown_level)


func _pop_level_up(lvl: int) -> void:
	_levelup.text = "LEVEL UP!  Level %d" % lvl
	_levelup.pivot_offset = _levelup.size * 0.5
	_levelup.scale = Vector2(0.4, 0.4)
	_levelup.modulate.a = 1.0
	var t := create_tween().set_parallel(true)
	t.tween_property(_levelup, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.play("sfx_ability_ready", -2.0, 1.2)
	Settings.vibrate(120)


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	_bar.draw_rect(r, Color(0, 0, 0, 0.6))
	_bar.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(_frac, 0.0, 1.0), r.size.y)), Color(1.0, 0.8, 0.25))
	_bar.draw_rect(r, Color(1, 1, 1, 0.5), false, 2.0)


func level_up_shown() -> bool:
	return _levelup.modulate.a > 0.5
