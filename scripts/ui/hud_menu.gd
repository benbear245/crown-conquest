class_name HudMenu
extends PanelContainer

# Pause / settings menu: resume, new map, and the settings toggles.

signal resume_pressed
signal new_map_pressed

const WIDTH: int = 440
const TOGGLES: Array[Array] = [
	["sound", "Sound effects"],
	["music", "Music"],
	["vibration", "Vibration"],
	["colorblind", "Colour-blind palette"],
	["left_handed", "Left-handed layout"],
]

var _checks: Dictionary = {}


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(16)
	add_theme_stylebox_override("panel", sb)
	UI.centre(self, WIDTH, 100)
	var v := UI.vbox(10)
	add_child(v)
	v.add_child(UI.label("Paused", 28))
	var resume := UI.button("Resume", WIDTH - 32)
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	v.add_child(resume)
	var new_map := UI.button("New map", WIDTH - 32)
	new_map.pressed.connect(func() -> void: new_map_pressed.emit())
	v.add_child(new_map)
	v.add_child(UI.label("Settings", 18, UI.COLOR_DIM))
	for t in TOGGLES:
		var key: String = t[0]
		var cb := CheckButton.new()
		cb.text = t[1]
		cb.custom_minimum_size = Vector2(WIDTH - 32, 48)
		cb.add_theme_font_size_override("font_size", 18)
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
		v.add_child(cb)
		_checks[key] = cb
	var hints := UI.button("Show tips again", WIDTH - 32, 48, 16)
	hints.pressed.connect(func() -> void: Settings.reset_hints())
	v.add_child(hints)
	visible = false


func open() -> void:
	for key: String in _checks.keys():
		(_checks[key] as CheckButton).set_pressed_no_signal(bool(Settings.get(key)))
	visible = true
