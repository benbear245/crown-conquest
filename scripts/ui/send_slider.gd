class_name SendSlider
extends PanelContainer

# "Send X%" slider (10-100%) with thumb-sized 25 / 50 / 75 / 100% buttons.

signal fraction_changed(fraction: float)

const QUICK: Array[float] = [0.25, 0.50, 0.75, 1.00]

var fraction: float = 0.50
var _label: Label
var _slider: HSlider


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_label = UIStyle.label("Send 50%", UIStyle.FONT_NORMAL)
	_label.custom_minimum_size = Vector2(118, Balance.MIN_BUTTON_PX)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_label)
	_slider = HSlider.new()
	_slider.custom_minimum_size = Vector2(220, Balance.MIN_BUTTON_PX)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.min_value = Balance.SEND_MIN_FRACTION * 100.0
	_slider.max_value = Balance.SEND_MAX_FRACTION * 100.0
	_slider.step = 1.0
	_slider.value = fraction * 100.0
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.value_changed.connect(_on_value)
	# A fatter grabber is much easier to hit with a thumb.
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.85, 0.85, 0.9)
	grab.set_corner_radius_all(14)
	grab.content_margin_top = 14
	grab.content_margin_bottom = 14
	_slider.add_theme_stylebox_override("grabber_area", grab)
	_slider.add_theme_stylebox_override("grabber_area_highlight", grab)
	row.add_child(_slider)
	for f: float in QUICK:
		var b := UIStyle.button("%d%%" % int(f * 100.0), 72)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(func() -> void: _slider.value = f * 100.0)
		row.add_child(b)


func _on_value(v: float) -> void:
	fraction = v / 100.0
	_label.text = "Send %d%%" % int(round(v))
	fraction_changed.emit(fraction)
