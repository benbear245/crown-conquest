class_name AbilityBar
extends PanelContainer

# The four ability buttons along the bottom edge.

signal ability_pressed(ability_id: int)

const TITLES: Array[String] = ["Swift March", "Crown Shield", "Rally", "Bombard"]

var _sim: Simulation
var _buttons: Array[AbilityButton] = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	for i in range(TITLES.size()):
		var btn := AbilityButton.new()
		btn.ability_id = i
		btn.title = TITLES[i]
		btn.pressed.connect(func() -> void: ability_pressed.emit(i))
		row.add_child(btn)
		_buttons.append(btn)


func setup(sim: Simulation) -> void:
	_sim = sim


func button(ability_id: int) -> AbilityButton:
	return _buttons[ability_id]


func update_view() -> void:
	if _sim == null:
		return
	var me: Player = _sim.state.get_player(_sim.local_player_id)
	var now: float = _sim.state.match_time
	var in_match: bool = _sim.state.phase == Balance.PHASE_MATCH and me != null and me.is_alive
	for i in range(_buttons.size()):
		var btn: AbilityButton = _buttons[i]
		var unlock: float = AbilitiesOps.unlock_sec(i)
		btn.locked = now < unlock
		btn.unlock_text = "Unlocks %s" % GameState.format_time(unlock)
		if not in_match:
			btn.disabled = true
			btn.active_frac = 0.0
			btn.cooldown_frac = 0.0
			btn.cost_text = AbilitiesOps.cost_label(i)
			continue
		var cd_until: float = AbilitiesOps.cooldown_until(i, me)
		var cd_total: float = AbilitiesOps.cooldown_sec(i, me)
		btn.cooldown_left = maxf(0.0, cd_until - now)
		btn.cooldown_frac = clampf(btn.cooldown_left / cd_total, 0.0, 1.0) if cd_total > 0.0 else 0.0
		var active_until: float = AbilitiesOps.active_until(i, me)
		var dur: float = AbilitiesOps.duration_sec(i)
		btn.active_frac = clampf((active_until - now) / dur, 0.0, 1.0) if dur > 0.0 else 0.0
		var cost: float = AbilitiesOps.cost_now(i, me)
		btn.affordable = cost <= 0.0 or me.troops >= cost
		btn.cost_text = AbilitiesOps.cost_label(i) if cost <= 0.0 else "%s (%d)" % [AbilitiesOps.cost_label(i), int(cost)]
		var blocked_by_siege: bool = i == AbilitiesOps.ID_CROWN_SHIELD and _sim.state.is_final_siege()
		if blocked_by_siege:
			btn.cost_text = "Off in Final Siege"
		btn.disabled = btn.locked or btn.cooldown_left > 0.0 or not btn.affordable or blocked_by_siege
