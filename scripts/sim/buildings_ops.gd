class_name BuildingsOps
extends RefCounted

# Static helpers for buildings, walls and Keep upgrades. Called by Simulation
# (local-player taps and bot building).


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
	if state.building_at_tile.has(tile_idx) or state.wall_tiles.has(tile_idx):
		return false
	if state.crown_tiles.has(tile_idx) or state.shrine_at_tile.has(tile_idx):
		return false
	var pos: Vector2i = state.idx_to_xy(tile_idx)
	var r: int = Balance.BUILD_MIN_DIST_FROM_ENEMY
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var nx: int = pos.x + dx
			var ny: int = pos.y + dy
			if not state.in_bounds(nx, ny):
				continue
			var ow: int = state.owners[state.idx(nx, ny)]
			if state.is_player_owner(ow) and ow != player_id:
				return false
	return true


static func tile_touches_water(state: GameState, tile_idx: int) -> bool:
	var pos := state.idx_to_xy(tile_idx)
	for off in TerritoryOps.NEIGHBOR_OFFSETS:
		var nx: int = pos.x + off.x
		var ny: int = pos.y + off.y
		if state.in_bounds(nx, ny) and state.terrain[state.idx(nx, ny)] == Balance.TERRAIN_WATER:
			return true
	return false


# Cost of the next building of this type for this player, or -1 if the
# player is at the limit (or the type can't be built from scratch).
static func next_cost(player: Player, type: int) -> float:
	match type:
		Balance.BUILDING_FORT:
			return fort_cost_for(player) if player.fort_count < Balance.FORT_LIMIT else -1.0
		Balance.BUILDING_BARRACKS:
			return barracks_cost_for(player) if player.barracks_count < Balance.BARRACKS_LIMIT else -1.0
		Balance.BUILDING_PORT:
			return Balance.PORT_COST if player.port_count < Balance.PORT_LIMIT else -1.0
		Balance.BUILDING_WATCHTOWER:
			return Balance.WATCHTOWER_COST if player.watchtower_count < Balance.WATCHTOWER_LIMIT else -1.0
		_:
			return -1.0


static func unlock_sec(type: int) -> float:
	return Balance.BARRACKS_UNLOCK_SEC if type == Balance.BUILDING_BARRACKS else 0.0


static func can_build(sim: Simulation, player: Player, type: int, tile_idx: int) -> bool:
	var cost: float = next_cost(player, type)
	if cost < 0.0 or player.troops < cost:
		return false
	if sim.state.match_time < unlock_sec(type):
		return false
	if not tile_is_buildable(sim, player.id, tile_idx):
		return false
	if type == Balance.BUILDING_PORT and not tile_touches_water(sim.state, tile_idx):
		return false
	return true


static func build(sim: Simulation, player: Player, type: int, x: int, y: int) -> bool:
	var state: GameState = sim.state
	if not state.in_bounds(x, y):
		return false
	var ti: int = state.idx(x, y)
	if not can_build(sim, player, type, ti):
		return false
	player.troops -= next_cost(player, type)
	var b := Building.new()
	b.type = type
	b.owner_id = player.id
	b.x = x
	b.y = y
	b.tile_idx = ti
	state.buildings.append(b)
	state.building_at_tile[ti] = b
	_adjust_count(player, b, 1)
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
	state.dirty_tiles[ti] = true
	return true


# Place a wall tile on one of the player's own tiles. Cost: 4 troops/tile.
static func build_wall(sim: Simulation, player: Player, x: int, y: int) -> bool:
	var state: GameState = sim.state
	if not state.in_bounds(x, y):
		return false
	var ti: int = state.idx(x, y)
	if state.owners[ti] != player.id or state.is_blocked_terrain(state.terrain[ti]):
		return false
	if state.wall_tiles.has(ti) or state.building_at_tile.has(ti):
		return false
	if state.crown_tiles.has(ti) or state.shrine_at_tile.has(ti):
		return false
	if player.wall_count >= Balance.WALL_LIMIT or player.troops < Balance.WALL_COST_PER_TILE:
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
	if player.troops < c or player.crown_x < 0:
		return false
	player.troops -= c
	player.keep_level = target_level
	return true


# --- Losing buildings --------------------------------------------------------

# A captured tile loses its building or wall; the capturer gets 25% of its
# cost back as loot.
static func destroy_at_capture(sim: Simulation, tile_idx: int, old_owner: int, capturer_id: int) -> void:
	var state: GameState = sim.state
	var loot: float = 0.0
	var b: Building = state.building_at_tile.get(tile_idx, null)
	if b != null and b.owner_id == old_owner:
		_remove_building(state, b)
		loot += b.cost() * Balance.CAPTURED_BUILDING_LOOT_FRACTION
	if state.wall_tiles.get(tile_idx, -1) == old_owner:
		state.wall_tiles.erase(tile_idx)
		var old_p: Player = state.get_player(old_owner)
		if old_p != null:
			old_p.wall_count = maxi(0, old_p.wall_count - 1)
		loot += Balance.WALL_COST_PER_TILE * Balance.CAPTURED_BUILDING_LOOT_FRACTION
	var cap_p: Player = state.get_player(capturer_id)
	if cap_p == null or loot <= 0.0:
		return
	cap_p.troops += loot
	# Walls give tiny loot; only show numbers worth reading.
	if loot >= 1.0 and b != null:
		var pos: Vector2i = state.idx_to_xy(tile_idx)
		sim.emit({"type": "loot", "player_id": capturer_id, "amount": int(loot), "x": pos.x, "y": pos.y})


static func _remove_building(state: GameState, b: Building) -> void:
	state.building_at_tile.erase(b.tile_idx)
	state.buildings.erase(b)
	state.dirty_tiles[b.tile_idx] = true
	var old_p: Player = state.get_player(b.owner_id)
	if old_p != null:
		_adjust_count(old_p, b, -1)


static func _adjust_count(p: Player, b: Building, delta: int) -> void:
	match b.type:
		Balance.BUILDING_FORT, Balance.BUILDING_FORT2:
			p.fort_count = maxi(0, p.fort_count + delta)
			if delta > 0:
				p.fort_tiles.append(b.tile_idx)
			else:
				var at: int = p.fort_tiles.find(b.tile_idx)
				if at >= 0:
					p.fort_tiles.remove_at(at)
		Balance.BUILDING_BARRACKS:
			p.barracks_count = maxi(0, p.barracks_count + delta)
		Balance.BUILDING_PORT:
			p.port_count = maxi(0, p.port_count + delta)
		Balance.BUILDING_WATCHTOWER:
			p.watchtower_count = maxi(0, p.watchtower_count + delta)


# Eliminated players lose everything (their land is Ruins now; no loot).
static func remove_all_for(state: GameState, victim: Player) -> void:
	for b: Building in state.buildings.duplicate():
		if b.owner_id == victim.id:
			_remove_building(state, b)
	for wk: int in state.wall_tiles.keys():
		if state.wall_tiles[wk] == victim.id:
			state.wall_tiles.erase(wk)
	victim.wall_count = 0
	victim.fort_tiles = PackedInt32Array()


# --- Lookups for spying -------------------------------------------------------

# The target's building closest to any of the viewer's border tiles (what
# Sabotage hits). Ports are skipped: switching one off does nothing useful.
static func nearest_building_to(state: GameState, target_id: int, viewer: Player) -> Building:
	var best: Building = null
	var best_d2: int = 1 << 30
	var sample: Array = viewer.border.keys()
	@warning_ignore("integer_division")
	var step: int = maxi(1, sample.size() / 64)
	for b: Building in state.buildings:
		if b.owner_id != target_id or b.type == Balance.BUILDING_PORT:
			continue
		for k in range(0, sample.size(), step):
			var pos: Vector2i = state.idx_to_xy(sample[k])
			var d2: int = (pos.x - b.x) * (pos.x - b.x) + (pos.y - b.y) * (pos.y - b.y)
			if d2 < best_d2:
				best_d2 = d2
				best = b
	return best


static func count_type(state: GameState, owner_id: int, type: int) -> int:
	var n := 0
	for b: Building in state.buildings:
		if b.owner_id == owner_id and b.type == type:
			n += 1
	return n
