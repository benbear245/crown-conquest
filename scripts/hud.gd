class_name HUD
extends CanvasLayer

# Thumb-friendly HUD built in code so there is one scene file to look at.
# Only reads from GameState; never mutates it.

const QUICK_BUTTONS: Array[float] = [0.25, 0.50, 0.75, 1.00]
const MARGIN: int = 16
const BAR_HEIGHT: int = 32
const BAR_WIDTH: int = 440
const COLOR_SWEET: Color = Color(0.40, 0.95, 0.50)
const COLOR_NORMAL: Color = Color(0.95, 0.85, 0.35)
const COLOR_OVER: Color = Color(0.95, 0.40, 0.35)
const COLOR_TEXT: Color = Color(0.95, 0.95, 0.95)

signal new_map_pressed

var _state: GameState
var _send_fraction: float = 0.50

var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _troop_label: Label
var _per_sec_label: Label
var _land_label: Label
var _slider: HSlider
var _slider_label: Label
var _new_map_button: Button


func _ready() -> void:
	layer = 10
	_build_top()
	_build_bottom()


func setup(state: GameState) -> void:
	_state = state
	update_from_state()


func send_fraction() -> float:
	return _send_fraction


# --- Build (one-time) --------------------------------------------------------

func _build_top() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = MARGIN
	panel.offset_right = -MARGIN
	panel.offset_top = MARGIN
	panel.offset_bottom = MARGIN + BAR_HEIGHT + 16
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var bar_wrap := Control.new()
	bar_wrap.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar_wrap)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.08, 0.08, 0.10)
	_bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color = COLOR_NORMAL
	_bar_fill.anchor_left = 0.0
	_bar_fill.anchor_right = 0.0
	_bar_fill.anchor_top = 0.0
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.offset_left = 0.0
	_bar_fill.offset_right = 0.0
	_bar_fill.offset_top = 0.0
	_bar_fill.offset_bottom = 0.0
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_bar_fill)

	_troop_label = Label.new()
	_troop_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_troop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_troop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_troop_label.add_theme_color_override("font_color", COLOR_TEXT)
	_troop_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_troop_label.add_theme_constant_override("outline_size", 4)
	_troop_label.text = "0 / 0"
	_troop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_troop_label)

	_per_sec_label = _make_stat_label("+0.0/s", 120)
	row.add_child(_per_sec_label)
	_land_label = _make_stat_label("0.0% land", 130)
	row.add_child(_land_label)

	_new_map_button = Button.new()
	_new_map_button.text = "New map"
	_new_map_button.custom_minimum_size = Vector2(110, BAR_HEIGHT)
	_new_map_button.pressed.connect(func() -> void: new_map_pressed.emit())
	row.add_child(_new_map_button)


func _make_stat_label(initial: String, min_width: int) -> Label:
	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(min_width, BAR_HEIGHT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.text = initial
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _build_bottom() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = MARGIN
	panel.offset_right = -MARGIN
	panel.offset_bottom = -MARGIN
	panel.offset_top = -(Balance.MIN_BUTTON_PX + 32)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	_slider_label = Label.new()
	_slider_label.custom_minimum_size = Vector2(140, Balance.MIN_BUTTON_PX)
	_slider_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_slider_label.add_theme_color_override("font_color", COLOR_TEXT)
	_slider_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_slider_label.add_theme_constant_override("outline_size", 4)
	_slider_label.text = "Send 50%"
	_slider_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_slider_label)

	_slider = HSlider.new()
	_slider.custom_minimum_size = Vector2(240, Balance.MIN_BUTTON_PX)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.min_value = Balance.SEND_MIN_FRACTION * 100.0
	_slider.max_value = Balance.SEND_MAX_FRACTION * 100.0
	_slider.step = 1.0
	_slider.value = _send_fraction * 100.0
	_slider.value_changed.connect(_on_slider_changed)
	row.add_child(_slider)

	for i in range(QUICK_BUTTONS.size()):
		var frac: float = QUICK_BUTTONS[i]
		var btn := Button.new()
		btn.text = "%d%%" % int(frac * 100.0)
		btn.custom_minimum_size = Vector2(72, Balance.MIN_BUTTON_PX)
		var captured: float = frac
		btn.pressed.connect(func() -> void: _set_fraction(captured))
		row.add_child(btn)


# --- Updates (every frame) ---------------------------------------------------

func update_from_state() -> void:
	if _state == null or _state.players.is_empty():
		return
	var p: Player = _state.players[0]
	var cap: float = p.troop_cap()
	_troop_label.text = "%d / %d" % [int(p.troops), int(cap)]
	var ratio: float = 0.0
	if cap > 0.0:
		ratio = p.troops / cap
	var fill_fraction: float = clampf(ratio, 0.0, 1.0)
	_bar_fill.anchor_right = fill_fraction
	var in_sweet: bool = ratio >= Balance.TROOP_BAR_SWEET_LOW and ratio <= Balance.TROOP_BAR_SWEET_HIGH
	if p.troops > cap:
		_bar_fill.color = COLOR_OVER
	elif in_sweet:
		_bar_fill.color = COLOR_SWEET
	else:
		_bar_fill.color = COLOR_NORMAL
	var tps: float = p.troops_per_second_at(cap)
	_per_sec_label.text = "%+.1f/s" % tps
	var usable: int = _state.total_usable_tiles()
	var denom: float = float(maxi(usable, 1))
	var land_pct: float = 100.0 * float(p.land) / denom
	_land_label.text = "%.1f%% land" % land_pct


func _on_slider_changed(v: float) -> void:
	_send_fraction = v / 100.0
	_update_slider_label()


func _set_fraction(frac: float) -> void:
	_send_fraction = frac
	_slider.value = frac * 100.0
	_update_slider_label()


func _update_slider_label() -> void:
	_slider_label.text = "Send %d%%" % int(round(_send_fraction * 100.0))
