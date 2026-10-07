class_name HudEnemyPanel
extends PanelContainer

# Long-press a rival's land: what you know about them, truce offers and the
# four spy actions. Everything about their troops comes through IntelOps, so
# this panel only ever shows what you have paid (or are allowed) to see.

signal offer_truce_requested(target_id: int)
signal spy_requested(target_id: int, action: int)

const WIDTH: int = 520

var target_id: int = -1
var _name: Label
var _info: Label
var _troops: Label
var _details: Label
var _truce_btn: Button
var _spy_buttons: Array[Button] = []


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	UI.centre(self, WIDTH, 100)
	var v := UI.vbox(8)
	add_child(v)
	_name = UI.label("", 24)
	v.add_child(_name)
	_info = UI.label("", 16, UI.COLOR_DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_info)
	_troops = UI.label("", 20, UI.COLOR_WARN)
	v.add_child(_troops)
	_details = UI.label("", 15)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_details)
	_truce_btn = UI.button("Offer truce", WIDTH - 28, 50)
	_truce_btn.pressed.connect(func() -> void:
		offer_truce_requested.emit(target_id))
	v.add_child(_truce_btn)
	v.add_child(UI.label("Spy (you may be caught — they'll know it was you)", 15, UI.COLOR_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	for action in range(4):
		var b := UI.button("", int((WIDTH - 36) * 0.5), 56, 15)
		b.pressed.connect(func() -> void: spy_requested.emit(target_id, action))
		grid.add_child(b)
		_spy_buttons.append(b)
	var close := UI.button("Close", WIDTH - 28, 44)
	close.pressed.connect(func() -> void: visible = false)
	v.add_child(close)
	visible = false


func open_for(id: int) -> void:
	target_id = id
	visible = true


func refresh(sim: Simulation, local: Player) -> void:
	if not visible or local == null:
		return
	var state: GameState = sim.state
	var target: Player = state.get_player(target_id)
	if target == null or not target.is_alive or not local.is_alive:
		visible = false
		return
	var now: float = state.match_time
	_name.text = target.display_name
	_name.add_theme_color_override("font_color", Balance.color_for_player(target.id).lightened(0.2))
	var info: Array[String] = ["Land %.1f%%" % (100.0 * state.land_fraction(target))]
	if target.is_bot:
		info.append(_personality_label(target.personality))
	if TrucesOps.is_oathbreaker(target, now) or target.refuses_all_truces:
		info.append("Oathbreaker")
	if TrucesOps.has_truce(local, target.id, now):
		info.append("Truce with you: %ds left" % int(ceilf(float(local.active_truces[target.id]) - now)))
	_info.text = "   •   ".join(info)
	_troops.text = _troop_text(IntelOps.troop_view(local, target, now))
	_details.text = _detail_text(sim, local, target)
	var blocker: String = TrucesOps.offer_blocker(sim, local.id, target.id)
	_truce_btn.text = "Offer truce" if blocker == "" else blocker
	_truce_btn.disabled = blocker != ""
	var catch_pct: int = int(round(IntelOps.catch_chance(target, now, state) * 100.0))
	for action in range(_spy_buttons.size()):
		var b: Button = _spy_buttons[action]
		var why: String = IntelOps.action_blocker(sim, local, target.id, action)
		var what: String = "%d troops • %d%% caught" % [int(IntelOps.action_cost(local, action)), catch_pct]
		b.text = "%s\n%s" % [IntelOps.action_label(action), why if why != "" else what]
		b.disabled = why != ""
		b.tooltip_text = _action_help(action)


func _troop_text(view: Dictionary) -> String:
	match String(view["kind"]):
		IntelOps.VIEW_LIVE:
			return "Troops: %d  (live, from your spy)" % int(view["value"])
		IntelOps.VIEW_RANGE:
			return "Troops: %d – %d  (scouted %ds ago)" % [int(view["low"]), int(view["high"]), int(view["age"])]
		IntelOps.VIEW_STALE:
			return "Troops: %d – %d  (old: %ds ago)" % [int(view["low"]), int(view["high"]), int(view["age"])]
		_:
			return "Troops: unknown — %s" % IntelOps.band_label(int(view["band"]))


func _detail_text(sim: Simulation, local: Player, target: Player) -> String:
	var state: GameState = sim.state
	var now: float = state.match_time
	var lines: Array[String] = []
	if IntelOps.has_live_spy(local, target.id, now):
		var cap: float = target.troop_cap()
		lines.append("Cap %d   Growth %+.1f/s   Keep %d" % [int(cap), target.troops_per_second_at(cap) * sim.growth_multiplier(target), target.keep_level])
		lines.append("Forts %d   Barracks %d   Watchtowers %d   Walls %d" % [target.fort_count, target.barracks_count, target.watchtower_count, target.wall_count])
		var cds: Array[String] = []
		for i in range(4):
			var cd: float = AbilitiesOps.cooldown_until(i, target)
			cds.append("%s %s" % [HudBottomBar.ABILITY_LABELS[i], ("%ds" % int(ceilf(cd - now))) if cd > now else "ready"])
		lines.append(", ".join(cds))
		lines.append("Truces: %d / %d" % [TrucesOps.active_truce_count(target, now), Balance.TRUCE_LIMIT])
	if IntelOps.has_plans(local, target.id, now):
		var fights: Array[String] = []
		for a: Attack in sim.attacks_by(target.id):
			var d: Player = state.get_player(a.defender_id)
			fights.append("%s (%d troops)" % [d.display_name if d != null else "?", int(a.troops_remaining)])
		lines.append("Attacking: %s" % (", ".join(fights) if not fights.is_empty() else "nobody"))
		var plan: Player = state.get_player(target.plan_target_id)
		if target.is_bot and plan != null and plan.is_alive:
			lines.append("Planning next: %s" % ("YOU" if plan == local else plan.display_name))
	return "\n".join(lines)


func _action_help(action: int) -> String:
	match action:
		Balance.SPY_SCOUT:
			return "Their troops as a range (±20%), one snapshot."
		Balance.SPY_SPY:
			return "Exact live troops, cap, buildings and cooldowns for %ds." % int(Balance.SPY_DURATION_SEC)
		Balance.SPY_SABOTAGE:
			return "Their building nearest you stops working for %ds." % int(Balance.SABOTAGE_DURATION_SEC)
		_:
			return "See who they're attacking and planning to attack for %ds." % int(Balance.PLANS_DURATION_SEC)


func _personality_label(p: int) -> String:
	match p:
		Balance.BOT_PERSONALITY_EXPANDER:
			return "Expander — grabs land, thin defenses"
		Balance.BOT_PERSONALITY_RAIDER:
			return "Raider — hits weak borders, overextends"
		Balance.BOT_PERSONALITY_TURTLE:
			return "Turtle — Forts and Walls, slow growth"
		Balance.BOT_PERSONALITY_OPPORTUNIST:
			return "Opportunist — picks on the busy, breaks truces"
		_:
			return ""
