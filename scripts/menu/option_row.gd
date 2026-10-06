class_name OptionRow
extends HBoxContainer

# "Label:  [A] [B] [C]" — one choice from a short list, thumb-sized.

signal changed(index: int)

var selected: int = 0
var _buttons: Array[Button] = []


func _init(title: String, options: Array, initial: int = 0, button_width: int = 170) -> void:
	add_theme_constant_override("separation", 10)
	var lbl := UIStyle.label(title, 22)
	lbl.custom_minimum_size = Vector2(230, 0)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(lbl)
	var group := ButtonGroup.new()
	for i in range(options.size()):
		var b := UIStyle.choice_button(str(options[i]), button_width)
		b.button_group = group
		var index: int = i
		b.pressed.connect(func() -> void: select(index); changed.emit(index))
		add_child(b)
		_buttons.append(b)
	select(initial)


func select(index: int) -> void:
	selected = clampi(index, 0, _buttons.size() - 1)
	for i in range(_buttons.size()):
		_buttons[i].set_pressed_no_signal(i == selected)


func button(index: int) -> Button:
	return _buttons[index]
