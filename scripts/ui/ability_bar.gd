class_name AbilityBar
extends PanelContainer

# The four ability buttons. Each shows ACTIVE / cooldown / unlock time / cost.

signal ability_pressed(ability_id: int)

const LABELS: Array[String] = ["Swift March", "Crown Shield", "Rally", "Bombard"]

var _sim: Simulation
var _buttons: Array[Button] = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	for i in range(LABELS.size()):
		var btn := UIStyle.button(LABELS[i], 130)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		var id: int = i
		btn.pressed.connect(func() -> void: ability_pressed.emit(id))
		row.add_child(btn)
		_buttons.append(btn)


func setup(sim: Simulation) -> void:
	_sim = sim


func update_view() -> void:
	if _sim == null:
		return
	var me: Player = _sim.state.get_player(_sim.local_player_id)
	var now: float = _sim.state.match_time
	for i in range(_buttons.size()):
		var btn: Button = _buttons[i]
		if me == null or not me.is_alive or _sim.state.phase != Balance.PHASE_MATCH:
			btn.disabled = true
			btn.text = LABELS[i]
			continue
		var cd_until: float = AbilitiesOps.cooldown_until(i, me)
		var unlocked: bool = now >= AbilitiesOps.unlock_sec(i)
		var active: bool = AbilitiesOps.is_active(i, me, now)
		var cost: float = AbilitiesOps.cost_now(i, me)
		var state_label: String
		if not unlocked:
			state_label = "unlocks %s" % GameState.format_time(AbilitiesOps.unlock_sec(i))
		elif active:
			state_label = "ACTIVE"
		elif cd_until > now:
			state_label = "cd %ds" % int(ceilf(cd_until - now))
		elif cost > 0.0:
			state_label = "%d" % int(cost)
		else:
			state_label = "ready"
		btn.text = "%s\n%s" % [LABELS[i], state_label]
		btn.disabled = (not unlocked) or (cd_until > now) or (cost > 0.0 and me.troops < cost)
