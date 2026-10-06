class_name MenuPanel
extends PanelContainer

# In-match menu: layout options and a fresh map. (The full pause menu and
# settings screen come with the menus.)

signal new_map_pressed

var _hand_button: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)
	vbox.add_child(UIStyle.label("Menu", UIStyle.FONT_LARGE))
	_hand_button = UIStyle.button("", 360)
	_hand_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hand_button.pressed.connect(func() -> void: Settings.set_value("left_handed", not Settings.left_handed); _refresh())
	vbox.add_child(_hand_button)
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
	_refresh()


func open() -> void:
	_refresh()
	visible = true


func _refresh() -> void:
	_hand_button.text = "Layout: %s-handed" % ("Left" if Settings.left_handed else "Right")
