class_name Bots
extends RefCounted

# Basic bot brain. Prompt 4: expansion only. Smarter choices land in Prompt 11.
# Bots call the exact same Simulation commands as the local player.


static func tick(sim: Simulation, player: Player) -> void:
	# Ability thinking runs on its own slower timer so bots don't spam buttons.
	player.ability_think_timer -= Balance.TICK_DELTA
	if player.ability_think_timer <= 0.0:
		player.ability_think_timer = sim.state.rng.randf_range(1.0, 2.0)
		if player.difficulty >= Balance.BOT_DIFFICULTY_NORMAL:
			_try_abilities(sim, player)
	player.think_timer -= Balance.TICK_DELTA
	if player.think_timer > 0.0:
		return
	player.think_timer = _think_interval(player.difficulty, sim.state.rng)
	# Normal/Hard bots occasionally spend troops on buildings/Keep upgrades.
	if player.difficulty >= Balance.BOT_DIFFICULTY_NORMAL:
		if _try_buy_keep(sim, player):
			return
		if _try_build_barracks(sim, player):
			return
		if _try_build_fort(sim, player):
			return
	_basic_expand(sim, player)


static func _try_abilities(sim: Simulation, player: Player) -> void:
	var state: GameState = sim.state
	var now: float = state.match_time
	# Crown Shield: pop it if an enemy is pressing the Crown zone right now.
	if player.crown_alert_until > now and not AbilitiesOps.is_crown_shield_active(player, now):
		sim.player_activate_crown_shield(player.id)
	# Swift March: during the land rush, if there's free land near our border, cast it.
	if now < 180.0 and not AbilitiesOps.is_swift_march_active(player, now):
		if player.swift_march_cd_until <= now:
			sim.player_activate_swift_march(player.id)
	# Hard: Rally for ongoing attacks and Bombard on enemy Crown zones.
	if player.difficulty >= Balance.BOT_DIFFICULTY_HARD:
		if sim.active_attack_count(player.id) > 0 and not AbilitiesOps.is_rally_active(player, now):
			if player.rally_cd_until <= now and now >= Balance.RALLY_UNLOCK_SEC:
				sim.player_activate_rally(player.id)
		if now >= Balance.BOMBARD_UNLOCK_SEC and player.bombard_cd_until <= now:
			var tgt: Vector2i = _pick_bombard_target(sim, player)
			if tgt.x >= 0:
				sim.player_activate_bombard(player.id, tgt.x, tgt.y)


static func _pick_bombard_target(sim: Simulation, player: Player) -> Vector2i:
	var state: GameState = sim.state
	# Prefer the nearest enemy Crown within range.
	var r2: int = Balance.BOMBARD_RANGE_TILES * Balance.BOMBARD_RANGE_TILES
	for other in state.players:
		if other.id == player.id or not other.is_alive or other.crown_x < 0:
			continue
		for i_v in player.border.keys():
			var pos: Vector2i = state.idx_to_xy(i_v)
			var dx: int = pos.x - other.crown_x
			var dy: int = pos.y - other.crown_y
			if dx * dx + dy * dy <= r2:
				return Vector2i(other.crown_x, other.crown_y)
	return Vector2i(-1, -1)


static func _try_build_fort(sim: Simulation, player: Player) -> bool:
	if player.fort_count >= Balance.FORT_LIMIT:
		return false
	var cost: float = BuildingsOps.fort_cost_for(player)
	if player.troops < cost * 1.3:
		return false
	# Only Hard bots upgrade Forts aggressively.
	var tile: int = _pick_safe_build_tile(sim, player)
	if tile < 0:
		return false
	var pos := sim.state.idx_to_xy(tile)
	return sim.player_build_fort(player.id, pos.x, pos.y)


static func _try_build_barracks(sim: Simulation, player: Player) -> bool:
	if sim.state.match_time < Balance.BARRACKS_UNLOCK_SEC:
		return false
	if player.barracks_count >= Balance.BARRACKS_LIMIT:
		return false
	var cost: float = BuildingsOps.barracks_cost_for(player)
	if player.troops < cost * 1.3:
		return false
	var tile: int = _pick_safe_build_tile(sim, player)
	if tile < 0:
		return false
	var pos := sim.state.idx_to_xy(tile)
	return sim.player_build_barracks(player.id, pos.x, pos.y)


static func _try_buy_keep(sim: Simulation, player: Player) -> bool:
	var next: int = player.keep_level + 1
	if next >= Balance.KEEP_COST.size():
		return false
	if sim.state.match_time < Balance.KEEP_UNLOCK_SEC[next]:
		return false
	var c: float = Balance.KEEP_COST[next]
	if player.troops < c * 1.5:
		return false
	return sim.player_buy_keep(player.id, next)


# Picks a random interior tile of the player (not touching enemy border) that
# is far enough from the enemy for building. Returns -1 if nothing is safe.
static func _pick_safe_build_tile(sim: Simulation, player: Player) -> int:
	var state: GameState = sim.state
	if player.border.size() == 0:
		return -1
	var crown_i: int = state.crown_centres.get(player.id, -1)
	# Try tiles around the Crown, which are usually furthest from the enemy border.
	if crown_i < 0:
		return -1
	var cpos := state.idx_to_xy(crown_i)
	for _attempt in range(12):
		var dx: int = state.rng.randi_range(-6, 6)
		var dy: int = state.rng.randi_range(-6, 6)
		var x: int = cpos.x + dx
		var y: int = cpos.y + dy
		if not state.in_bounds(x, y):
			continue
		var ti: int = state.idx(x, y)
		if BuildingsOps.tile_is_buildable(sim, player.id, ti):
			return ti
	return -1


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


static func _send_range(difficulty: int) -> Vector2:
	match difficulty:
		Balance.BOT_DIFFICULTY_HARD:
			return Vector2(Balance.BOT_HARD_SEND_MIN, Balance.BOT_HARD_SEND_MAX)
		Balance.BOT_DIFFICULTY_NORMAL:
			return Vector2(Balance.BOT_NORMAL_SEND_MIN, Balance.BOT_NORMAL_SEND_MAX)
		_:
			return Vector2(Balance.BOT_EASY_SEND_MIN, Balance.BOT_EASY_SEND_MAX)


static func _basic_expand(sim: Simulation, player: Player) -> void:
	if player.border.is_empty() or player.troops < 1.0:
		return
	if _try_tap_free(sim, player):
		return
	# No free tiles touch the border; try attacking the weakest neighbour.
	if sim.state.match_time >= Balance.PEACE_PERIOD_SEC:
		_try_attack_weakest(sim, player)


static func _try_tap_free(sim: Simulation, player: Player) -> bool:
	var state: GameState = sim.state
	var border_keys: Array = player.border.keys()
	for _attempt in range(16):
		var i: int = border_keys[state.rng.randi_range(0, border_keys.size() - 1)]
		var pos := state.idx_to_xy(i)
		for off in Simulation.NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var ni := state.idx(nx, ny)
			var ow: int = state.owners[ni]
			if ow != 0 and ow != GameState.RUINS_OWNER_ID:
				continue
			if state.is_blocked_terrain(state.terrain[ni]):
				continue
			var range_v := _send_range(player.difficulty)
			var frac := state.rng.randf_range(range_v.x, range_v.y)
			if sim.player_expand(player.id, nx, ny, frac):
				return true
	return false


static func _try_attack_weakest(sim: Simulation, player: Player) -> void:
	if sim.active_attack_count(player.id) >= Balance.MAX_SIMULTANEOUS_ATTACKS:
		return
	var state: GameState = sim.state
	var neighbour_tile: Dictionary = {}       # defender_id -> example enemy tile idx
	for i: int in player.border.keys():
		var pos := state.idx_to_xy(i)
		for off in Simulation.NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var ni := state.idx(nx, ny)
			var ow: int = state.owners[ni]
			if ow == 0 or ow == GameState.RUINS_OWNER_ID or ow == player.id:
				continue
			neighbour_tile[ow] = ni
	if neighbour_tile.is_empty():
		return
	var best_id: int = -1
	var best_score: float = INF
	var best_tile: int = -1
	var rising_id: int = sim.rising_empire_id()
	for ow_v in neighbour_tile.keys():
		var ow: int = ow_v
		var def: Player = state.get_player(ow)
		if def == null or not def.is_alive or def.land <= 0:
			continue
		# Honour truces (Opportunists already have their own break logic).
		if TrucesOps.has_truce(player, ow, state.match_time):
			continue
		var d: float = def.troops / float(def.land)
		var score: float = d
		# Rising Empire: bots prioritise them (lower score = better target).
		if rising_id > 0 and ow == rising_id:
			score *= 0.6
		if score < best_score:
			best_score = score
			best_id = ow
			best_tile = neighbour_tile[ow_v]
	if best_id < 0:
		return
	var pos: Vector2i = state.idx_to_xy(best_tile)
	var range_v := _send_range(player.difficulty)
	var frac := state.rng.randf_range(range_v.x, range_v.y)
	sim.player_attack(player.id, pos.x, pos.y, frac)
