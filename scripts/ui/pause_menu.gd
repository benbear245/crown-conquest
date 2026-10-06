class_name PauseMenu
extends ColorRect

# Pause menu: Resume, Restart, Settings, Quit. The game is paused while it's
# open (game.gd pauses the tree), so this node keeps processing on its own.

signal resume_pressed
signal restart_pressed
signal quit_pressed

var settings_list: SettingsList
var _main: VBoxContainer
var _settings: VBoxContainer
var _title: Label
var _subtitle: Label
var _confirm: String = ""          # "restart" / "quit" while asking "Are you sure?"
var _restart_button: Button
var _quit_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.5)
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UIStyle.panel()
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	_title = UIStyle.label("Paused", 36)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)
	_subtitle = UIStyle.label("", UIStyle.FONT_SMALL, UIStyle.COLOR_DIM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_subtitle)
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 10)
	vbox.add_child(_main)
	_main.add_child(_button("Resume", func() -> void: resume_pressed.emit()))
	_restart_button = _button("Restart", func() -> void: _ask("restart"))
	_main.add_child(_restart_button)
	_main.add_child(_button("Settings", func() -> void: _show_settings(true)))
	_quit_button = _button("Quit to menu", func() -> void: _ask("quit"))
	_main.add_child(_quit_button)
	_settings = VBoxContainer.new()
	_settings.add_theme_constant_override("separation", 10)
	_settings.visible = false
	vbox.add_child(_settings)
	settings_list = SettingsList.new(400)
	_settings.add_child(settings_list)
	_settings.add_child(_button("Show tips again", func() -> void: Settings.reset_hints(); _subtitle.text = "Tips will show again"))
	_settings.add_child(_button("Back", func() -> void: _show_settings(false)))


func _button(text: String, action: Callable) -> Button:
	var b := UIStyle.button(text, 400)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(action)
	return b


func open(subtitle: String = "") -> void:
	_confirm = ""
	_restart_button.text = "Restart"
	_quit_button.text = "Quit to menu"
	_subtitle.text = subtitle
	_show_settings(false)
	visible = true


func close() -> void:
	visible = false


func _show_settings(on: bool) -> void:
	_main.visible = not on
	_settings.visible = on
	_title.text = "Settings" if on else "Paused"
	if on:
		settings_list.refresh()


# Restart and Quit lose the current match, so they ask once more.
func _ask(what: String) -> void:
	if _confirm == what:
		_confirm = ""
		if what == "restart":
			restart_pressed.emit()
		else:
			quit_pressed.emit()
		return
	_confirm = what
	_restart_button.text = "Tap again to restart" if what == "restart" else "Restart"
	_quit_button.text = "Tap again to quit" if what == "quit" else "Quit to menu"
