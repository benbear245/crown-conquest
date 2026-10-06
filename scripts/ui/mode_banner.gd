class_name ModeBanner
extends PanelContainer

# Shown while a targeting mode is active (Wall, Boat, Bombard, Crown move):
# a one-line hint, live feedback (e.g. the running wall cost), and buttons to
# confirm or leave the mode.

signal cancel_pressed
signal confirm_pressed

var _label: Label
var _confirm: Button
var _cancel: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_label = UIStyle.label("", UIStyle.FONT_NORMAL)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(360, 0)
	row.add_child(_label)
	_confirm = UIStyle.button("Confirm", 130)
	_confirm.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm.pressed.connect(func() -> void: confirm_pressed.emit())
	row.add_child(_confirm)
	_cancel = UIStyle.button("Cancel", 130)
	_cancel.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cancel.pressed.connect(func() -> void: cancel_pressed.emit())
	row.add_child(_cancel)


# confirm_text "" hides the confirm button.
func show_mode(text: String, cancel_text: String = "Cancel", confirm_text: String = "") -> void:
	_label.text = text
	_cancel.text = cancel_text
	_confirm.text = confirm_text
	_confirm.visible = confirm_text != ""
	visible = true


func set_text(text: String) -> void:
	_label.text = text


func set_confirm_enabled(enabled: bool) -> void:
	_confirm.disabled = not enabled


func hide_mode() -> void:
	visible = false
