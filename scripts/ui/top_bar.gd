class_name TopBar
extends PanelContainer

# Top of the screen: Crown button, troop bar (green in the sweet spot),
# troops per second, land %, match timer, and the Menu button.

signal crown_double_tapped
signal crown_tapped_once
signal menu_pressed

const COLOR_SWEET: Color = Color(0.40, 0.95, 0.50)
const COLOR_NORMAL: Color = Color(0.95, 0.85, 0.35)
const COLOR_OVER: Color = Color(0.95, 0.40, 0.35)
const DOUBLE_TAP_SEC: float = 0.35

var _sim: Simulation
var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _bar_glow: ColorRect
var _troop_label: Label
var _per_sec_label: Label
var _land_label: Label
var _timer_label: Label
var _crown_button: Button
var _last_crown_tap: float = -10.0
var _time: float = 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_crown_button = UIStyle.button("", Balance.MIN_BUTTON_PX)
	_crown_button.custom_minimum_size = Vector2(Balance.MIN_BUTTON_PX + 8, Balance.MIN_BUTTON_PX)
	_crown_button.tooltip_text = "Double-tap to jump to your Crown"
	_crown_button.pressed.connect(_on_crown_pressed)
	var icon := IconView.new(IconView.Kind.CROWN, 40)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crown_button.add_child(icon)
	row.add_child(_crown_button)
	var bar_wrap := Control.new()
	bar_wrap.custom_minimum_size = Vector2(380, Balance.MIN_BUTTON_PX)
	bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar_wrap)
	_bar_glow = ColorRect.new()
	_bar_glow.color = Color(COLOR_SWEET, 0.0)
	_bar_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_glow.offset_left = -4
	_bar_glow.offset_top = 6
	_bar_glow.offset_right = 4
	_bar_glow.offset_bottom = -6
	_bar_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_bar_glow)
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.08, 0.08, 0.10)
	_bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_bg.offset_top = 10
	_bar_bg.offset_bottom = -10
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = COLOR_NORMAL
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.offset_top = 10
	_bar_fill.offset_bottom = -10
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_bar_fill)
	_troop_label = UIStyle.label("0 / 0", UIStyle.FONT_NORMAL)
	_troop_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_troop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_troop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_wrap.add_child(_troop_label)
	_per_sec_label = _stat("+0.0/s", 110)
	row.add_child(_per_sec_label)
	_land_label = _stat("0.0%", 90)
	row.add_child(_land_label)
	_timer_label = _stat("0:00", 210)
	row.add_child(_timer_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var menu := UIStyle.button("Menu", 120)
	menu.alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	row.add_child(menu)


func _stat(text: String, w: int) -> Label:
	var lbl := UIStyle.label(text, UIStyle.FONT_NORMAL)
	lbl.custom_minimum_size = Vector2(w, Balance.MIN_BUTTON_PX)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


# Where the troop bar is on screen (for the tutorial's arrow).
func troop_bar_rect() -> Rect2:
	return _bar_bg.get_global_rect()


func setup(sim: Simulation) -> void:
	_sim = sim


func _on_crown_pressed() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_crown_tap <= DOUBLE_TAP_SEC:
		_last_crown_tap = -10.0
		crown_double_tapped.emit()
	else:
		_last_crown_tap = now
		crown_tapped_once.emit()


func _process(delta: float) -> void:
	_time += delta


func update_view() -> void:
	if _sim == null:
		return
	var st: GameState = _sim.state
	var p: Player = st.get_player(_sim.local_player_id)
	if p != null:
		var cap: float = p.troop_cap()
		_troop_label.text = "%d / %d" % [int(p.troops), int(cap)]
		var ratio: float = p.troops / cap if cap > 0.0 else 0.0
		_bar_fill.anchor_right = clampf(ratio, 0.0, 1.0)
		var sweet: bool = ratio >= Balance.TROOP_BAR_SWEET_LOW and ratio <= Balance.TROOP_BAR_SWEET_HIGH
		_bar_fill.color = COLOR_OVER if p.troops > cap else (COLOR_SWEET if sweet else COLOR_NORMAL)
		_bar_glow.color = Color(COLOR_SWEET, (0.35 + 0.25 * sin(_time * 4.0)) if sweet else 0.0)
		var tps: float = p.troops_per_second_at(cap)
		if tps > 0.0:
			tps *= _sim.growth_multiplier(p)
		_per_sec_label.text = "%+.1f/s" % tps
		_land_label.text = "%.1f%%" % (100.0 * st.land_fraction(p))
	match st.phase:
		Balance.PHASE_PLACEMENT:
			_timer_label.text = "Place your Crown" if st.tutorial_rules else "Placement 0:%02d" % maxi(0, ceili(st.placement_time_left))
		Balance.PHASE_MATCH:
			if st.match_time < Balance.PEACE_PERIOD_SEC:
				_timer_label.text = "Peace ends %s" % GameState.format_time(Balance.PEACE_PERIOD_SEC - st.match_time)
			elif st.is_final_siege():
				_timer_label.text = "Final Siege %s" % GameState.format_time(st.match_time)
			else:
				_timer_label.text = GameState.format_time(st.match_time)
		_:
			_timer_label.text = GameState.format_time(st.match_time)
