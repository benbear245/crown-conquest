class_name AllyPanel
extends PanelContainer

# Teams: your ally at a glance and the "Send 20% to ally" button.

signal send_pressed

var _sim: Simulation
var _label: Label
var _button: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)
	_label = UIStyle.label("", UIStyle.FONT_SMALL + 1)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_label)
	_button = UIStyle.button("Send 20% to ally", 300)
	_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button.pressed.connect(func() -> void: send_pressed.emit())
	vbox.add_child(_button)


func setup(sim: Simulation) -> void:
	_sim = sim


func update_view() -> void:
	if _sim == null:
		return
	var st: GameState = _sim.state
	var me: Player = st.get_player(_sim.local_player_id)
	var ally: Player = _sim.ally_of(me)
	visible = st.teams_mode and me != null and me.is_alive and ally != null and st.phase == Balance.PHASE_MATCH
	mouse_filter = Control.MOUSE_FILTER_PASS if visible else Control.MOUSE_FILTER_IGNORE
	if not visible:
		return
	if ally.is_alive:
		_label.text = "Ally: %s — %s troops, %.1f%% land" % [ally.display_name, GameState.format_int(int(ally.troops)), 100.0 * st.land_fraction(ally)]
	else:
		_label.text = "Ally: %s has fallen" % ally.display_name
	var reason: String = _sim.send_to_ally_block_reason(me)
	_button.disabled = reason != ""
	if reason == "":
		_button.text = "Send 20%% to ally (%s)" % GameState.format_int(int(floorf(me.troops * Balance.ALLY_SEND_FRACTION)))
	else:
		_button.text = "Send 20%% to ally — %s" % reason
