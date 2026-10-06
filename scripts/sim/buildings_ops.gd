class_name BuildingsOps
extends RefCounted

# Static helpers for building and Keep operations. Keeps simulation.gd lean.
# These are called by Simulation (local-player taps and bot building).


static func fort_cost_for(player: Player) -> float:
	return Balance.FORT_COST_BASE + Balance.FORT_COST_PER_EXTRA * float(player.fort_count)


static func barracks_cost_for(player: Player) -> float:
	return Balance.BARRACKS_COST_BASE + Balance.BARRACKS_COST_PER_EXTRA * float(player.barracks_count)


# Checks required for every building: owned-by-player, not too near enemy border.
static func tile_is_buildable(sim: Simulation, player_id: int, tile_idx: int) -> bool:
	var state: GameState = sim.state
	if state.owners[tile_idx] != player_id:
		return false
	if state.is_blocked_terrain(state.terrain[tile_idx]):
		return false
	if state.building_at_tile.has(tile_idx):
		return false
	if state.wall_tiles.has(tile_idx):
		return false
	if state.crown_tiles.has(tile_idx):
		return false
	var pos: Vector2i = state.idx_to_xy(tile_idx)
	var r: int = Balance.BUILD_MIN_DIST_FROM_ENEMY
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var nx: int = pos.x + dx
			var ny: int = pos.y + dy
			if not state.in_bounds(nx, ny):
				continue
			var ni: int = state.idx(nx, ny)
			var ow: int = state.owners[ni]
			if ow > 0 and ow != player_id and ow != GameState.RUINS_OWNER_ID:
				return false
	return true


static func can_build_fort(sim: Simulation, player: Player, tile_idx: int) -> bool:
	if player.fort_count >= Balance.FORT_LIMIT:
		return false
	if player.troops < fort_cost_for(player):
		return false
	return tile_is_buildable(sim, player.id, tile_idx)


static func build_fort(sim: Simulation, player: Player, x: int, y: int) -> bool:
	var state: GameState = sim.state
	if not state.in_bounds(x, y):
		return false
	var ti: int = state.idx(x, y)
	if not can_build_fort(sim, player, ti):
		return false
	var c: float = fort_cost_for(player)
	player.troops -= c
	var b := Building.new()
	b.type = Balance.BUILDING_FORT
	b.owner_id = player.id
	b.x = x
	b.y = y
	b.tile_idx = ti
	state.buildings.append(b)
	state.building_at_tile[ti] = b
	player.fort_count += 1
	player.fort_tiles.append(ti)
	state.dirty_tiles[ti] = true
	return true


# Upgrades an existing Fort I at (x, y) to Fort II. Costs FORT2_COST on top.
static func upgrade_fort(sim: Simulation, player: Player, x: int, y: int) -> bool:
	var state: GameState = sim.state
	if not state.in_bounds(x, y):
		return false
	var ti: int = state.idx(x, y)
	var b: Building = state.building_at_tile.get(ti, null)
	if b == null or b.owner_id != player.id or b.type != Balance.BUILDING_FORT:
		return false
	if player.troops < Balance.FORT2_COST:
		return false
	player.troops -= Balance.FORT2_COST
	b.type = Balance.BUILDING_FORT2
	return true


static func build_barracks(sim: Simulation, player: Player, x: int, y: int) -> bool:
	var state: GameState = sim.state
	if state.match_time < Balance.BARRACKS_UNLOCK_SEC:
		return false
	if player.barracks_count >= Balance.BARRACKS_LIMIT:
		return false
	if not state.in_bounds(x, y):
		return false
	var ti: int = state.idx(x, y)
	if not tile_is_buildable(sim, player.id, ti):
		return false
	var c: float = barracks_cost_for(player)
	if player.troops < c:
		return false
	player.troops -= c
	var b := Building.new()
	b.type = Balance.BUILDING_BARRACKS
	b.owner_id = player.id
	b.x = x
	b.y = y
	b.tile_idx = ti
	state.buildings.append(b)
	state.building_at_tile[ti] = b
	player.barracks_count += 1
	state.dirty_tiles[ti] = true
	return true


static func build_port(sim: Simulation, player: Player, x: int, y: int) -> bool:
	var state: GameState = sim.state
	if player.port_count >= Balance.PORT_LIMIT:
		return false
	if not state.in_bounds(x, y):
		return false
	var ti: int = state.idx(x, y)
	if not tile_is_buildable(sim, player.id, ti):
		return false
	# Must touch water.
	var touches: bool = false
	for off in Simulation.NEIGHBOR_OFFSETS:
		var nx: int = x + off.x
		var ny: int = y + off.y
		if not state.in_bounds(nx, ny):
			continue
		if state.terrain[state.idx(nx, ny)] == Balance.TERRAIN_WATER:
			touches = true
			break
	if not touches:
		return false
	if player.troops < Balance.PORT_COST:
		return false
	player.troops -= Balance.PORT_COST
	var b := Building.new()
	b.type = Balance.BUILDING_PORT
	b.owner_id = player.id
	b.x = x
	b.y = y
	b.tile_idx = ti
	state.buildings.append(b)
	state.building_at_tile[ti] = b
	player.port_count += 1
	state.dirty_tiles[ti] = true
	return true


# Place a wall tile on one of the player's own tiles. Cost: 4 troops/tile.
static func build_wall(sim: Simulation, player: Player, x: int, y: int) -> bool:
	var state: GameState = sim.state
	if not state.in_bounds(x, y):
		return false
	var ti: int = state.idx(x, y)
	if state.owners[ti] != player.id:
		return false
	if state.is_blocked_terrain(state.terrain[ti]):
		return false
	if state.wall_tiles.has(ti) or state.building_at_tile.has(ti):
		return false
	if state.crown_tiles.has(ti):
		return false
	if player.wall_count >= Balance.WALL_LIMIT:
		return false
	if player.troops < Balance.WALL_COST_PER_TILE:
		return false
	player.troops -= Balance.WALL_COST_PER_TILE
	state.wall_tiles[ti] = player.id
	player.wall_count += 1
	state.dirty_tiles[ti] = true
	return true


# Keep upgrades: buy level 1, 2, or 3. Must own a Crown (not eliminated).
static func buy_keep(sim: Simulation, player: Player, target_level: int) -> bool:
	if target_level < 1 or target_level >= Balance.KEEP_COST.size():
		return false
	if target_level != player.keep_level + 1:
		return false
	if sim.state.match_time < Balance.KEEP_UNLOCK_SEC[target_level]:
		return false
	var c: float = Balance.KEEP_COST[target_level]
	if player.troops < c:
		return false
	if player.crown_x < 0:
		return false
	player.troops -= c
	player.keep_level = target_level
	return true
