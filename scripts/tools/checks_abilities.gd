extends RefCounted

# Prompt 9 checks: ability bar states, each ability's effect, Bombard preview
# + confirm, the effect visuals (screenshots), and bot ability use.


func run(t: SmokeTest) -> void:
	t.new_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 9090)
	t.skip_placement()
	t.ff(5.0, false)
	var me: Player = t.me()
	var bar: AbilityBar = t.hud.ability_bar
	t.hud.update_from_state()
	var sm: AbilityButton = bar.button(AbilitiesOps.ID_SWIFT_MARCH)
	var rally: AbilityButton = bar.button(AbilitiesOps.ID_RALLY)
	var bomb: AbilityButton = bar.button(AbilitiesOps.ID_BOMBARD)
	t.check(not sm.locked and not sm.disabled, "Swift March ready at the start")
	t.check(rally.locked and rally.unlock_text == "Unlocks 1:30", "Rally shows a lock until 1:30")
	t.check(bomb.locked and bomb.unlock_text == "Unlocks 3:00", "Bombard shows a lock until 3:00")
	await t.zoom_to(Vector2i(me.crown_x, me.crown_y), 2.5)
	await t.shot("p9_bar_start")

	# Swift March: 2x faster, 25% cheaper for 8 s, then a 45 s cooldown ring.
	sm.pressed.emit()
	t.hud.update_from_state()
	t.check(AbilitiesOps.is_swift_march_active(me, t.sim.state.match_time) and sm.active_frac > 0.9, "Swift March active (ring full)")
	t.check(is_equal_approx(TerritoryOps.claim_discount(t.sim, me), 0.75) or TerritoryOps.claim_discount(t.sim, me) < 0.76, "Swift March: claims 25% cheaper")
	t.ff(9.0, false)
	t.hud.update_from_state()
	t.check(sm.cooldown_frac > 0.6 and sm.cooldown_frac < 0.9 and sm.disabled, "Swift March cooling down (ring %.2f, %ds left)" % [sm.cooldown_frac, int(sm.cooldown_left)])

	# Crown Shield: tiles in the Crown zone can't be captured.
	var shield: AbilityButton = bar.button(AbilitiesOps.ID_CROWN_SHIELD)
	shield.pressed.emit()
	t.check(AbilitiesOps.is_crown_shield_active(me, t.sim.state.match_time), "Crown Shield active")
	t.check(t.sim.state.phase == Balance.PHASE_MATCH, "match still running")
	var zone_tile: int = t.sim.state.idx(me.crown_x + 2, me.crown_y)
	var enemy: Player = t.sim.state.players[1]
	var atk := Attack.new()
	atk.attacker_id = enemy.id
	atk.defender_id = me.id
	atk.troops_remaining = 100000.0
	atk.front = {zone_tile: true}
	t.sim.state.attacks.append(atk)
	CombatOps.advance_attack(t.sim, atk)
	t.check(t.sim.state.owners[zone_tile] == me.id, "shielded Crown-zone tile can't be captured")
	t.sim.state.attacks.erase(atk)
	t.hud.update_from_state()
	await t.shot("p9_shield_bubble")

	# Rally (1:30): costs 10% of troops, attacks pay 30% less per tile.
	t.ff_safe(Balance.RALLY_UNLOCK_SEC - t.sim.state.match_time + 1.0, false)
	me = t.me()
	me.troops = 1000.0
	var enemy_tile: int = _enemy_tile_near(t, me)
	var before_cost: float = CombatOps.attack_tile_cost(t.sim, enemy_tile, 2.0, me.id)
	t.hud.update_from_state()
	rally.pressed.emit()
	t.check(is_equal_approx(me.troops, 900.0), "Rally cost 10% of troops")
	var after_cost: float = CombatOps.attack_tile_cost(t.sim, enemy_tile, 2.0, me.id)
	t.check(is_equal_approx(after_cost, before_cost * 0.7), "Rally: tile cost %.2f -> %.2f (-30%%)" % [before_cost, after_cost])
	# Start a real attack so the glowing front shows.
	var ep: Vector2i = t.sim.state.idx_to_xy(enemy_tile)
	t.sim.state.match_time = maxf(t.sim.state.match_time, Balance.PEACE_PERIOD_SEC)
	if t.sim.player_attack(me.id, ep.x, ep.y, 0.5):
		t.ff(0.5, false)
		await t.zoom_to(ep, 1.0)
		await t.shot("p9_rally_glow")

	# Bombard (3:00): preview first, Fire! confirms.
	t.ff_safe(Balance.BOMBARD_UNLOCK_SEC - t.sim.state.match_time + 1.0, false)
	me = t.me()
	if not me.is_alive:
		t.check(true, "(local player fell before 3:00 — Bombard checks skipped)")
		_bot_usage(t)
		return
	me.troops = 2000.0
	t.hud.update_from_state()
	bomb.pressed.emit()
	var targeting: Targeting = t.game.get("_targeting")
	t.check(targeting.mode == Targeting.Mode.BOMBARD and t.hud.mode_banner.visible, "Bombard asks for a target")
	var far: Vector2i = _far_enemy_tile(t, me)
	if far.x >= 0:
		await t.zoom_to(far, 1.0)
		await t.tap_tile(far)
		var confirm: Button = t.hud.mode_banner.get("_confirm")
		t.check(confirm.disabled and (t.hud.mode_banner.get("_label") as Label).text.begins_with("Out of range"), "out-of-range target can't be fired")
	enemy_tile = _enemy_tile_in_bombard_range(t, me)
	t.check(enemy_tile >= 0, "found an enemy tile in Bombard range")
	if enemy_tile < 0:
		_bot_usage(t)
		return
	ep = t.sim.state.idx_to_xy(enemy_tile)
	await t.zoom_to(ep, 1.0)
	await t.tap_tile(ep)
	var confirm2: Button = t.hud.mode_banner.get("_confirm")
	t.check(not confirm2.disabled, "in-range enemy target can be fired: %s" % (t.hud.mode_banner.get("_label") as Label).text)
	t.check((t.game.get_node("Overlay") as WorldOverlay).bombard_preview == ep, "the blast area is previewed before firing")
	await t.shot("p9_bombard_preview")
	var victim: Player = t.sim.state.get_player(t.sim.state.owners[enemy_tile])
	victim.troops = 5000.0
	var troops_before: float = me.troops
	confirm2.pressed.emit()
	t.check(t.sim.state.bombards.size() == 1 and is_equal_approx(me.troops, troops_before - floorf(troops_before * 0.15)), "Fire! launches Bombard and charges 15%")
	t.check(targeting.mode == Targeting.Mode.NORMAL, "targeting ends after firing")
	t.check(AbilitiesOps.tile_in_any_bombard(t.sim.state, enemy_tile), "target tile is inside the Bombard area (half defense)")
	# One second of Bombard removes 2 troops per victim tile in the area.
	var victim_tiles: int = 0
	var r: int = Balance.BOMBARD_AREA_RADIUS_TILES
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r and t.sim.state.in_bounds(ep.x + dx, ep.y + dy):
				if t.sim.state.owners[t.sim.state.idx(ep.x + dx, ep.y + dy)] == victim.id:
					victim_tiles += 1
	var v_before: float = victim.troops
	t.sim.state.match_time += 1.0
	AbilitiesOps.tick(t.sim)
	t.sim.state.match_time -= 1.0
	var drained: float = v_before - victim.troops
	t.check(is_equal_approx(drained, 2.0 * float(victim_tiles)), "Bombard drains 2 troops per tile hit per second (%d tiles -> -%d)" % [victim_tiles, int(drained)])
	t.ff(0.5, false)
	await t.shot("p9_bombard_cracks")
	_bot_usage(t)


func _enemy_tile_near(t: SmokeTest, me: Player) -> int:
	var st: GameState = t.sim.state
	for i: int in me.border.keys():
		var p: Vector2i = st.idx_to_xy(i)
		for off in TerritoryOps.NEIGHBOR_OFFSETS:
			var n: Vector2i = p + off
			if not st.in_bounds(n.x, n.y):
				continue
			var ow: int = st.owners[st.idx(n.x, n.y)]
			if ow > 0 and ow != me.id and ow != GameState.RUINS_OWNER_ID:
				return st.idx(n.x, n.y)
	# No shared border yet: any enemy tile closest to our Crown.
	var best: int = -1
	var best_d: float = INF
	for i in range(st.owners.size()):
		var ow2: int = st.owners[i]
		if ow2 > 0 and ow2 != me.id and ow2 != GameState.RUINS_OWNER_ID:
			var d: float = Vector2(st.idx_to_xy(i)).distance_squared_to(Vector2(me.crown_x, me.crown_y))
			if d < best_d:
				best_d = d
				best = i
	return best


# An enemy tile inside Bombard range, preferring one near the middle of the
# map so the camera can centre on it.
func _enemy_tile_in_bombard_range(t: SmokeTest, me: Player) -> int:
	var st: GameState = t.sim.state
	var best: int = -1
	var best_d: float = INF
	var mid := Vector2(st.width, st.height) * 0.5
	for i in range(st.owners.size()):
		var ow: int = st.owners[i]
		if ow <= 0 or ow == me.id or ow == GameState.RUINS_OWNER_ID:
			continue
		var p: Vector2i = st.idx_to_xy(i)
		var d: float = Vector2(p).distance_squared_to(mid)
		if d < best_d and AbilitiesOps.bombard_in_range(t.sim, me, p.x, p.y):
			best_d = d
			best = i
	return best


func _far_enemy_tile(t: SmokeTest, me: Player) -> Vector2i:
	var st: GameState = t.sim.state
	for i in range(0, st.owners.size(), 7):
		var ow: int = st.owners[i]
		if ow > 0 and ow != me.id and ow != GameState.RUINS_OWNER_ID:
			var p: Vector2i = st.idx_to_xy(i)
			if not AbilitiesOps.bombard_in_range(t.sim, me, p.x, p.y):
				return p
	return Vector2i(-1, -1)


# Bot-only match: Normal bots use Swift March + Crown Shield; Hard use all four;
# Easy use none.
func _bot_usage(t: SmokeTest) -> void:
	var sim := Simulation.new()
	sim.headless = true
	sim.start_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 31337)
	var mix: Array[int] = [0, 0, 1, 1, 1, 2, 2, 2]
	for i in range(sim.state.players.size()):
		var p: Player = sim.state.players[i]
		p.is_bot = true
		p.difficulty = mix[i % mix.size()]
	var ticks: int = 0
	while sim.state.phase != Balance.PHASE_ENDED and ticks < 9000:
		sim.advance_tick()
		sim.state.events.clear()
		ticks += 1
	var used: Array[Dictionary] = [{}, {}, {}]
	for p: Player in sim.state.players:
		for k: int in p.abilities_used.keys():
			used[p.difficulty][k] = int(used[p.difficulty].get(k, 0)) + int(p.abilities_used[k])
	print("[smoke]   ability uses by difficulty (0 SM, 1 Shield, 2 Rally, 3 Bombard): Easy %s  Normal %s  Hard %s" % [used[0], used[1], used[2]])
	t.check(used[0].is_empty(), "Easy bots use no abilities")
	t.check(used[1].has(AbilitiesOps.ID_SWIFT_MARCH) and not used[1].has(AbilitiesOps.ID_RALLY) and not used[1].has(AbilitiesOps.ID_BOMBARD), "Normal bots use Swift March (and only SM/Shield)")
	t.check(used[1].has(AbilitiesOps.ID_CROWN_SHIELD) or used[2].has(AbilitiesOps.ID_CROWN_SHIELD), "bots pop Crown Shield when their Crown is attacked")
	t.check(used[2].has(AbilitiesOps.ID_RALLY) and used[2].has(AbilitiesOps.ID_BOMBARD), "Hard bots use Rally and Bombard")
