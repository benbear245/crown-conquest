extends RefCounted

# Prompt 11 checks: difficulty table (think speed, send amounts, tools,
# special rules), personalities, move scoring, and the stalled-attack fix.


func run(t: SmokeTest) -> void:
	_send_ranges(t)
	_pick_noise(t)
	_stalled_attack(t)
	_hard_retreat(t)
	_easy_spares_your_crown(t)
	_bot_match_behaviour(t)


func _send_ranges(t: SmokeTest) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var p := Player.new()
	var expect: Array[Vector2] = [Vector2(0.20, 0.40), Vector2(0.30, 0.60), Vector2(0.40, 0.80)]
	for d in range(3):
		p.difficulty = d
		p.personality = Balance.BOT_PERSONALITY_EXPANDER
		p.troops = 5000.0
		p.land = 1000
		var lo: float = 1.0
		var hi: float = 0.0
		for i in range(400):
			var f: float = Bots.send_fraction(p, rng)
			lo = minf(lo, f)
			hi = maxf(hi, f)
		t.check(lo >= expect[d].x - 0.001 and hi <= expect[d].y + 0.001, "difficulty %d sends %.2f-%.2f (design %.0f-%.0f%%)" % [d, lo, hi, expect[d].x * 100, expect[d].y * 100])
	p.difficulty = Balance.BOT_DIFFICULTY_NORMAL
	p.personality = Balance.BOT_PERSONALITY_RAIDER
	t.check(is_equal_approx(Bots.send_fraction(p, rng, true), 0.60), "Raiders attack with the top of their range (overextend)")


func _pick_noise(t: SmokeTest) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var p := Player.new()
	var counts: Array[int] = [0, 0, 0]
	for d in range(3):
		p.difficulty = d
		for i in range(2000):
			var moves: Array[Dictionary] = [{"type": "a", "score": 90.0}, {"type": "b", "score": 50.0}, {"type": "c", "score": 10.0}]
			Bots._reorder_by_difficulty(p, moves, rng)
			if moves[0].type != "a":
				counts[d] += 1
	# Easy: 20% random move (2/3 of those aren't the best), Normal 10%, Hard 0%.
	t.check(counts[0] > 180 and counts[0] < 360, "Easy takes a worse/random move %.1f%% of the time" % (counts[0] / 20.0))
	t.check(counts[1] > 120 and counts[1] < 280, "Normal takes its 2nd-best move %.1f%% of the time" % (counts[1] / 20.0))
	t.check(counts[2] == 0, "Hard always takes its best move")


func _new_sim(match_seed: int) -> Simulation:
	var sim := Simulation.new()
	sim.headless = true
	sim.start_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, match_seed)
	return sim


# An attack that can't pay for any tile ends and returns 75% (like a retreat).
func _stalled_attack(t: SmokeTest) -> void:
	var sim: Simulation = _new_sim(42)
	while sim.state.match_time < 90.0:
		sim.advance_tick()
	var st: GameState = sim.state
	var a_p: Player = st.players[1]
	var front: Dictionary = {}
	var d_id: int = -1
	for p: Player in st.players:
		if p.id != a_p.id and p.is_alive:
			front = CombatOps.build_attack_front(st, a_p.id, p.id)
			if not front.is_empty():
				d_id = p.id
				break
	if d_id < 0:
		t.check(true, "(no bordering bots — stalled-attack check skipped)")
		return
	st.get_player(d_id).troops = 50000.0   # make every tile very expensive
	st.attacks.clear()
	var atk := Attack.new()
	atk.attacker_id = a_p.id
	atk.defender_id = d_id
	atk.troops_remaining = 10.0
	atk.troops_sent = 10.0
	atk.front = front
	atk.advance_timer = 0.01
	st.attacks.append(atk)
	var before: float = a_p.troops
	# A ring is spread over the ticks of one ring interval; run one full ring.
	for k in range(CombatOps.ring_ticks()):
		CombatOps.tick_attacks(sim)
	t.check(not st.attacks.has(atk), "a stalled attack ends instead of blocking a slot forever")
	t.check(is_equal_approx(a_p.troops - before, 7.5), "...and 75%% of what's left comes back (+%.1f)" % (a_p.troops - before))


func _hard_retreat(t: SmokeTest) -> void:
	var sim: Simulation = _new_sim(43)
	while sim.state.match_time < 90.0:
		sim.advance_tick()
	var st: GameState = sim.state
	var hard: Player = st.players[2]
	hard.is_bot = true
	hard.difficulty = Balance.BOT_DIFFICULTY_HARD
	st.attacks.clear()
	var atk := Attack.new()
	atk.attacker_id = hard.id
	atk.defender_id = st.players[3].id
	atk.troops_remaining = 400.0
	atk.front = {0: true}
	atk.stalled_rings = Balance.BOT_HARD_RETREAT_STALLED_RINGS
	atk.advance_timer = 99.0
	st.attacks.append(atk)
	var before: float = hard.troops
	Bots._housekeeping(sim, hard, BotScan.scan(sim, hard))
	t.check(not st.attacks.has(atk) and is_equal_approx(hard.troops - before, 300.0), "Hard retreats from a losing attack (+75%)")


# Easy bots never take your Crown zone before 4:00 (you, the human, are passive).
func _easy_spares_your_crown(t: SmokeTest) -> void:
	var sim: Simulation = _new_sim(44)
	sim.state.players[0].is_bot = false
	for i in range(1, sim.state.players.size()):
		sim.state.players[i].difficulty = Balance.BOT_DIFFICULTY_EASY
	while sim.state.phase == Balance.PHASE_PLACEMENT:
		sim.advance_tick()
	var me: Player = sim.state.players[0]
	TerritoryOps.claim_circle(sim, me, me.crown_x, me.crown_y, 22)   # land outside the Crown zone to fight over
	var r2: int = me.crown_zone_radius() * me.crown_zone_radius()
	var my_zone: PackedInt32Array = PackedInt32Array()   # zone tiles we own at the start
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			if dx * dx + dy * dy <= r2 and sim.state.in_bounds(me.crown_x + dx, me.crown_y + dy):
				var ti: int = sim.state.idx(me.crown_x + dx, me.crown_y + dy)
				if sim.state.owners[ti] == me.id:
					my_zone.append(ti)
	var zone_lost: int = 0
	var attacked: bool = false
	while sim.state.match_time < Balance.BOT_EASY_NO_CROWN_ATTACK_BEFORE_SEC - 1.0 and me.is_alive:
		me.troops = 0.0   # the weakest neighbour around: Easy bots want this land
		sim.advance_tick()
		for a: Attack in sim.state.attacks:
			attacked = attacked or a.defender_id == me.id
		for ti: int in my_zone:
			if sim.state.owners[ti] != me.id:
				zone_lost += 1
	t.check(attacked, "Easy bots do attack a weak human player")
	t.check(me.is_alive and zone_lost == 0, "...but leave your Crown zone alone before 4:00 (%d zone tiles lost)" % zone_lost)


# A Mixed bot match: who uses what (design difficulty table) and personality hints.
func _bot_match_behaviour(t: SmokeTest) -> void:
	var by_diff: Array[Dictionary] = [{}, {}, {}]
	var by_pers: Array[Dictionary] = [{}, {}, {}, {}]
	var keep_max: Array[int] = [0, 0, 0]
	for match_seed in [51, 52, 53]:
		var sim: Simulation = _new_sim(match_seed)
		var mix: Array[int] = [0, 0, 0, 1, 1, 1, 2, 2]
		for i in range(sim.state.players.size()):
			sim.state.players[i].is_bot = true
			sim.state.players[i].difficulty = mix[i]
			sim.state.players[i].personality = i % 4
		var ticks: int = 0
		while sim.state.phase != Balance.PHASE_ENDED and ticks < 6000:
			sim.advance_tick()
			sim.state.events.clear()
			ticks += 1
		for p: Player in sim.state.players:
			for k: String in p.bot_actions.keys():
				by_diff[p.difficulty][k] = int(by_diff[p.difficulty].get(k, 0)) + int(p.bot_actions[k])
				by_pers[p.personality][k] = int(by_pers[p.personality].get(k, 0)) + int(p.bot_actions[k])
			for ab: int in p.abilities_used.keys():
				by_diff[p.difficulty]["ability%d" % ab] = 1
			keep_max[p.difficulty] = maxi(keep_max[p.difficulty], p.keep_level)
	print("[smoke]   moves by difficulty: Easy %s\n[smoke]     Normal %s\n[smoke]     Hard %s" % [by_diff[0], by_diff[1], by_diff[2]])
	var easy: Dictionary = by_diff[0]
	t.check(not easy.has("barracks") and not easy.has("keep") and not easy.has("wall") and not easy.has("ability0"), "Easy: Forts at most, no Barracks / Keep / Walls / abilities")
	var normal: Dictionary = by_diff[1]
	t.check(not normal.has("wall") and not normal.has("port") and not normal.has("fort2") and not normal.has("ability2") and not normal.has("ability3") and keep_max[1] <= 1,
		"Normal: Forts, Barracks, Keep 1, Swift March, Crown Shield only")
	t.check(int(by_diff[2].get("attack", 0)) > 0 and (by_diff[2].has("ability2") or by_diff[2].has("ability3")), "Hard: attacks and uses Rally / Bombard")
	var attack_share: Array[float] = []
	for pd: Dictionary in by_pers:
		var total: float = 0.0
		for k: String in pd.keys():
			total += float(pd[k])
		attack_share.append(float(pd.get("attack", 0)) / maxf(total, 1.0))
	print("[smoke]   attack share by personality (Exp/Raid/Turt/Opp): %s" % [attack_share])
	t.check(int(by_pers[Balance.BOT_PERSONALITY_TURTLE].get("fort", 0)) >= int(by_pers[Balance.BOT_PERSONALITY_EXPANDER].get("fort", 0)), "Turtles build at least as many Forts as Expanders")
