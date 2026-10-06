class_name MenuScreen
extends VBoxContainer

# Base for the menu screens: a title and a "Back" helper. MenuRoot shows one
# screen at a time.

var root: MenuRoot


func _init(menu_root: MenuRoot, title: String) -> void:
	root = menu_root
	add_theme_constant_override("separation", 16)
	alignment = BoxContainer.ALIGNMENT_CENTER
	if title != "":
		var t := UIStyle.label(title, 44, Color(1.0, 0.9, 0.5))
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(t)


# Called each time the screen is shown.
func refresh() -> void:
	pass


func back_and_action_row(action_text: String, action: Callable, back_to: String = "main") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 20)
	var back := UIStyle.big_button("Back", 240)
	back.name = "Back"
	back.pressed.connect(func() -> void: root.show_screen(back_to))
	row.add_child(back)
	if action_text != "":
		var go := UIStyle.big_button(action_text, 320)
		go.name = "Action"
		go.pressed.connect(action)
		row.add_child(go)
	return row


static func text_block(text: String, width: int = 900, font_size: int = 20, color: Color = UIStyle.COLOR_TEXT) -> Label:
	var l := UIStyle.label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
