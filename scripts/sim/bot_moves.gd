class_name BotMoves
extends RefCounted

# Builds a bot's list of possible moves, each with a score. Difficulty decides
# which tools a bot may use (design "Bots" table); personality and the
# situation shape the scores. Bots.gd picks one and carries it out through the
# same Simulation commands the player uses.

const EASY: int = Balance.BOT_DIFFICULTY_EASY
const NORMAL: int = Balance.BOT_DIFFICULTY_NORMAL
const HARD: int = Balance.BOT_DIFFICULTY_HARD


static func w(key: String) -> float:
	return float(Balance.BOT_SCORES[key])


static func move(type: String, score: float, tile: int = -1, target: int = -1) -> Dictionary:
	return {"type": type, "score": score, "tile": tile, "target": target}


static func candidates(sim: Simulation, p: Player, scan: BotScan) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var state: GameState = sim.state
	# Keep a defense: only grab land or attack once troops reach the bar.
	var cap: float = p.troop_cap()
	# Hard bots hold their troops while their Crown is under attack, and when
	# they're the softest target around.
	var crown_hit: bool = p.crown_alert_until > state.match_time
	var hold: bool = p.difficulty == HARD and (crown_hit or _softest_target(state, p, scan))
	if p.troops >= Bots.act_threshold(p, state.match_time, false) * cap and not (hold and (crown_hit or not scan.attackers_on_me.is_empty())):
		_expand(state, p, scan, out)
	if p.troops >= Bots.act_threshold(p, state.match_time, true) * cap and not hold:
		_attacks(sim, p, scan, out)
	_buildings(sim, p, scan, out)
	_truce(sim, p, scan, out)
	if p.difficulty == HARD:
		_hard_extras(sim, p, scan, out)
	return out


# Hard bots notice when they have the fewest troops per tile of everyone
# around them (everyone attacks their weakest neighbour), and hold.
static func _softest_target(state: GameState, p: Player, scan: BotScan) -> bool:
	if state.match_time < Balance.PEACE_PERIOD_SEC or scan.enemy_tile.is_empty():
		return false
	var my_d: float = p.troops / float(maxi(p.land, 1))
	for id: int in scan.enemy_tile.keys():
		var e: Player = state.get_player(id)
		if e != null and e.is_alive and e.troops / float(maxi(e.land, 1)) < my_d:
			return false
	return true


# Hard bots don't send so much that they'd end up with fewer troops per tile
# than their strongest neighbour (the weakest neighbour gets attacked).
static func hard_safe_fraction(state: GameState, p: Player, scan: BotScan) -> float:
	if state.match_time < Balance.PEACE_PERIOD_SEC or scan.enemy_tile.is_empty() or p.troops <= 0.0:
		return 1.0
	var max_d: float = 0.0
	for id: int in scan.enemy_tile.keys():
		var e: Player = state.get_player(id)
		if e != null and e.is_alive:
			max_d = maxf(max_d, e.troops / float(maxi(e.land, 1)))
	var keep: float = max_d * float(p.land)
	return clampf((p.troops - keep) / p.troops, 0.0, 1.0)


# --- Expanding -----------------------------------------------------------------

static func _expand(state: GameState, p: Player, scan: BotScan, out: Array[Dictionary]) -> void:
	if not scan.has_free_land():
		return
	var score: float = w("expand")
	if state.match_time < Balance.PEACE_PERIOD_SEC:
		score += w("expand_rush")
	if p.personality == Balance.BOT_PERSONALITY_EXPANDER:
		score += w("expand_expander")
	elif p.personality == Balance.BOT_PERSONALITY_TURTLE:
		score += w("expand_turtle")
	var pool: PackedInt32Array = scan.free_tiles
	var prefer_ruins: bool = p.personality == Balance.BOT_PERSONALITY_RAIDER or p.difficulty == HARD
	if not scan.ruins_tiles.is_empty() and (scan.free_tiles.is_empty() or prefer_ruins):
		pool = scan.ruins_tiles
		if p.personality == Balance.BOT_PERSONALITY_RAIDER:
			score += w("ruins_raider")   # races for Ruins
		if p.difficulty == HARD:
			score += w("ruins_hard")     # Ruins are half price: Hard bots grab them
	out.append(move("expand", score, pool[state.rng.randi_range(0, pool.size() - 1)]))


# --- Attacking -----------------------------------------------------------------

static func _attacks(sim: Simulation, p: Player, scan: BotScan, out: Array[Dictionary]) -> void:
	var state: GameState = sim.state
	if state.match_time < Balance.PEACE_PERIOD_SEC or scan.enemy_tile.is_empty():
		return
	if scan.my_attacks.size() >= Balance.MAX_SIMULTANEOUS_ATTACKS:
		return
	var weakest_id: int = -1
	var weakest_d: float = INF
	for id: int in scan.enemy_tile.keys():
		var e: Player = state.get_player(id)
		if e != null and e.is_alive and e.land > 0 and not TrucesOps.has_truce(p, id, state.match_time):
			var d: float = e.troops / float(e.land)
			if d < weakest_d:
				weakest_d = d
				weakest_id = id
	var frac: float = Bots.send_fraction(p, state.rng, true)
	if p.difficulty == HARD:
		frac = minf(frac, hard_safe_fraction(state, p, scan))
		if frac < Balance.BOT_HARD_SEND_MIN:
			return   # can't send a real push and stay as tough as the neighbours
	var send: float = floorf(p.troops * frac)
	var rising: int = sim.rising_empire_id()
	for id: int in scan.enemy_tile.keys():
		var e: Player = state.get_player(id)
		if e == null or not e.is_alive or e.land <= 0:
			continue
		if TrucesOps.has_truce(p, id, state.match_time):
			continue
		var tile: int = scan.enemy_tile[id]
		if p.difficulty == EASY and _easy_spares_crown(state, e, tile):
			continue
		var d: float = e.troops / float(e.land)
		var est_cost: float = Balance.ATTACK_TILE_COST_BASE + Balance.ATTACK_TILE_COST_SCALE * d * 1.3
		var tiles: float = send / est_cost
		if tiles < Balance.BOT_MIN_ATTACK_TILES:
			continue
		var score: float = w("attack") + minf(w("attack_tile_cap"), tiles * w("attack_per_tile"))
		var is_weakest: bool = id == weakest_id
		if is_weakest and p.difficulty >= NORMAL:
			score += w("attack_weakest")   # looks for weak borders
		match p.personality:
			Balance.BOT_PERSONALITY_RAIDER:
				if is_weakest:
					score += w("attack_raider")
			Balance.BOT_PERSONALITY_OPPORTUNIST:
				if scan.busy.has(id) and not scan.attackers_on_me.has(id):
					score += w("attack_busy_opportunist")
			Balance.BOT_PERSONALITY_TURTLE:
				score += w("attack_counter_turtle") if scan.attackers_on_me.has(id) else w("attack_turtle_idle")
			Balance.BOT_PERSONALITY_EXPANDER:
				if scan.has_free_land():
					score += w("attack_expander_free_land")
		if id == rising:
			score += w("attack_rising")
		if p.difficulty == HARD and scan.busy.has(id) and not scan.attackers_on_me.has(id):
			score += w("attack_busy_hard")   # their troops are tied up elsewhere
		if p.difficulty >= NORMAL and e.crown_x >= 0:
			var tp: Vector2i = state.idx_to_xy(tile)
			var reach: int = e.crown_zone_radius() + 6
			if (tp.x - e.crown_x) * (tp.x - e.crown_x) + (tp.y - e.crown_y) * (tp.y - e.crown_y) <= reach * reach:
				score += w("attack_crown")
				# Hard: a much weaker neighbour's Crown is a kill worth chasing.
				if p.difficulty == HARD and d * 2.0 < p.troops / float(maxi(p.land, 1)):
					score += w("crown_kill_hard")
		for a: Attack in scan.my_attacks:
			if a.defender_id == id:
				score += w("attack_again")
				break
		var m: Dictionary = move("attack", score, tile, id)
		m["frac"] = frac
		out.append(m)


# Easy bots won't attack a human player's Crown before 4:00.
static func _easy_spares_crown(state: GameState, e: Player, tile: int) -> bool:
	if e.is_bot or e.crown_x < 0 or state.match_time >= Balance.BOT_EASY_NO_CROWN_ATTACK_BEFORE_SEC:
		return false
	var tp: Vector2i = state.idx_to_xy(tile)
	var r: int = e.crown_zone_radius() + 3
	return (tp.x - e.crown_x) * (tp.x - e.crown_x) + (tp.y - e.crown_y) * (tp.y - e.crown_y) <= r * r


# --- Building ------------------------------------------------------------------

static func _margin(p: Player) -> float:
	return Balance.BOT_TURTLE_BUILD_TROOP_MARGIN if p.personality == Balance.BOT_PERSONALITY_TURTLE else Balance.BOT_BUILD_TROOP_MARGIN


# A building may not take troops below the bot's defense bar. Defensive
# buildings bought under threat (Keep, Forts) only need the lower expand bar.
static func can_build(p: Player, cost: float, now: float, defensive: bool = false) -> bool:
	var floor_troops: float = Bots.act_threshold(p, now, not defensive) * p.troop_cap()
	return p.troops >= cost * _margin(p) and p.troops - cost >= floor_troops


static func _buildings(sim: Simulation, p: Player, scan: BotScan, out: Array[Dictionary]) -> void:
	var state: GameState = sim.state
	var now: float = state.match_time
	var threatened: bool = scan.threatened()
	var turtle: bool = p.personality == Balance.BOT_PERSONALITY_TURTLE
	# Forts: Easy rarely, Normal and Hard when threatened (Turtles any time there's a front).
	var easy_fort_ok: bool = p.difficulty != EASY or state.rng.randf() < Balance.BOT_EASY_FORT_CHANCE
	if easy_fort_ok and p.fort_count < Balance.FORT_LIMIT and can_build(p, BuildingsOps.fort_cost_for(p), now, threatened) \
			and (threatened or (turtle and scan.threat_tile >= 0)):
		var tile: int = BotPlaces.fort_tile(sim, p, scan)
		if tile >= 0:
			var score: float = w("fort") + (w("fort_threat") if threatened else 0.0)
			score += w("fort_turtle") if turtle else (w("fort_expander") if p.personality == Balance.BOT_PERSONALITY_EXPANDER else 0.0)
			out.append(move("fort", score, tile))
	if p.difficulty == EASY:
		return
	# Barracks (Normal, Hard): more cap once troops press against it.
	if now >= Balance.BARRACKS_UNLOCK_SEC and p.barracks_count < Balance.BARRACKS_LIMIT \
			and p.troops >= Balance.BOT_BARRACKS_AT_CAP * p.troop_cap() and can_build(p, BuildingsOps.barracks_cost_for(p), now):
		var bt: int = BotPlaces.safe_tile(sim, p)
		if bt >= 0:
			var full: bool = p.troops >= 0.9 * p.troop_cap()
			out.append(move("barracks", w("barracks") + (w("barracks_full") if full else 0.0), bt))
	# Keep: Normal buys Keep 1 only; Hard any level.
	var next_keep: int = p.keep_level + 1
	var keep_ok: bool = next_keep < Balance.KEEP_COST.size() and (p.difficulty == HARD or next_keep == 1)
	if keep_ok and BuildingsOps.keep_block_reason(sim, p, next_keep) == "" and can_build(p, Balance.KEEP_COST[next_keep], now, threatened) \
			and (threatened or turtle or now >= Balance.KEEP_UNLOCK_SEC[next_keep] + 60.0):
		var ks: float = w("keep") + (w("keep_threat") if threatened else 0.0) + (w("keep_turtle") if turtle else 0.0)
		if p.crown_alert_until > now:
			ks += w("keep_crown_hit")   # the Crown is being hit: shore it up first
		var km: Dictionary = move("keep", ks)
		km["level"] = next_keep
		out.append(km)


static func _truce(sim: Simulation, p: Player, scan: BotScan, out: Array[Dictionary]) -> void:
	var state: GameState = sim.state
	if state.match_time < p.truce_offer_cd_until:
		return
	# Pressed from two sides: offer peace to the one pushing hardest.
	if scan.attackers_on_me.size() >= 2:
		var best_id: int = -1
		var best_troops: float = -1.0
		for id: int in scan.attackers_on_me.keys():
			var other: Player = state.get_player(id)
			if other == null or other.oathbroken or TrucesOps.offer_block_reason(state, p, other) != "":
				continue
			if float(scan.attackers_on_me[id]) > best_troops:
				best_troops = scan.attackers_on_me[id]
				best_id = id
		if best_id > 0:
			out.append(move("truce", w("truce_pressed"), -1, best_id))
			return
	# Hard bots avoid two-front wars: offer peace to the strongest neighbour
	# they aren't fighting (from the end of the peace period, up to 2 truces).
	if p.difficulty == HARD and state.match_time >= Balance.PEACE_PERIOD_SEC - 5.0:
		var strongest_id: int = -1
		var strongest: float = -1.0
		for id: int in scan.enemy_tile.keys():
			var e: Player = state.get_player(id)
			var fighting_e: bool = false
			for a: Attack in scan.my_attacks:
				fighting_e = fighting_e or a.defender_id == id
			if e == null or e.oathbroken or fighting_e or TrucesOps.offer_block_reason(state, p, e) != "":
				continue
			if e.troops > strongest:
				strongest = e.troops
				strongest_id = id
		if strongest_id > 0:
			var score: float = w("truce_hard_flank") if not scan.my_attacks.is_empty() else w("truce_hard_peace")
			out.append(move("truce", score, -1, strongest_id))
			return
	# Opportunists secure a quiet flank while they fight elsewhere.
	if p.personality == Balance.BOT_PERSONALITY_OPPORTUNIST and not scan.my_attacks.is_empty():
		for id: int in scan.enemy_tile.keys():
			var other2: Player = state.get_player(id)
			if other2 == null or other2.oathbroken or scan.busy.has(id) == false:
				continue
			var fighting: bool = false
			for a: Attack in scan.my_attacks:
				fighting = fighting or a.defender_id == id
			if not fighting and TrucesOps.offer_block_reason(state, p, other2) == "":
				out.append(move("truce", w("truce_opportunist_setup"), -1, id))
				return


# --- Hard only: walls, Fort II, Ports and boats, Crown move --------------------

static func _hard_extras(sim: Simulation, p: Player, scan: BotScan, out: Array[Dictionary]) -> void:
	var state: GameState = sim.state
	var now: float = state.match_time
	var turtle: bool = p.personality == Balance.BOT_PERSONALITY_TURTLE
	# Fort II and walls only against a real threat: someone attacking us or
	# enemy land close to the Crown.
	if not scan.attackers_on_me.is_empty() or scan.threat_dist2 <= Balance.BOT_THREAT_RADIUS * Balance.BOT_THREAT_RADIUS:
		var fort2: int = BotPlaces.fort_to_upgrade(sim, p)
		if fort2 >= 0 and can_build(p, Balance.FORT2_COST, now):
			out.append(move("fort2", w("fort2"), fort2))
		var wall_cost: float = float(Balance.BOT_WALL_LENGTH) * Balance.WALL_COST_PER_TILE
		if p.wall_count + Balance.BOT_WALL_LENGTH <= Balance.WALL_LIMIT and can_build(p, wall_cost, now):
			var line: PackedInt32Array = BotPlaces.wall_line(sim, p, scan)
			if line.size() >= 3:
				var wm: Dictionary = move("wall", w("wall") + (w("wall_turtle") if turtle else 0.0))
				wm["tiles"] = line
				out.append(wm)
	# No land left to grab: Ports and boats.
	if not scan.has_free_land() and can_build(p, Balance.PORT_COST, now):
		if p.port_count == 0:
			var port: int = BotPlaces.port_tile(sim, p, scan)
			if port >= 0:
				out.append(move("port", w("port"), port))
	if p.port_count > 0 and p.troops >= 300.0:
		var bm: Dictionary = BotPlaces.boat_plan(sim, p)
		if not bm.is_empty():
			bm["score"] = w("boat") + (15.0 if not scan.has_free_land() and scan.enemy_tile.is_empty() else 0.0)
			out.append(bm)
	# Crown under real pressure: move it somewhere safe (once, from 3:00).
	if not p.crown_moved and state.match_time >= Balance.CROWN_MOVE_UNLOCK_SEC and p.crown_alert_until > state.match_time \
			and AbilitiesOps.cooldown_until(AbilitiesOps.ID_CROWN_SHIELD, p) > state.match_time:
		var spot: Vector2i = BotPlaces.crown_move_spot(sim, p)
		if spot.x >= 0:
			out.append(move("crown_move", w("crown_move"), state.idx(spot.x, spot.y)))
