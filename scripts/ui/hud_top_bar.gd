class_name HudTopBar
extends Control

# Top strip: troop bar (green in the growth sweet spot), troops per second,
# land %, match timer, active modifiers, and the menu button.

signal menu_pressed

const BAR_W: int = 380
const BAR_H: int = 34
const COLOR_SWEET: Color = Color(0.40, 0.95, 0.50)
const COLOR_NORMAL: Color = Color(0.95, 0.85, 0.35)
const COLOR_OVER: Color = Color(0.95, 0.40, 0.35)

var _bar_fill: ColorRect
var _troop_label: Label
var _per_sec: Label
var _land: Label
var _timer: Label
var _modifiers: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_left = UI.MARGIN
	offset_right = -UI.MARGIN
	offset_top = UI.MARGIN * 0.5
	offset_bottom = UI.MARGIN * 0.5 + UI.TOP_BAR_H + 26
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := UI.vbox(2)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var panel := UI.panel(8)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(panel)
	var row := UI.hbox(18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var bar_wrap := Control.new()
	bar_wrap.custom_minimum_size = Vector2(BAR_W, BAR_H)
	bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar_wrap)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(bg)
	# The sweet-spot band, faintly marked under the fill.
	var band := ColorRect.new()
	band.color = Color(COLOR_SWEET, 0.18)
	band.anchor_left = Balance.TROOP_BAR_SWEET_LOW
	band.anchor_right = Balance.TROOP_BAR_SWEET_HIGH
	band.anchor_bottom = 1.0
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(band)
	_bar_fill = ColorRect.new()
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_bar_fill)
	_troop_label = UI.label("0 / 0", 20)
	_troop_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_troop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_troop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_wrap.add_child(_troop_label)

	_per_sec = UI.label("+0.0/s", 20)
	_per_sec.custom_minimum_size = Vector2(100, 0)
	row.add_child(_per_sec)
	_land = UI.label("0.0%", 20)
	_land.custom_minimum_size = Vector2(90, 0)
	row.add_child(_land)
	_timer = UI.label("0:00", 20)
	_timer.custom_minimum_size = Vector2(200, 0)
	row.add_child(_timer)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var menu := UI.button("☰ Menu", 120, 44)
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	row.add_child(menu)

	_modifiers = UI.label("", 15, UI.COLOR_WARN)
	col.add_child(_modifiers)


func refresh(sim: Simulation, local: Player) -> void:
	var state: GameState = sim.state
	_update_timer(state)
	if local == null:
		return
	var cap: float = local.troop_cap()
	_troop_label.text = "%d / %d" % [int(local.troops), int(cap)]
	var ratio: float = local.troops / cap if cap > 0.0 else 0.0
	_bar_fill.anchor_right = clampf(ratio, 0.0, 1.0)
	if local.troops > cap:
		_bar_fill.color = COLOR_OVER
	elif ratio >= Balance.TROOP_BAR_SWEET_LOW and ratio <= Balance.TROOP_BAR_SWEET_HIGH:
		_bar_fill.color = COLOR_SWEET
	else:
		_bar_fill.color = COLOR_NORMAL
	var tps: float = local.troops_per_second_at(cap)
	if tps > 0.0:
		tps *= sim.growth_multiplier(local)
	_per_sec.text = "%+.1f/s" % tps
	_land.text = "%.1f%%" % (100.0 * state.land_fraction(local))
	_modifiers.text = _modifier_text(sim, local)


func _update_timer(state: GameState) -> void:
	match state.phase:
		Balance.PHASE_PLACEMENT:
			_timer.text = "Place Crown  0:%02d" % maxi(0, ceili(state.placement_time_left))
		Balance.PHASE_MATCH:
			if state.is_peace():
				_timer.text = "Peace ends  %s" % GameState.format_time(Balance.PEACE_PERIOD_SEC - state.match_time)
			elif state.is_final_siege():
				_timer.text = "Final Siege  %s" % GameState.format_time(state.match_time)
			else:
				_timer.text = GameState.format_time(state.match_time)
		_:
			_timer.text = GameState.format_time(state.match_time)


func _modifier_text(sim: Simulation, local: Player) -> String:
	var state: GameState = sim.state
	var now: float = state.match_time
	var parts: Array[String] = []
	if sim.is_underdog(local):
		parts.append("UNDERDOG +25% growth, -25% claim")
	var frac: float = state.land_fraction(local)
	if frac >= Balance.EMPIRE_UPKEEP_LAND_THRESHOLD_2:
		parts.append("EMPIRE UPKEEP -30% growth")
	elif frac >= Balance.EMPIRE_UPKEEP_LAND_THRESHOLD_1:
		parts.append("EMPIRE UPKEEP -15% growth")
	if TrucesOps.is_oathbreaker(local, now):
		parts.append("OATHBREAKER +20% attack cost")
	for s: Shrine in state.shrines:
		if s.holder_id == local.id:
			parts.append("%s: %s" % [Shrine.kind_label(s.kind), Shrine.kind_effect(s.kind)])
	if local.disinfo_until > now:
		parts.append("DISINFORMATION (you look %s) %ds" % ["strong" if local.disinfo_mult > 1.0 else "weak", int(ceilf(local.disinfo_until - now))])
	var rising: int = sim.rising_empire_id()
	if rising > 0 and rising != local.id:
		var rp: Player = state.get_player(rising)
		parts.append("Rising Empire: %s (-15%% to attack)" % rp.display_name)
	elif rising == local.id:
		parts.append("YOU are the Rising Empire — everyone's attacks on you cost less")
	return "   •   ".join(parts)
