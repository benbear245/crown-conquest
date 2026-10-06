class_name AttackList
extends PanelContainer

# Your running attacks (up to 3). Tap one to retreat: 75% comes back.

var _sim: Simulation
var _header: Label
var _rows: Array[Button] = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)
	_header = UIStyle.label("Attacks — tap to retreat (75% back)", UIStyle.FONT_SMALL)
	vbox.add_child(_header)
	for i in range(Balance.MAX_SIMULTANEOUS_ATTACKS):
		var b := UIStyle.button("", 300)
		b.visible = false
		b.pressed.connect(func() -> void: _sim.player_retreat(_sim.local_player_id, i))
		vbox.add_child(b)
		_rows.append(b)


func setup(sim: Simulation) -> void:
	_sim = sim


func update_view() -> void:
	if _sim == null:
		return
	var attacks: Array[Attack] = _sim.attacks_by(_sim.local_player_id)
	visible = not attacks.is_empty()
	for i in range(_rows.size()):
		var b: Button = _rows[i]
		if i >= attacks.size():
			b.visible = false
			continue
		var a: Attack = attacks[i]
		var d: Player = _sim.state.get_player(a.defender_id)
		b.visible = true
		b.text = "Attacking %s — %d left" % [(d.display_name if d != null else "?"), int(a.troops_remaining)]
