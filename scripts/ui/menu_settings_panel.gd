class_name MenuSettingsPanel
extends ColorRect

# Settings from the home screen: the same switches as the in-game menu,
# plus "Report a problem".

const W: int = 560

var _checks: Dictionary = {}
var _note: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.75)
	var panel := UI.card(UI.COLOR_DIM, 24)
	UI.centre(panel, W, 100)
	add_child(panel)
	var v := UI.vbox(10)
	panel.add_child(v)
	v.add_child(UI.label("Settings", 32, UI.COLOR_WARN))
	for t in HudMenu.TOGGLES:
		var key: String = t[0]
		var cb := CheckButton.new()
		cb.text = t[1]
		cb.custom_minimum_size = Vector2(W - 48, 52)
		cb.add_theme_font_size_override("font_size", 20)
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
		v.add_child(cb)
		_checks[key] = cb
	var tips := UI.outline_button("Show tips again", UI.COLOR_DIM, W - 48, 52, 18)
	tips.pressed.connect(func() -> void:
		Settings.reset_hints()
		_note.text = "Tips will show again in your next match.")
	v.add_child(tips)
	var report := UI.outline_button("Report a problem (copies details)", UI.COLOR_DIM, W - 48, 52, 18)
	report.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(BugReport.build_text())
		_note.text = "Copied! Paste it into your message to the developer, with what you were doing.")
	v.add_child(report)
	_note = UI.label("", 16, UI.COLOR_GOOD)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size = Vector2(W - 48, 0)
	v.add_child(_note)
	var close := UI.primary_button("Done", W - 48, UI.BUTTON_H, 22)
	close.pressed.connect(func() -> void: visible = false)
	v.add_child(close)
	visible = false


func open() -> void:
	_note.text = ""
	for key: String in _checks.keys():
		(_checks[key] as CheckButton).set_pressed_no_signal(bool(Settings.get(key)))
	visible = true
