class_name HudBottomBar
extends Control

# Bottom strip: Crown button (tap: Keep menu, double-tap: jump home), the send
# slider with 25/50/75/100% quick buttons, and the ability bar above it.

signal crown_tapped
signal crown_double_tapped
signal ability_pressed(ability_id: int)
signal ability_ready(ability_id: int)

const QUICK: Array[float] = [0.25, 0.50, 0.75, 1.00]
const DOUBLE_TAP_SEC: float = 0.35
const ABILITY_LABELS: Array[String] = ["Swift March", "Crown Shield", "Rally", "Bombard"]
const ABILITY_W: int = 150

var send_fraction: float = 0.5
var _row: HBoxContainer
var _crown_btn: Button
var _slider: HSlider
var _slider_label: Label
var _abilities: HBoxContainer
var _ability_buttons: Array[Button] = []
var _was_ready: Array[bool] = [false, false, false, false]
var _last_crown_tap: float = -10.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := UI.panel(8)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = UI.MARGIN
	panel.offset_right = -UI.MARGIN
	panel.offset_bottom = -UI.MARGIN
	panel.offset_top = -(UI.MARGIN + UI.BOTTOM_BAR_H)
	add_child(panel)
	_row = UI.hbox(12)
	panel.add_child(_row)
	_crown_btn = UI.button("♛ Crown", 130)
	_crown_btn.pressed.connect(_on_crown_pressed)
	_row.add_child(_crown_btn)
	_slider_label = UI.label("Send 50%", 20)
	_slider_label.custom_minimum_size = Vector2(120, UI.BUTTON_H)
	_slider_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row.add_child(_slider_label)
	_slider = HSlider.new()
	_slider.custom_minimum_size = Vector2(220, UI.BUTTON_H)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.min_value = Balance.SEND_MIN_FRACTION * 100.0
	_slider.max_value = Balance.SEND_MAX_FRACTION * 100.0
	_slider.step = 1.0
	_slider.value = send_fraction * 100.0
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.value_changed.connect(func(v: float) -> void: _set_fraction(v / 100.0, false))
	_row.add_child(_slider)
	for frac in QUICK:
		var b := UI.button("%d%%" % int(frac * 100.0), 76)
		b.pressed.connect(func() -> void: _set_fraction(frac, true))
		_row.add_child(b)

	_abilities = UI.hbox(8)
	_abilities.anchor_left = 0.5
	_abilities.anchor_right = 0.5
	_abilities.anchor_top = 1.0
	_abilities.anchor_bottom = 1.0
	var total_w: float = ABILITY_W * 4 + 8 * 3
	_abilities.offset_left = -total_w * 0.5
	_abilities.offset_right = total_w * 0.5
	_abilities.offset_bottom = -(UI.MARGIN * 2 + UI.BOTTOM_BAR_H)
	_abilities.offset_top = _abilities.offset_bottom - 64
	add_child(_abilities)
	for i in range(4):
		var b := UI.button(ABILITY_LABELS[i], ABILITY_W, 64, 16)
		b.pressed.connect(func() -> void: ability_pressed.emit(i))
		_abilities.add_child(b)
		_ability_buttons.append(b)


# Left-handed: the Crown button and quick buttons swap ends of the bar.
func apply_side(left_handed: bool) -> void:
	var order: Array[Node] = [_crown_btn, _slider_label, _slider]
	var quick: Array[Node] = []
	for c in _row.get_children():
		if not order.has(c):
			quick.append(c)
	var seq: Array[Node] = []
	if left_handed:
		seq.append_array(quick)
		seq.append_array([_slider, _slider_label, _crown_btn])
	else:
		seq.append_array(order)
		seq.append_array(quick)
	for i in range(seq.size()):
		_row.move_child(seq[i], i)


func _set_fraction(frac: float, move_slider: bool) -> void:
	send_fraction = clampf(frac, Balance.SEND_MIN_FRACTION, Balance.SEND_MAX_FRACTION)
	if move_slider:
		_slider.set_value_no_signal(send_fraction * 100.0)
	_slider_label.text = "Send %d%%" % int(round(send_fraction * 100.0))


func _on_crown_pressed() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_crown_tap <= DOUBLE_TAP_SEC:
		_last_crown_tap = -10.0
		crown_double_tapped.emit()
		return
	_last_crown_tap = now
	crown_tapped.emit()


func refresh(sim: Simulation, local: Player) -> void:
	var now: float = sim.state.match_time
	var in_match: bool = sim.state.phase == Balance.PHASE_MATCH
	for i in range(_ability_buttons.size()):
		var btn: Button = _ability_buttons[i]
		if local == null or not local.is_alive or not in_match:
			btn.disabled = true
			btn.text = ABILITY_LABELS[i]
			_was_ready[i] = false
			continue
		var cd_until: float = AbilitiesOps.cooldown_until(i, local)
		var unlock: float = AbilitiesOps.unlock_sec(i)
		var cost: float = AbilitiesOps.cost_now(i, local)
		var state_label: String
		if now < unlock:
			state_label = "🔒 %s" % GameState.format_time(unlock - now)
		elif AbilitiesOps.is_active(i, local, now):
			state_label = "ACTIVE"
		elif i == AbilitiesOps.ID_CROWN_SHIELD and sim.state.is_final_siege():
			state_label = "off in Siege"
		elif cd_until > now:
			state_label = "%ds" % int(ceilf(cd_until - now))
		elif cost > 0.0:
			state_label = "%d troops" % int(cost)
		else:
			state_label = "ready"
		btn.text = "%s\n%s" % [ABILITY_LABELS[i], state_label]
		var can_use: bool = AbilitiesOps.is_ready(i, local, sim) and (cost <= 0.0 or local.troops >= cost)
		btn.disabled = not can_use
		if can_use and not _was_ready[i] and now > 1.0:
			ability_ready.emit(i)
		_was_ready[i] = can_use
