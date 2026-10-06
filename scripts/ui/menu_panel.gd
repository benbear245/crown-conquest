class_name MenuPanel
extends PanelContainer

# In-match menu: settings (layout, sound, music, vibration, colour-blind)
# and a fresh map. (The full pause menu comes with the menus.)

signal new_map_pressed

var settings_list: SettingsList


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)
	vbox.add_child(UIStyle.label("Menu", UIStyle.FONT_LARGE))
	settings_list = SettingsList.new(360)
	vbox.add_child(settings_list)
	var hints := UIStyle.button("Show tips again", 360)
	hints.alignment = HORIZONTAL_ALIGNMENT_CENTER
	hints.pressed.connect(func() -> void: Settings.reset_hints(); visible = false)
	vbox.add_child(hints)
	var new_map := UIStyle.button("New map", 360)
	new_map.alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_map.pressed.connect(func() -> void: visible = false; new_map_pressed.emit())
	vbox.add_child(new_map)
	var close := UIStyle.button("Close", 360)
	close.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.pressed.connect(func() -> void: visible = false)
	vbox.add_child(close)


func open() -> void:
	settings_list.refresh()
	visible = true
