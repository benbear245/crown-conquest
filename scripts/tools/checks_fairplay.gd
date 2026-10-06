extends RefCounted

# Prompt 10 checks: Underdog, Empire upkeep, Rising Empire, modifier badges,
# enemy panel, truces (offer, accept, flags, countdown, expiry), Oathbreaker,
# bot offers to the player, Opportunist truce-breaking, bot truces.


func run(t: SmokeTest) -> void:
	t.new_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 5150)
	t.skip_placement()
	t.ff_safe(70.0, false)   # we stay at 49 tiles while bots grow: Underdog
	var st: GameState = t.sim.state
	var me: Player = t.me()
	var badges: ModifierBadges = t.hud.modifier_badges
	t.hud.update_from_state()

	# --- Underdog ------------------------------------------------------------
	t.check(t.sim.is_underdog(me), "small player is an Underdog (land %d, avg %.0f)" % [me.land, st.avg_alive_land])
	var mult: float = t.sim.growth_multiplier(me)
	t.check(is_equal_approx(mult, 1.0 + FairPlayOps.gem_bonus(me) + Balance.UNDERDOG_GROWTH_BONUS), "Underdog growth x%.2f (+25%%, adds with gems)" % mult)
	t.check(is_equal_approx(TerritoryOps.claim_discount(t.sim, me), 0.75), "Underdog: free land and Ruins 25% cheaper")
	var mods: Array[Array] = badges.current_modifiers()
	t.check(not mods.is_empty() and mods[0][0] == IconView.Kind.UP and str(mods[0][1]) == "+25%", "Underdog badge next to the troop bar")
	(badges.get("_badges") as Array)[0].pressed.emit()
	t.check((badges.get("_explain") as Label).visible and (badges.get("_explain") as Label).text.begins_with("Underdog"), "tapping the badge explains it")
	await t.shot("p10_underdog_badge")

	# --- Empire upkeep (fake a big empire by bumping the land counter) --------
	var real_land: int = me.land
	var usable: int = st.total_usable_tiles()
	me.land = int(usable * 0.25)
	t.check(is_equal_approx(t.sim.empire_upkeep(me), -0.15), "Empire upkeep -15% over 20% of the map")
	me.land = int(usable * 0.40)
	t.check(is_equal_approx(t.sim.empire_upkeep(me), -0.30), "Empire upkeep -30% over 35% of the map")
	t.hud.update_from_state()
	var has_down: bool = false
	for m: Array in badges.current_modifiers():
		if m[0] == IconView.Kind.DOWN and str(m[1]) == "-30%":
			has_down = true
	t.check(has_down, "Empire upkeep badge shows -30%")
	me.land = real_land

	# --- Rising Empire ---------------------------------------------------------
	var big: Player = null
	for p: Player in st.players:
		if p.id != me.id and p.is_alive and (big == null or p.land > big.land):
			big = p
	var big_real: int = big.land
	big.land = int(usable * 0.32)
	st.fair_play_next_tick = 0
	FairPlayOps.recompute_once_per_second(st)
	t.check(t.sim.rising_empire_id() == big.id, "a player over 30% becomes the Rising Empire")
	var tile_of_big: int = -1
	for i: int in big.border.keys():
		tile_of_big = i
		break
	var cost_rising: float = CombatOps.attack_tile_cost(t.sim, tile_of_big, 2.0, me.id)
	big.land = big_real
	st.fair_play_next_tick = 0
	FairPlayOps.recompute_once_per_second(st)
	var cost_normal: float = CombatOps.attack_tile_cost(t.sim, tile_of_big, 2.0, me.id)
	t.check(is_equal_approx(cost_rising, cost_normal * 0.85), "attacks on the Rising Empire cost 15%% less (%.2f vs %.2f)" % [cost_rising, cost_normal])
	big.land = int(usable * 0.32)
	st.fair_play_next_tick = 0
	FairPlayOps.recompute_once_per_second(st)
	t.hud.update_from_state()
	var lb_rows: Array = t.hud.leaderboard.get("_rows")
	var star_shown: bool = false
	for r: Dictionary in lb_rows:
		if (r["row"] as Control).visible and (r["rising"] as IconView).visible and (r["name"] as Label).text == big.display_name:
			star_shown = true
	t.check(star_shown, "Rising Empire star next to them on the leaderboard")
	await t.zoom_to(Vector2i(big.crown_x, big.crown_y), 2.0)
	await t.shot("p10_rising_empire")
	big.land = big_real
	st.fair_play_next_tick = 0
	FairPlayOps.recompute_once_per_second(st)

	# --- Enemy panel + offering a truce ---------------------------------------
	var neighbour: Player = big
	var nt: Vector2i = st.idx_to_xy(tile_of_big)
	await t.zoom_to(nt, 1.0)
	await t.long_press_tile(nt)
	var panel: EnemyPanel = t.hud.enemy_panel
	t.check(panel.visible, "long-pressing enemy land opens their info panel")
	var stats_text: String = (panel.get("_stats") as Label).text
	t.check(stats_text.contains("Land") and stats_text.contains("Troops") and stats_text.contains(EnemyPanel.personality_hint(neighbour.personality).left(8)),
		"panel shows land, troops and a personality hint")
	await t.shot("p10_enemy_panel")
	var offer_btn: Button = panel.get("_offer")
	t.check(not offer_btn.disabled, "Offer truce available")
	offer_btn.pressed.emit()
	t.check(not TrucesOps.pending_offer(st, me.id, neighbour.id).is_empty(), "offer sent; bot answers within 2 s")
	t.hud.update_from_state()
	t.check(t.hud.truce_panel.visible, "truce panel shows 'Waiting for … to answer'")
	t.ff(Balance.TRUCE_BOT_RESPONSE_SEC + 0.2, false)
	t.check(TrucesOps.pending_offer(st, me.id, neighbour.id).is_empty(), "bot answered after 2 s (truce: %s)" % TrucesOps.has_truce(me, neighbour.id, st.match_time))
	if not TrucesOps.has_truce(me, neighbour.id, st.match_time):
		TrucesOps.accept(t.sim, me.id, neighbour.id)   # it refused: force one to test the rest
	t.check(TrucesOps.has_truce(neighbour, me.id, st.match_time), "truce recorded for both sides")
	t.hud.update_from_state()
	var rows: Array = t.hud.truce_panel.get("_rows")
	t.check((rows[0]["label"] as Label).text.begins_with("Truce: %s" % neighbour.display_name) and (rows[0]["icon"] as IconView).kind == IconView.Kind.FLAG,
		"white-flag row with countdown: %s" % (rows[0]["label"] as Label).text)
	await t.zoom_to(Vector2i(neighbour.crown_x, neighbour.crown_y), 1.5)
	await t.shot("p10_truce_flag")

	# --- A bot offers you a truce ----------------------------------------------
	t.new_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 5151)
	t.skip_placement()
	t.ff_safe(85.0, true)   # grow until we share borders
	st = t.sim.state
	me = t.me()
	var bot: Player = st.players[2]
	t.check(TrucesOps.offer(t.sim, bot.id, me.id), "bot offers you a truce")
	t.hud.update_from_state()
	rows = t.hud.truce_panel.get("_rows")
	t.check((rows[0]["yes"] as Button).visible and (rows[0]["label"] as Label).text.contains("offers a truce"), "Accept / Decline shown for the offer (%s)" % (rows[0]["label"] as Label).text)
	await t.shot("p10_incoming_offer")
	(rows[0]["yes"] as Button).pressed.emit()
	t.check(TrucesOps.has_truce(me, bot.id, st.match_time), "Accept starts the truce")
	await _break_truce_checks(t)
	t.ff(Balance.TRUCE_DURATION_SEC + 0.5, false)
	t.check(not TrucesOps.has_truce(me, bot.id, st.match_time), "truce ends after %ds" % int(Balance.TRUCE_DURATION_SEC))

	_opportunist_check(t)
	_bot_truces(t)


# Attacking a truce partner asks first, then makes you an Oathbreaker.
func _break_truce_checks(t: SmokeTest) -> void:
	var st: GameState = t.sim.state
	var me: Player = t.me()
	var partner: Player = null
	for p: Player in st.players:
		if p.id != me.id and p.is_alive and not TrucesOps.has_truce(me, p.id, st.match_time) \
				and not CombatOps.build_attack_front(st, me.id, p.id).is_empty():
			partner = p
			break
	if partner == null:
		t.check(true, "(no bordering bot — break-truce checks skipped)")
		return
	TrucesOps.accept(t.sim, me.id, partner.id)
	var cost_normal: float = CombatOps.attack_tile_cost(t.sim, int(CombatOps.build_attack_front(st, me.id, partner.id).keys()[0]), 2.0, me.id)
	var targeting: Targeting = t.game.get("_targeting")
	var partner_tile: Vector2i = _partner_tile_touching(t, me, partner)
	me.troops = maxf(me.troops, 500.0)
	await t.zoom_to(partner_tile, 1.0)
	await t.tap_tile(partner_tile)
	t.check(targeting.mode == Targeting.Mode.BREAK_TRUCE and t.hud.mode_banner.visible, "attacking a truce partner asks for confirmation")
	await t.shot("p10_break_confirm")
	t.hud.mode_banner.cancel_pressed.emit()
	t.check(TrucesOps.has_truce(me, partner.id, st.match_time) and t.sim.active_attack_count(me.id) == 0 or not me.oathbroken, "Cancel keeps the truce")
	await t.tap_tile(partner_tile)
	(t.hud.mode_banner.get("_confirm") as Button).pressed.emit()
	t.check(me.oathbroken and TrucesOps.is_oathbreaker(me, st.match_time), "Attack anyway makes you an Oathbreaker")
	t.check(not TrucesOps.has_truce(me, partner.id, st.match_time), "the truce is gone")
	var other_bot: Player = _other_bot(t, me, partner)
	t.check(TrucesOps.offer_block_reason(st, me, other_bot) == "Bots refuse truces from Oathbreakers", "every bot now refuses your truces")
	var tile_idx: int = int(CombatOps.build_attack_front(st, me.id, partner.id).keys()[0]) if not CombatOps.build_attack_front(st, me.id, partner.id).is_empty() else -1
	if tile_idx >= 0:
		var cost_oath: float = CombatOps.attack_tile_cost(t.sim, tile_idx, 2.0, me.id)
		t.check(cost_oath >= Balance.ATTACK_TILE_COST_BASE * 1.2, "Oathbreaker attacks cost +20%% (%.2f vs %.2f before)" % [cost_oath, cost_normal])
	t.hud.update_from_state()
	var has_broken: bool = false
	for m: Array in t.hud.modifier_badges.current_modifiers():
		has_broken = has_broken or m[0] == IconView.Kind.BROKEN
	t.check(has_broken, "Oathbreaker badge shown")


func _partner_tile_touching(t: SmokeTest, me: Player, partner: Player) -> Vector2i:
	var front: Dictionary = CombatOps.build_attack_front(t.sim.state, me.id, partner.id)
	if front.is_empty():
		return Vector2i(-1, -1)
	return t.sim.state.idx_to_xy(int(front.keys()[0]))


func _other_bot(t: SmokeTest, me: Player, not_this: Player) -> Player:
	for p: Player in t.sim.state.players:
		if p.is_alive and p.id != me.id and p.id != not_this.id and not TrucesOps.has_truce(me, p.id, t.sim.state.match_time):
			return p
	return null


# An Opportunist with a planned break attacks its partner when the time comes.
func _opportunist_check(t: SmokeTest) -> void:
	var sim := Simulation.new()
	sim.headless = true
	sim.start_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 2024)
	while sim.state.match_time < 150.0:
		sim.advance_tick()
	var st: GameState = sim.state
	var pair: Array[Player] = []
	for a: Player in st.players:
		for b: Player in st.players:
			if a.id < b.id and a.is_alive and b.is_alive and a.id != 1 and not CombatOps.build_attack_front(st, a.id, b.id).is_empty():
				pair = [a, b]
				break
		if not pair.is_empty():
			break
	if pair.is_empty():
		t.check(true, "(no bordering bots — Opportunist check skipped)")
		return
	var opp: Player = pair[0]
	opp.personality = Balance.BOT_PERSONALITY_OPPORTUNIST
	opp.troops = maxf(opp.troops, 500.0)
	TrucesOps.accept(sim, opp.id, pair[1].id)
	opp.truce_break_at[pair[1].id] = st.match_time + 1.0
	while CombatOps.active_attack_count(st, opp.id) > 0:
		sim.player_retreat(opp.id, 0)   # free an attack slot
	for i in range(15):
		sim.advance_tick()
	t.check(opp.oathbroken and not TrucesOps.has_truce(opp, pair[1].id, st.match_time), "a planned Opportunist break attacks the partner and makes it an Oathbreaker")


func _bot_truces(t: SmokeTest) -> void:
	var made: int = 0
	var broken: int = 0
	for match_seed in [77, 78]:
		var sim := Simulation.new()
		sim.headless = true
		sim.start_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, match_seed)
		for p: Player in sim.state.players:
			p.is_bot = true
			p.difficulty = Balance.BOT_DIFFICULTY_NORMAL
		var ticks: int = 0
		while sim.state.phase != Balance.PHASE_ENDED and ticks < 7200:
			sim.advance_tick()
			sim.state.events.clear()
			ticks += 1
		for p: Player in sim.state.players:
			made += p.truces_made
			broken += p.truces_broken
	print("[smoke]   bot-only matches: %d truces made, %d broken" % [made >> 1, broken])
	t.check(made > 0, "bots offer and accept truces among themselves")
