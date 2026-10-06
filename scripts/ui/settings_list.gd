class_name SettingsList
extends VBoxContainer

# On/off buttons for every player setting. Used by the in-match menu and the
# Settings screen. Each tap flips the setting and saves it straight away.

const TOGGLES: Array = [
	["sound", "Sound"],
	["music", "Music"],
	["vibration", "Vibration"],
	["colorblind", "Colour-blind palette"],
]

var _hand_button: Button
var _buttons: Dictionary = {}   # setting key -> Button


func _init(width: int = 360) -> void:
	add_theme_constant_override("separation", 10)
	_hand_button = UIStyle.button("", width)
	_hand_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hand_button.pressed.connect(func() -> void: Settings.set_value("left_handed", not Settings.left_handed))
	add_child(_hand_button)
	for t: Array in TOGGLES:
		var key: String = t[0]
		var b := UIStyle.button("", width)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(func() -> void:
			Settings.set_value(key, not bool(Settings.get(key)))
			Audio.play("sfx_ui_tap", -8.0))
		add_child(b)
		_buttons[key] = b
	Settings.changed.connect(refresh)
	refresh()


func refresh() -> void:
	_hand_button.text = "Layout: %s-handed" % ("Left" if Settings.left_handed else "Right")
	for t: Array in TOGGLES:
		(_buttons[t[0]] as Button).text = "%s: %s" % [t[1], "On" if bool(Settings.get(t[0])) else "Off"]


func button_for(key: String) -> Button:
	return _hand_button if key == "left_handed" else _buttons.get(key, null)
