class_name BuildingsOps
extends RefCounted

# Building, Wall and Keep operations. Called by Simulation (local-player taps
# and bot building). Every check also produces a reason string so the build
# menu can explain why an option is greyed out.

# Pseudo-type for walls in build_block_reason (walls live in GameState.wall_tiles).
const TYPE_WALL: int = 100


static func fort_cost_for(player: Player) -> float:
	return Balance.FORT_COST_BASE + Balance.FORT_COST_PER_EXTRA * float(player.fort_count)


static func barracks_cost_for(player: Player) -> float:
	return Balance.BARRACKS_COST_BASE + Balance.BARRACKS_COST_PER_EXTRA * float(player.barracks_count)


static func cost_for(player: Player, type: int) -> float:
	match type:
		Balance.BUILDING_FORT:
			return fort_cost_for(player)
		Balance.BUILDING_FORT2:
			return Balance.FORT2_COST
		Balance.BUILDING_BARRACKS:
			return barracks_cost_for(player)
		Balance.BUILDING_PORT:
			return Balance.PORT_COST
		TYPE_WALL:
			return Balance.WALL_COST_PER_TILE
	return 0.0


static func count_and_limit(player: Player, type: int) -> Vector2i:
	match type:
		Balance.BUILDING_FORT, Balance.BUILDING_FORT2:
			return Vector2i(player.fort_count, Balance.FORT_LIMIT)
		Balance.BUILDING_BARRACKS:
			return Vector2i(player.barracks_count, Balance.BARRACKS_LIMIT)
		Balance.BUILDING_PORT:
			return Vector2i(player.port_count, Balance.PORT_LIMIT)
		TYPE_WALL:
			return Vector2i(player.wall_count, Balance.WALL_LIMIT)
	return Vector2i.ZERO


# True if an enemy (alive player, not Ruins) owns any tile within
# BUILD_MIN_DIST_FROM_ENEMY of tile_idx.
static func near_enemy_border(state: GameState, player_id: int, tile_idx: int) -> bool:
	var pos: Vector2i = state.idx_to_xy(tile_idx)
	var r: int = Balance.BUILD_MIN_DIST_FROM_ENEMY
	for dy in range(-r, r + 1):
		var ny: int = pos.y + dy
		if ny < 0 or ny >= state.height:
			continue
		for dx in range(-r, r + 1):
			var nx: int = pos.x + dx
			if nx < 0 or nx >= state.width:
				continue
			var ow: int = state.owners[ny * state.width + nx]
			if ow > 0 and ow != player_id and ow != GameState.RUINS_OWNER_ID:
				return true
	return false


static func tile_touches_water(state: GameState, tile_idx: int) -> bool:
	var pos: Vector2i = state.idx_to_xy(tile_idx)
	for off in TerritoryOps.NEIGHBOR_OFFSETS:
		var nx: int = pos.x + off.x
		var ny: int = pos.y + off.y
		if state.in_bounds(nx, ny) and state.terrain[state.idx(nx, ny)] == Balance.TERRAIN_WATER:
			return true
	return false


# Placement checks shared by every building (and walls).
static func tile_is_buildable(sim: Simulation, player_id: int, tile_idx: int) -> bool:
	return _tile_block_reason(sim.state, player_id, tile_idx) == ""


static func _tile_block_reason(state: GameState, player_id: int, tile_idx: int) -> String:
	if state.owners[tile_idx] != player_id:
		return "Not your land"
	if state.is_blocked_terrain(state.terrain[tile_idx]):
		return "Blocked terrain"
	if state.building_at_tile.has(tile_idx) or state.wall_tiles.has(tile_idx):
		return "Already built here"
	if state.crown_tiles.has(tile_idx):
		return "Crown tile"
	if near_enemy_border(state, player_id, tile_idx):
		return "Within %d tiles of an enemy" % Balance.BUILD_MIN_DIST_FROM_ENEMY
	return ""


# Why `player` can't build `type` on tile_idx right now, or "" if they can.
static func build_block_reason(sim: Simulation, player: Player, type: int, tile_idx: int) -> String:
	var state: GameState = sim.state
	if type == Balance.BUILDING_FORT2:
		var b: Building = state.building_at_tile.get(tile_idx, null)
		if b == null or b.owner_id != player.id or b.type != Balance.BUILDING_FORT:
			return "Needs a Fort here"
		if near_enemy_border(state, player.id, tile_idx):
			return "Within %d tiles of an enemy" % Balance.BUILD_MIN_DIST_FROM_ENEMY
		if player.troops < Balance.FORT2_COST:
			return "Need %d troops" % int(Balance.FORT2_COST)
		return ""
	if type == Balance.BUILDING_BARRACKS and state.match_time < Balance.BARRACKS_UNLOCK_SEC:
		return "Unlocks at %s" % GameState.format_time(Balance.BARRACKS_UNLOCK_SEC)
	var cl: Vector2i = count_and_limit(player, type)
	if cl.x >= cl.y:
		return "Limit reached (%d/%d)" % [cl.x, cl.y]
	var tile_reason: String = _tile_block_reason(state, player.id, tile_idx)
	if tile_reason != "":
		return tile_reason
	if type == Balance.BUILDING_PORT and not tile_touches_water(state, tile_idx):
		return "Must touch water"
	var c: float = cost_for(player, type)
	if player.troops < c:
		return "Need %d troops" % int(c)
	return ""


static func build_fort(sim: Simulation, player: Player, x: int, y: int) -> bool:
	return _build(sim, player, Balance.BUILDING_FORT, x, y)


static func build_barracks(sim: Simulation, player: Player, x: int, y: int) -> bool:
	return _build(sim, player, Balance.BUILDING_BARRACKS, x, y)


static func build_port(sim: Simulation, player: Player, x: int, y: int) -> bool:
	return _build(sim, player, Balance.BUILDING_PORT, x, y)


static func _build(sim: Simulation, player: Player, type: int, x: int, y: int) -> bool:
	var state: GameState = sim.state
	if not state.in_bounds(x, y):
		return false
	var ti: int = state.idx(x, y)
	if build_block_reason(sim, player, type, ti) != "":
		return false
	var c: float = cost_for(player, type)
	player.troops -= c
	var b := Building.new()
	b.type = type
	b.owner_id = player.id
	b.x = x
	b.y = y
	b.tile_idx = ti
	b.paid = c
	state.buildings.append(b)
	state.building_at_tile[ti] = b
	match type:
		Balance.BUILDING_FORT:
			player.fort_count += 1
			player.fort_tiles.append(ti)
		Balance.BUILDING_BARRACKS:
			player.barracks_count += 1
		Balance.BUILDING_PORT:
			player.port_count += 1
	player.buildings_built[type] = int(player.buildings_built.get(type, 0)) + 1
	state.dirty_tiles[ti] = true
	return true


# Upgrades an existing Fort I at (x, y) to Fort II. Costs FORT2_COST on top.
static func upgrade_fort(sim: Simulation, player: Player, x: int, y: int) -> bool:
	var state: GameState = sim.state
	if not state.in_bounds(x, y):
		return false
	var ti: int = state.idx(x, y)
	if build_block_reason(sim, player, Balance.BUILDING_FORT2, ti) != "":
		return false
	var b: Building = state.building_at_tile[ti]
	player.troops -= Balance.FORT2_COST
	b.type = Balance.BUILDING_FORT2
	b.paid += Balance.FORT2_COST
	player.buildings_built[Balance.BUILDING_FORT2] = int(player.buildings_built.get(Balance.BUILDING_FORT2, 0)) + 1
	state.dirty_tiles[ti] = true
	return true


# Place a wall tile on one of the player's own tiles. Cost: 4 troops/tile.
static func build_wall(sim: Simulation, player: Player, x: int, y: int) -> bool:
	var state: GameState = sim.state
	if not state.in_bounds(x, y):
		return false
	var ti: int = state.idx(x, y)
	if build_block_reason(sim, player, TYPE_WALL, ti) != "":
		return false
	player.troops -= Balance.WALL_COST_PER_TILE
	state.wall_tiles[ti] = player.id
	player.wall_count += 1
	player.buildings_built[TYPE_WALL] = int(player.buildings_built.get(TYPE_WALL, 0)) + 1
	state.dirty_tiles[ti] = true
	return true


# Keep upgrades: buy level 1, 2, or 3. Must own a Crown (not eliminated).
static func keep_block_reason(sim: Simulation, player: Player, target_level: int) -> String:
	if target_level < 1 or target_level >= Balance.KEEP_COST.size():
		return "No such level"
	if player.keep_level >= target_level:
		return "Owned"
	if sim.state.match_time < Balance.KEEP_UNLOCK_SEC[target_level]:
		return "Unlocks at %s" % GameState.format_time(Balance.KEEP_UNLOCK_SEC[target_level])
	if target_level != player.keep_level + 1:
		return "Buy Keep %d first" % (target_level - 1)
	if player.crown_x < 0:
		return "No Crown"
	if player.troops < Balance.KEEP_COST[target_level]:
		return "Need %d troops" % int(Balance.KEEP_COST[target_level])
	return ""


static func buy_keep(sim: Simulation, player: Player, target_level: int) -> bool:
	if keep_block_reason(sim, player, target_level) != "":
		return false
	player.troops -= Balance.KEEP_COST[target_level]
	player.keep_level = target_level
	return true


# --- Defense lookup ----------------------------------------------------------

# The best Fort multiplier covering tile_idx among `owner`'s Forts (1.0 if none).
static func best_fort_defense_at(state: GameState, owner: Player, tile_idx: int) -> float:
	var pos: Vector2i = state.idx_to_xy(tile_idx)
	var best: float = 1.0
	for ft_idx: int in owner.fort_tiles:
		var b: Building = state.building_at_tile.get(ft_idx, null)
		if b == null or b.owner_id != owner.id:
			continue
		var r: int = b.radius()
		var fdx: int = pos.x - b.x
		var fdy: int = pos.y - b.y
		if fdx * fdx + fdy * fdy <= r * r:
			var m: float = b.defense_mult()
			if m > best:
				best = m
	return best


# --- Destruction -------------------------------------------------------------

# Capturing a building's tile destroys it and pays the capturer 25% of its cost.
static func destroy_building_at(sim: Simulation, tile_idx: int, old_owner: int, capturer_id: int) -> void:
	var state: GameState = sim.state
	var b: Building = state.building_at_tile.get(tile_idx, null)
	if b == null or b.owner_id != old_owner:
		return
	state.building_at_tile.erase(tile_idx)
	state.buildings.erase(b)
	var old_p: Player = state.get_player(old_owner)
	if old_p != null:
		match b.type:
			Balance.BUILDING_FORT, Balance.BUILDING_FORT2:
				old_p.fort_count = maxi(0, old_p.fort_count - 1)
				var at: int = old_p.fort_tiles.find(tile_idx)
				if at >= 0:
					old_p.fort_tiles.remove_at(at)
			Balance.BUILDING_BARRACKS:
				old_p.barracks_count = maxi(0, old_p.barracks_count - 1)
			Balance.BUILDING_PORT:
				old_p.port_count = maxi(0, old_p.port_count - 1)
	_pay_loot(sim, capturer_id, b.paid * Balance.CAPTURED_BUILDING_LOOT_FRACTION, tile_idx)


static func destroy_wall_at(sim: Simulation, tile_idx: int, old_owner: int, capturer_id: int) -> void:
	var state: GameState = sim.state
	if not state.wall_tiles.has(tile_idx) or state.wall_tiles[tile_idx] != old_owner:
		return
	state.wall_tiles.erase(tile_idx)
	var old_p: Player = state.get_player(old_owner)
	if old_p != null:
		old_p.wall_count = maxi(0, old_p.wall_count - 1)
	_pay_loot(sim, capturer_id, Balance.WALL_COST_PER_TILE * Balance.CAPTURED_BUILDING_LOOT_FRACTION, tile_idx)


static func _pay_loot(sim: Simulation, capturer_id: int, loot: float, tile_idx: int) -> void:
	var cap_p: Player = sim.state.get_player(capturer_id)
	if cap_p == null:
		return
	cap_p.troops += loot
	if not sim.headless:
		sim.add_popup(tile_idx, "+%d loot" % int(round(loot)), capturer_id)


# Elimination wipes every building, wall and boat the victim had (no loot).
static func remove_all_for(state: GameState, victim: Player) -> void:
	var i: int = 0
	while i < state.buildings.size():
		var b: Building = state.buildings[i]
		if b.owner_id == victim.id:
			state.building_at_tile.erase(b.tile_idx)
			state.dirty_tiles[b.tile_idx] = true
			state.buildings.remove_at(i)
			continue
		i += 1
	for wk: int in state.wall_tiles.keys():
		if state.wall_tiles[wk] == victim.id:
			state.wall_tiles.erase(wk)
			state.dirty_tiles[wk] = true
	victim.fort_count = 0
	victim.barracks_count = 0
	victim.port_count = 0
	victim.wall_count = 0
	victim.fort_tiles = PackedInt32Array()
	var bo: int = 0
	while bo < state.boats.size():
		var boat: Boat = state.boats[bo]
		if boat.owner_id == victim.id:
			state.boats.remove_at(bo)
			continue
		bo += 1
