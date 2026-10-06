class_name EnemyPanel
extends PanelContainer

# Long-press enemy land: who they are, how strong, and an Offer truce button.

signal offer_truce_requested(target_id: int)

var _sim: Simulation
var _target_id: int = -1
var _name: Label
var _stats: Label
var _offer: Button


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)
	_name = UIStyle.label("", UIStyle.FONT_LARGE)
	vbox.add_child(_name)
	_stats = UIStyle.label("", UIStyle.FONT_SMALL + 1)
	vbox.add_child(_stats)
	_offer = UIStyle.button("Offer truce", 380)
	_offer.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offer.pressed.connect(_on_offer_pressed)
	vbox.add_child(_offer)
	var close := UIStyle.button("Close", 380)
	close.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.pressed.connect(close_panel)
	vbox.add_child(close)


func setup(sim: Simulation) -> void:
	_sim = sim


func close_panel() -> void:
	visible = false
	_target_id = -1


func open_for(target_id: int) -> void:
	if _sim == null:
		return
	var target: Player = _sim.state.get_player(target_id)
	if target == null or not target.is_alive or target.id == _sim.local_player_id:
		return
	_target_id = target_id
	visible = true
	_refresh()


func _process(_delta: float) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	var state: GameState = _sim.state
	var target: Player = state.get_player(_target_id)
	if target == null or not target.is_alive or state.phase != Balance.PHASE_MATCH:
		close_panel()
		return
	var me: Player = state.get_player(_sim.local_player_id)
	var tags: Array[String] = []
	if _sim.rising_empire_id() == target.id:
		tags.append("Rising Empire: your attacks cost %d%% less" % int(Balance.RISING_EMPIRE_ATTACK_DISCOUNT * 100.0))
	if TrucesOps.is_oathbreaker(target, state.match_time) or target.oathbroken:
		tags.append("Oathbreaker")
	if me != null and TrucesOps.has_truce(me, target.id, state.match_time):
		tags.append("Truce with you: %s left" % GameState.format_time(TrucesOps.truce_time_left(me, target.id, state.match_time)))
	_name.text = target.display_name
	_stats.text = "%s\nLand %.1f%%   Troops %d   Truces %d/%d%s" % [
		personality_hint(target.personality), 100.0 * state.land_fraction(target), int(target.troops),
		TrucesOps.active_truce_count(target, state.match_time), Balance.TRUCE_LIMIT,
		("\n" + "  ·  ".join(tags)) if not tags.is_empty() else "",
	]
	var reason: String = "You're out" if me == null or not me.is_alive else TrucesOps.offer_block_reason(state, me, target)
	_offer.disabled = reason != ""
	_offer.text = "Offer truce (%ds, no attacks either way)" % int(Balance.TRUCE_DURATION_SEC) if reason == "" else reason


func _on_offer_pressed() -> void:
	if _target_id >= 0:
		offer_truce_requested.emit(_target_id)
	close_panel()


static func personality_hint(p: int) -> String:
	match p:
		Balance.BOT_PERSONALITY_EXPANDER:
			return "Expander — grabs land fast, thin defenses"
		Balance.BOT_PERSONALITY_RAIDER:
			return "Raider — hits weak borders, overextends"
		Balance.BOT_PERSONALITY_TURTLE:
			return "Turtle — Forts and Walls, slow growth"
		Balance.BOT_PERSONALITY_OPPORTUNIST:
			return "Opportunist — picks on the busy, may break truces"
	return ""
