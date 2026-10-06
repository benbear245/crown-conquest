class_name TutorialCard
extends PanelContainer

# The tutorial's instruction card: "Step 2 of 7", the instruction, and Skip
# (or the end-of-tutorial buttons).

signal skip_pressed
signal primary_pressed       # "Play a Skirmish" / "Try again"
signal menu_pressed

var _step: Label
var _text: Label
var _skip: Button
var _primary: Button
var _menu: Button


func _ready() -> void:
	var sb := UIStyle.panel_style(12)
	sb.bg_color = Color(0.10, 0.09, 0.05, 0.94)
	sb.border_color = Color(1.0, 0.85, 0.25)
	sb.set_border_width_all(3)
	add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	_step = UIStyle.label("", UIStyle.FONT_SMALL, Color(1.0, 0.85, 0.35))
	col.add_child(_step)
	_text = UIStyle.label("", 21)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(420, 0)
	col.add_child(_text)
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(buttons)
	_skip = _make_button("Skip tutorial", buttons, func() -> void: skip_pressed.emit())
	_primary = _make_button("", buttons, func() -> void: primary_pressed.emit())
	_menu = _make_button("Main menu", buttons, func() -> void: menu_pressed.emit())
	show_step("", "", false)


func _make_button(text: String, parent: Control, action: Callable) -> Button:
	var b := UIStyle.button(text, 200)
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func show_step(step_text: String, text: String, finished: bool, primary: String = "") -> void:
	_step.text = step_text
	_text.text = text
	_skip.visible = not finished
	_primary.visible = finished and primary != ""
	_primary.text = primary
	_menu.visible = finished


func current_text() -> String:
	return _text.text
