class_name CrownsOps
extends RefCounted

# Crown placement (start of match) and the once-per-match Crown move.

const CROWN_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1,  0), Vector2i(0,  0), Vector2i(1,  0),
	Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1),
]


static func place_crown(sim: Simulation, player: Player, cx: int, cy: int) -> void:
	var state: GameState = sim.state
	player.crown_x = cx
	player.crown_y = cy
	player.troops = Balance.STARTING_TROOPS
	_stamp_crown_tiles(state, player, cx, cy)
	# Claim the starting radius-4 circle (which includes the 3x3).
	TerritoryOps.claim_circle(sim, player, cx, cy, Balance.STARTING_LAND_RADIUS)


static func _stamp_crown_tiles(state: GameState, player: Player, cx: int, cy: int) -> void:
	for off in CROWN_OFFSETS:
		var tx: int = cx + off.x
		var ty: int = cy + off.y
		if not state.in_bounds(tx, ty):
			continue
		var ti: int = state.idx(tx, ty)
		state.crown_tiles[ti] = player.id
		state.dirty_tiles[ti] = true
	state.crown_centres[player.id] = state.idx(cx, cy)


static func is_valid_crown_tile(state: GameState, x: int, y: int, min_dist_from_other: int) -> bool:
	if x < Balance.CROWN_MIN_DIST_FROM_EDGE or x >= state.width - Balance.CROWN_MIN_DIST_FROM_EDGE:
		return false
	if y < Balance.CROWN_MIN_DIST_FROM_EDGE or y >= state.height - Balance.CROWN_MIN_DIST_FROM_EDGE:
		return false
	var t: int = state.terrain[state.idx(x, y)]
	if t != Balance.TERRAIN_PLAINS and t != Balance.TERRAIN_FOREST and t != Balance.TERRAIN_HILLS:
		return false
	# Every tile of the 3x3 block must sit on buildable terrain.
	for off in CROWN_OFFSETS:
		var tx: int = x + off.x
		var ty: int = y + off.y
		if not state.in_bounds(tx, ty):
			return false
		if state.is_blocked_terrain(state.terrain[state.idx(tx, ty)]):
			return false
	# Keep Crowns apart.
	var md2: int = min_dist_from_other * min_dist_from_other
	for other: Player in state.players:
		if other.crown_x < 0:
			continue
		var dx: int = other.crown_x - x
		var dy: int = other.crown_y - y
		if dx * dx + dy * dy < md2:
			return false
	return true


static func find_valid_crown_position(state: GameState) -> Vector2i:
	var min_x: int = Balance.CROWN_MIN_DIST_FROM_EDGE
	var min_y: int = Balance.CROWN_MIN_DIST_FROM_EDGE
	var max_x: int = state.width - Balance.CROWN_MIN_DIST_FROM_EDGE
	var max_y: int = state.height - Balance.CROWN_MIN_DIST_FROM_EDGE
	# Try full spacing first.
	for _attempt in range(800):
		var x: int = state.rng.randi_range(min_x, max_x - 1)
		var y: int = state.rng.randi_range(min_y, max_y - 1)
		if is_valid_crown_tile(state, x, y, Balance.CROWN_MIN_DIST_FROM_OTHER):
			return Vector2i(x, y)
	# Fallback: relax the inter-Crown distance.
	@warning_ignore("integer_division")
	var relaxed: int = Balance.CROWN_MIN_DIST_FROM_OTHER / 2
	for _attempt in range(800):
		var x: int = state.rng.randi_range(min_x, max_x - 1)
		var y: int = state.rng.randi_range(min_y, max_y - 1)
		if is_valid_crown_tile(state, x, y, relaxed):
			return Vector2i(x, y)
	return Vector2i(-1, -1)


# --- Crown move --------------------------------------------------------------

static func move_cost(player: Player) -> float:
	return floorf(player.troops * Balance.CROWN_MOVE_COST_FRACTION)


# Why the Crown can't move to (x, y) right now, or "" if it can.
static func move_block_reason(sim: Simulation, player: Player, x: int, y: int) -> String:
	var state: GameState = sim.state
	if player.crown_moved:
		return "Already moved this match"
	if state.match_time < Balance.CROWN_MOVE_UNLOCK_SEC:
		return "Unlocks at %s" % GameState.format_time(Balance.CROWN_MOVE_UNLOCK_SEC)
	if not state.in_bounds(x, y):
		return "Off the map"
	for off in CROWN_OFFSETS:
		var tx: int = x + off.x
		var ty: int = y + off.y
		if not state.in_bounds(tx, ty):
			return "Too close to the edge"
		var ti: int = state.idx(tx, ty)
		if state.owners[ti] != player.id:
			return "Must be your own land"
		if state.is_blocked_terrain(state.terrain[ti]):
			return "Blocked terrain"
		if state.building_at_tile.has(ti) or state.wall_tiles.has(ti):
			return "A building is in the way"
	var r: int = Balance.CROWN_MOVE_MIN_DIST_FROM_ENEMY
	var r2: int = r * r
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r2:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			if not state.in_bounds(nx, ny):
				continue
			var ow: int = state.owners[state.idx(nx, ny)]
			if ow > 0 and ow != player.id and ow != GameState.RUINS_OWNER_ID:
				return "Too close to an enemy border"
	return ""


# Moves the Crown: costs 20% of troops, once per match from 3:00. The Crown
# relocates now but has no special defense for CROWN_MOVE_DURATION_SEC.
static func move_crown(sim: Simulation, player: Player, x: int, y: int) -> bool:
	var state: GameState = sim.state
	if player.crown_x < 0 or not player.is_alive:
		return false
	if move_block_reason(sim, player, x, y) != "":
		return false
	player.troops -= move_cost(player)
	for t_idx: int in state.crown_tiles.keys():
		if state.crown_tiles[t_idx] == player.id:
			state.crown_tiles.erase(t_idx)
			state.dirty_tiles[t_idx] = true
	player.crown_x = x
	player.crown_y = y
	player.crown_moved = true
	player.crown_move_until = state.match_time + Balance.CROWN_MOVE_DURATION_SEC
	_stamp_crown_tiles(state, player, x, y)
	return true
