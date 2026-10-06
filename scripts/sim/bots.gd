class_name Bots
extends RefCounted

# Bot brain. Each think a bot scans its surroundings (BotScan), lists its
# possible moves with scores (BotMoves), and takes the best one, or by
# difficulty sometimes a worse or random one. Bots use exactly the same
# Simulation commands, costs and rules as the player: no hidden bonuses.


static func tick(sim: Simulation, player: Player) -> void:
	var state: GameState = sim.state
	# Ability thinking runs on its own slower timer so bots don't spam buttons.
	player.ability_think_timer -= Balance.TICK_DELTA
	if player.ability_think_timer <= 0.0:
		player.ability_think_timer = state.rng.randf_range(1.0, 2.0)
		if player.difficulty >= Balance.BOT_DIFFICULTY_NORMAL:
			BotAbilities.think(sim, player)
	# Easy bots won't attack a human's Crown before 4:00 (checked every tick so
	# a fast push can't slip into the Crown zone between thinks).
	# (In the tutorial it never does.)
	if player.difficulty == Balance.BOT_DIFFICULTY_EASY and (state.match_time < Balance.BOT_EASY_NO_CROWN_ATTACK_BEFORE_SEC or state.tutorial_rules):
		_easy_spare_human_crowns(sim, player)
	player.think_timer -= Balance.TICK_DELTA
	if player.think_timer > 0.0:
		return
	if state.bot_thinks_left <= 0:
		return   # enough bots thought this tick; this one goes next tick
	state.bot_thinks_left -= 1
	player.think_timer = _think_interval(player.difficulty, state.rng)
	if player.ally_id > 0:
		_support_ally(sim, player)
	if player.border.is_empty():
		return
	var scan: BotScan = BotScan.scan(sim, player)
	player.bot_scan = scan
	_housekeeping(sim, player, scan)
	var moves: Array[Dictionary] = BotMoves.candidates(sim, player, scan)
	if moves.is_empty():
		return
	moves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	_reorder_by_difficulty(player, moves, state.rng)
	for i in range(mini(3, moves.size())):
		if _execute(sim, player, moves[i]):
			var kind: String = str(moves[i].type)
			player.bot_actions[kind] = int(player.bot_actions.get(kind, 0)) + 1
			return


# Teams: send 20% to the ally when it's in trouble (Crown under attack or
# low on troops) and this bot has plenty to spare.
static func _support_ally(sim: Simulation, p: Player) -> void:
	var ally: Player = sim.ally_of(p)
	if ally == null or sim.send_to_ally_block_reason(p) != "":
		return
	if p.troops < p.troop_cap() * Balance.BOT_ALLY_HELP_MIN_RATIO:
		return
	var now: float = sim.state.match_time
	if ally.crown_alert_until > now or ally.troops < ally.troop_cap() * Balance.BOT_ALLY_HELP_BELOW_RATIO:
		sim.player_send_to_ally(p.id)


# Difficulty controls how often a bot picks a worse move: Easy makes a random
# move 20% of the time, Normal sometimes takes its second-best idea.
static func _reorder_by_difficulty(player: Player, moves: Array[Dictionary], rng: RandomNumberGenerator) -> void:
	if moves.size() < 2:
		return
	match player.difficulty:
		Balance.BOT_DIFFICULTY_EASY:
			if rng.randf() < Balance.BOT_EASY_RANDOM_MOVE_CHANCE:
				var pick: int = rng.randi_range(0, moves.size() - 1)
				var m: Dictionary = moves[pick]
				moves.remove_at(pick)
				moves.push_front(m)
		Balance.BOT_DIFFICULTY_NORMAL:
			if rng.randf() < Balance.BOT_NORMAL_WORSE_MOVE_CHANCE:
				var first: Dictionary = moves[0]
				moves[0] = moves[1]
				moves[1] = first
		_:
			if rng.randf() < Balance.BOT_HARD_WORSE_MOVE_CHANCE:
				var first2: Dictionary = moves[0]
				moves[0] = moves[1]
				moves[1] = first2


# Before choosing a move, Hard bots retreat from attacks that stopped making
# progress (75% of what's left comes back).
static func _housekeeping(sim: Simulation, player: Player, scan: BotScan) -> void:
	if player.difficulty != Balance.BOT_DIFFICULTY_HARD:
		return
	var index: int = 0
	for a: Attack in scan.my_attacks:
		if a.stalled_rings >= Balance.BOT_HARD_RETREAT_STALLED_RINGS and sim.player_retreat(player.id, index):
			return   # indices shift; one retreat per think is plenty
		index += 1


static func _easy_spare_human_crowns(sim: Simulation, player: Player) -> void:
	var state: GameState = sim.state
	var index: int = 0
	for a: Attack in state.attacks:
		if a.attacker_id != player.id:
			continue
		var target: Player = state.get_player(a.defender_id)
		if target != null and not target.is_bot and _front_near_crown(state, a, target):
			sim.player_retreat(player.id, index)
			return
		index += 1


static func _front_near_crown(state: GameState, a: Attack, target: Player) -> bool:
	if target.crown_x < 0:
		return false
	var r: int = target.crown_zone_radius() + 1
	for ti: int in a.front.keys():
		var t: Vector2i = state.idx_to_xy(ti)
		if (t.x - target.crown_x) * (t.x - target.crown_x) + (t.y - target.crown_y) * (t.y - target.crown_y) <= r * r:
			return true
	return false


static func _execute(sim: Simulation, p: Player, m: Dictionary) -> bool:
	var state: GameState = sim.state
	var tile: int = int(m.get("tile", -1))
	var t: Vector2i = state.idx_to_xy(tile) if tile >= 0 else Vector2i(-1, -1)
	match str(m.type):
		"expand":
			return sim.player_expand(p.id, t.x, t.y, send_fraction(p, state.rng))
		"attack":
			return sim.player_attack(p.id, t.x, t.y, float(m.frac))
		"fort":
			return sim.player_build_fort(p.id, t.x, t.y)
		"fort2":
			return sim.player_upgrade_fort(p.id, t.x, t.y)
		"barracks":
			return sim.player_build_barracks(p.id, t.x, t.y)
		"port":
			return sim.player_build_port(p.id, t.x, t.y)
		"keep":
			return sim.player_buy_keep(p.id, int(m.level))
		"wall":
			var built: bool = false
			for wt: int in m.tiles:
				var wp: Vector2i = state.idx_to_xy(wt)
				built = sim.player_build_wall(p.id, wp.x, wp.y) or built
			return built
		"boat":
			var port: Vector2i = state.idx_to_xy(int(m.port))
			return sim.player_launch_boat(p.id, port.x, port.y, t.x, t.y, send_fraction(p, state.rng))
		"crown_move":
			return sim.player_move_crown(p.id, t.x, t.y)
		"truce":
			p.truce_offer_cd_until = state.match_time + Balance.BOT_TRUCE_OFFER_COOLDOWN_SEC
			return sim.player_offer_truce(p.id, int(m.target))
	return false


# The share of its troop cap a bot waits for before it expands or attacks.
# Everyone rushes free land early, then rebuilds before the peace period ends.
static func act_threshold(p: Player, match_time: float, attacking: bool) -> float:
	if match_time < Balance.BOT_RUSH_END_SEC:
		return Balance.BOT_RUSH_ACT_THRESHOLD
	var base: float = Balance.BOT_ATTACK_THRESHOLD[p.difficulty] if attacking else Balance.BOT_EXPAND_THRESHOLD[p.difficulty]
	var t: float = clampf(base + Balance.BOT_ACT_THRESHOLD_PERSONALITY[p.personality], 0.0, 0.9)
	if attacking and match_time >= Balance.FINAL_SIEGE_START_SEC:
		t = maxf(t, Balance.BOT_SIEGE_ATTACK_THRESHOLD)   # save up for a decisive push
	return t


# How much of its troops a bot sends: the difficulty's range. Raiders always
# send the top of it (they overextend); Hard bots send enough to come back
# down to the middle of the sweet spot.
static func send_fraction(p: Player, rng: RandomNumberGenerator, attacking: bool = false) -> float:
	var r: Vector2 = send_range(p.difficulty)
	if attacking and p.personality == Balance.BOT_PERSONALITY_RAIDER:
		return r.y
	if p.difficulty == Balance.BOT_DIFFICULTY_HARD and p.troops > 0.0:
		var target: float = Balance.BOT_SWEET_SPOT_TARGET * p.troop_cap()
		return clampf((p.troops - target) / p.troops, r.x, r.y)
	return rng.randf_range(r.x, r.y)


static func random_send_fraction(p: Player, rng: RandomNumberGenerator) -> float:
	return send_fraction(p, rng, true)


static func send_range(difficulty: int) -> Vector2:
	match difficulty:
		Balance.BOT_DIFFICULTY_HARD:
			return Vector2(Balance.BOT_HARD_SEND_MIN, Balance.BOT_HARD_SEND_MAX)
		Balance.BOT_DIFFICULTY_NORMAL:
			return Vector2(Balance.BOT_NORMAL_SEND_MIN, Balance.BOT_NORMAL_SEND_MAX)
	return Vector2(Balance.BOT_EASY_SEND_MIN, Balance.BOT_EASY_SEND_MAX)


static func _think_interval(difficulty: int, rng: RandomNumberGenerator) -> float:
	var base: float
	match difficulty:
		Balance.BOT_DIFFICULTY_HARD:
			base = Balance.BOT_HARD_THINK_SEC
		Balance.BOT_DIFFICULTY_NORMAL:
			base = Balance.BOT_NORMAL_THINK_SEC
		_:
			base = Balance.BOT_EASY_THINK_SEC
	# A little jitter so bots don't all think on the same tick.
	return base * rng.randf_range(0.85, 1.15)
