class_name HudAttacks
extends PanelContainer

# The local player's running attacks. Tap one to retreat (75% comes back).

signal retreat_pressed(local_index: int)

const WIDTH: int = 300

var _buttons: Array[Button] = []
var _header: Label


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(4)
	add_child(v)
	_header = UI.label("Attacks — tap to retreat", 15, UI.COLOR_DIM)
	v.add_child(_header)
	for i in range(Balance.MAX_SIMULTANEOUS_ATTACKS):
		var b := UI.button("", WIDTH - 16, 48, 17)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void: retreat_pressed.emit(i))
		v.add_child(b)
		_buttons.append(b)


func apply_side(left_handed: bool) -> void:
	var bottom: float = -(UI.BOTTOM_BAR_H + UI.MARGIN * 2)
	var h: float = 30.0 + Balance.MAX_SIMULTANEOUS_ATTACKS * 52.0
	UI.dock_side(self, not left_handed, WIDTH, bottom - h, bottom, true)


func refresh(sim: Simulation, local: Player) -> void:
	var attacks: Array = sim.attacks_by(local.id) if local != null else []
	visible = not attacks.is_empty()
	for i in range(_buttons.size()):
		var b: Button = _buttons[i]
		if i >= attacks.size():
			b.visible = false
			continue
		var a: Attack = attacks[i]
		var def: Player = sim.state.get_player(a.defender_id)
		b.visible = true
		b.text = "⚔ %s   %d" % [def.display_name if def != null else "?", int(a.troops_remaining)]
		b.add_theme_color_override("font_color", Balance.color_for_player(a.defender_id).lightened(0.3))
