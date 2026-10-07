class_name Bots
extends RefCounted

# Bot brain. Every think, a bot lists the moves it could make (expand, attack
# someone, build, spy, offer a truce, or wait), scores them by its personality
# and situation, and does the best one. Difficulty sets how often it thinks,
# how much it sends, what it may use, and how often it picks a worse move.
#
# Bots call the exact same Simulation commands as the local player and only
# see rivals through IntelOps, so they never know more than a player could.

const MOVE_WAIT: int = 0
const MOVE_EXPAND: int = 1
const MOVE_ATTACK: int = 2
const MOVE_BUILD: int = 3
const MOVE_SPY: int = 4
const MOVE_TRUCE: int = 5


static func tick(sim: Simulation, p: Player) -> void:
	# Ability thinking runs on its own slower timer so bots don't spam buttons.
	p.ability_think_timer -= Balance.TICK_DELTA
	if p.ability_think_timer <= 0.0:
		p.ability_think_timer = sim.state.rng.randf_range(1.0, 2.0)
		BotTactics.use_abilities(sim, p)
	p.think_timer -= Balance.TICK_DELTA
	if p.think_timer > 0.0:
		return
	p.think_timer = _think_interval(p.difficulty, sim.state.rng)
	BotTactics.manage_attacks(sim, p)
	_think(sim, p)


static func _think(sim: Simulation, p: Player) -> void:
	if p.border.is_empty() or p.troops < 1.0:
		return
	var ctx := _context(sim, p)
	var moves: Array[Dictionary] = []
	_add_expand(sim, p, ctx, moves)
	_add_attacks(sim, p, ctx, moves)
	if p.difficulty >= Balance.BOT_DIFFICULTY_NORMAL or p.personality == Balance.BOT_PERSONALITY_TURTLE:
		BotBuild.add_moves(sim, p, ctx, moves)
	BotTactics.add_moves(sim, p, ctx, moves)
	moves.append({"kind": MOVE_WAIT, "score": _wait_score(p, ctx)})
	var pick: Dictionary = _choose(sim, p, moves)
	_execute(sim, p, pick, ctx)


# What every scorer needs to know, computed once per think.
static func _context(sim: Simulation, p: Player) -> Dictionary:
	var state: GameState = sim.state
	var cap: float = p.troop_cap()
	var attacked_by: Dictionary = {}              # attacker_id -> true
	var busy: Dictionary = {}                     # player_id -> true when in any fight
	for a: Attack in state.attacks:
		busy[a.attacker_id] = true
		busy[a.defender_id] = true
		if a.defender_id == p.id:
			attacked_by[a.attacker_id] = true
	return {
		"now": state.match_time,
		"cap": cap,
		"ratio": p.troops / maxf(cap, 1.0),
		"neighbours": TerritoryOps.neighbour_ids(state, p),
		"frontier": TerritoryOps.collect_frontier(state, p),
		"attacked_by": attacked_by,
		"busy": busy,
		"send": _send_fraction(sim, p, cap),
		"can_spend": _can_spend(p, cap),
	}


# --- Candidate moves ------------------------------------------------------------

static func _add_expand(sim: Simulation, p: Player, ctx: Dictionary, moves: Array[Dictionary]) -> void:
	var frontier: PackedInt32Array = ctx["frontier"]
	if frontier.is_empty() or p.expansion_troops > p.troops or not ctx["can_spend"]:
		return
	var weight: float = 1.0
	match p.personality:
		Balance.BOT_PERSONALITY_EXPANDER:
			weight = 1.4
		Balance.BOT_PERSONALITY_RAIDER:
			weight = 0.8
	# Free land is the best deal in the game while it lasts.
	var score: float = 1.0 * weight + 0.002 * float(frontier.size())
	var tile: int = frontier[sim.state.rng.randi_range(0, frontier.size() - 1)]
	moves.append({"kind": MOVE_EXPAND, "score": score, "tile": tile})


static func _add_attacks(sim: Simulation, p: Player, ctx: Dictionary, moves: Array[Dictionary]) -> void:
	var state: GameState = sim.state
	var now: float = ctx["now"]
	if state.is_peace() or sim.active_attack_count(p.id) >= Balance.MAX_SIMULTANEOUS_ATTACKS or not ctx["can_spend"]:
		return
	var neighbours: Dictionary = ctx["neighbours"]
	var already: Dictionary = {}
	for a: Attack in sim.attacks_by(p.id):
		already[a.defender_id] = true
	var send: float = floorf(p.troops * float(ctx["send"]))
	var free_left: bool = not (ctx["frontier"] as PackedInt32Array).is_empty()
	for def_id: int in neighbours.keys():
		var def: Player = state.get_player(def_id)
		if def == null or not def.is_alive or def.land <= 0 or already.has(def_id):
			continue
		if TrucesOps.has_truce(p, def_id, now):
			continue
		if _easy_spares_crown(p, def, now) and _near_crown(state, def, neighbours[def_id], 4):
			continue
		var est: float = IntelOps.estimate_troops(p, def, now)
		var d_est: float = est / float(def.land)
		var tile_cost: float = Balance.ATTACK_TILE_COST_BASE + Balance.ATTACK_TILE_COST_SCALE * d_est * 1.3
		var tiles: float = send / tile_cost
		# Value: tiles we'd take, compared with what a ring of free land gives.
		var score: float = clampf(tiles / 60.0, 0.0, 2.0)
		score *= _attack_personality(p, def, ctx, d_est)
		if sim.rising_empire_id() == def_id:
			score *= 1.4
		if float(p.grudges.get(def_id, 0.0)) > now:
			score *= 1.3
		if ctx["attacked_by"].has(def_id):
			score *= 1.25                        # hit back
		for s: Shrine in state.shrines:
			if s.holder_id == def_id:
				score *= 1.15
		# Picking a fight with someone much stronger is a bad idea.
		if est > p.troops * 1.3:
			score *= 0.5
		if free_left:
			score *= 0.5
		moves.append({"kind": MOVE_ATTACK, "score": score, "target": def_id, "tile": neighbours[def_id]})


static func _attack_personality(p: Player, def: Player, ctx: Dictionary, d_est: float) -> float:
	match p.personality:
		Balance.BOT_PERSONALITY_RAIDER:
			# Loves weak borders.
			return 1.3 + clampf(1.5 - d_est, 0.0, 1.0) * 0.5
		Balance.BOT_PERSONALITY_TURTLE:
			# Counterattacks; otherwise rarely starts fights.
			return 1.4 if ctx["attacked_by"].has(def.id) else 0.8
		Balance.BOT_PERSONALITY_OPPORTUNIST:
			return 1.9 if ctx["busy"].has(def.id) else 1.0
		_:
			return 0.9


# Easy bots won't push into a human's Crown before 4:00.
static func _easy_spares_crown(p: Player, def: Player, now: float) -> bool:
	return p.difficulty == Balance.BOT_DIFFICULTY_EASY and not def.is_bot \
			and now < Balance.BOT_EASY_NO_CROWN_ATTACK_BEFORE_SEC


static func _near_crown(state: GameState, def: Player, tile_idx: int, extra: int) -> bool:
	if def.crown_x < 0:
		return false
	var pos: Vector2i = state.idx_to_xy(tile_idx)
	var r: int = def.crown_zone_radius() + extra
	return (pos.x - def.crown_x) * (pos.x - def.crown_x) + (pos.y - def.crown_y) * (pos.y - def.crown_y) <= r * r


static func _wait_score(_p: Player, ctx: Dictionary) -> float:
	return 0.15 if ctx["can_spend"] else 2.0


# Troops a bot keeps home as defense (and for growth interest). Easy bots
# don't plan for this; smarter bots sit near the growth sweet spot.
static func _reserve(p: Player, cap: float) -> float:
	match p.difficulty:
		Balance.BOT_DIFFICULTY_HARD:
			return Balance.BOT_HARD_RESERVE_OF_CAP * cap
		Balance.BOT_DIFFICULTY_NORMAL:
			return Balance.BOT_NORMAL_RESERVE_OF_CAP * cap
		_:
			return 0.0


static func _can_spend(p: Player, cap: float) -> bool:
	return p.troops - _reserve(p, cap) >= maxf(10.0, 0.1 * p.troops)


# --- Choosing and doing -----------------------------------------------------

static func _choose(sim: Simulation, p: Player, moves: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = moves[0]
	for m in moves:
		if float(m["score"]) > float(best["score"]):
			best = m
	var mistake: float = Balance.BOT_HARD_MISTAKE_CHANCE
	match p.difficulty:
		Balance.BOT_DIFFICULTY_EASY:
			mistake = Balance.BOT_EASY_MISTAKE_CHANCE
		Balance.BOT_DIFFICULTY_NORMAL:
			mistake = Balance.BOT_NORMAL_MISTAKE_CHANCE
	if moves.size() > 1 and sim.state.rng.randf() < mistake:
		return moves[sim.state.rng.randi_range(0, moves.size() - 1)]
	return best


static func _execute(sim: Simulation, p: Player, m: Dictionary, ctx: Dictionary) -> void:
	var state: GameState = sim.state
	match int(m["kind"]):
		MOVE_EXPAND:
			var pos: Vector2i = state.idx_to_xy(int(m["tile"]))
			sim.player_expand(p.id, pos.x, pos.y, float(ctx["send"]))
		MOVE_ATTACK:
			var pos: Vector2i = state.idx_to_xy(int(m["tile"]))
			sim.player_attack(p.id, pos.x, pos.y, float(ctx["send"]))
		MOVE_BUILD:
			BotBuild.execute(sim, p, m)
		MOVE_SPY:
			sim.player_spy(p.id, int(m["target"]), int(m["action"]))
		MOVE_TRUCE:
			sim.player_offer_truce(p.id, int(m["target"]))


static func _think_interval(difficulty: int, rng: RandomNumberGenerator) -> float:
	var base: float = Balance.BOT_EASY_THINK_SEC
	match difficulty:
		Balance.BOT_DIFFICULTY_HARD:
			base = Balance.BOT_HARD_THINK_SEC
		Balance.BOT_DIFFICULTY_NORMAL:
			base = Balance.BOT_NORMAL_THINK_SEC
	# A little jitter so bots don't all think on the same tick.
	return base * rng.randf_range(0.85, 1.15)


static func _send_fraction(sim: Simulation, p: Player, cap: float) -> float:
	var lo: float = Balance.BOT_EASY_SEND_MIN
	var hi: float = Balance.BOT_EASY_SEND_MAX
	match p.difficulty:
		Balance.BOT_DIFFICULTY_HARD:
			lo = Balance.BOT_HARD_SEND_MIN
			hi = Balance.BOT_HARD_SEND_MAX
		Balance.BOT_DIFFICULTY_NORMAL:
			lo = Balance.BOT_NORMAL_SEND_MIN
			hi = Balance.BOT_NORMAL_SEND_MAX
	var frac: float = sim.state.rng.randf_range(lo, hi)
	if p.troops > 0.0:
		# Never send below the reserve (the slider minimum still applies).
		var spendable: float = maxf(0.0, p.troops - _reserve(p, cap))
		frac = clampf(minf(frac, spendable / p.troops), Balance.SEND_MIN_FRACTION, hi)
	return frac
