class_name BotPlaces
extends RefCounted

# Where should a bot put things? Spatial helpers for BotMoves: Fort spots,
# safe interior tiles, wall lines, Ports, boat targets, Crown move spots.


# A Fort is most useful between the Crown and the nearest enemy border, so it
# covers both the Crown zone and the front. Walk from that border tile back
# toward the Crown and take the first tile we may build on, unless one of our
# Forts already covers that approach.
static func fort_tile(sim: Simulation, p: Player, scan: BotScan) -> int:
	var state: GameState = sim.state
	if p.crown_x < 0 or scan.threat_tile < 0:
		return -1
	var crown := Vector2(p.crown_x, p.crown_y)
	var front := Vector2(state.idx_to_xy(scan.threat_tile))
	var steps: int = maxi(1, int(front.distance_to(crown)))
	for s_i in range(Balance.BUILD_MIN_DIST_FROM_ENEMY + 1, steps + 1):
		var pt: Vector2 = front.lerp(crown, float(s_i) / float(steps))
		var x: int = int(round(pt.x))
		var y: int = int(round(pt.y))
		if not state.in_bounds(x, y):
			continue
		var ti: int = state.idx(x, y)
		if BuildingsOps.best_fort_defense_at(state, p, ti) > 1.0:
			return -1
		if BuildingsOps.tile_is_buildable(sim, p.id, ti):
			return ti
	return -1


# A random buildable tile near the Crown (usually the safest place we own).
static func safe_tile(sim: Simulation, p: Player) -> int:
	var state: GameState = sim.state
	if p.crown_x < 0:
		return -1
	for _attempt in range(12):
		var x: int = p.crown_x + state.rng.randi_range(-6, 6)
		var y: int = p.crown_y + state.rng.randi_range(-6, 6)
		if state.in_bounds(x, y) and BuildingsOps.tile_is_buildable(sim, p.id, state.idx(x, y)):
			return state.idx(x, y)
	return -1


static func fort_to_upgrade(sim: Simulation, p: Player) -> int:
	for ft: int in p.fort_tiles:
		if BuildingsOps.build_block_reason(sim, p, Balance.BUILDING_FORT2, ft) == "":
			return ft
	return -1


# A short wall across the approach from the nearest enemy to our Crown, a few
# tiles inside our border (walls can't go within 3 tiles of an enemy).
static func wall_line(sim: Simulation, p: Player, scan: BotScan) -> PackedInt32Array:
	var out := PackedInt32Array()
	var state: GameState = sim.state
	if p.crown_x < 0 or scan.threat_tile < 0:
		return out
	var crown := Vector2(p.crown_x, p.crown_y)
	var threat := Vector2(state.idx_to_xy(scan.threat_tile))
	var dist: float = threat.distance_to(crown)
	if dist < 3.0:
		return out
	var dir: Vector2 = (threat - crown) / dist
	var centre: Vector2 = crown + dir * maxf(2.5, dist - float(Balance.BUILD_MIN_DIST_FROM_ENEMY) - 1.5)
	var cx: int = int(round(centre.x))
	var cy: int = int(round(centre.y))
	# Already walled here? Don't stack lines.
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			if state.in_bounds(cx + dx, cy + dy) and state.wall_tiles.get(state.idx(cx + dx, cy + dy), -1) == p.id:
				return out
	var perp := Vector2(-dir.y, dir.x)
	@warning_ignore("integer_division")
	var half: int = Balance.BOT_WALL_LENGTH / 2
	for k in range(-half, half + 1):
		var pt: Vector2 = centre + perp * float(k)
		var x: int = int(round(pt.x))
		var y: int = int(round(pt.y))
		if not state.in_bounds(x, y):
			continue
		var ti: int = state.idx(x, y)
		if out.has(ti):
			continue
		if BuildingsOps.build_block_reason(sim, p, BuildingsOps.TYPE_WALL, ti) == "":
			out.append(ti)
	return out


# A coastal tile for a Port, but only if a boat from there could reach some
# free land or a weak enemy (otherwise the Port would be wasted troops).
static func port_tile(sim: Simulation, p: Player, scan: BotScan) -> int:
	var state: GameState = sim.state
	for ti: int in scan.coast_tiles:
		if BuildingsOps.build_block_reason(sim, p, Balance.BUILDING_PORT, ti) != "":
			continue
		var pos: Vector2i = state.idx_to_xy(ti)
		if _coast_target_from(sim, pos).x >= 0:
			return ti
	return -1


static func _coast_target_from(sim: Simulation, port: Vector2i) -> Vector2i:
	var state: GameState = sim.state
	var r: int = Balance.BOAT_RANGE_TILES - 10
	for _attempt in range(6):
		var x: int = clampi(port.x + state.rng.randi_range(-r, r), 0, state.width - 1)
		var y: int = clampi(port.y + state.rng.randi_range(-r, r), 0, state.height - 1)
		var ti: int = state.idx(x, y)
		var ow: int = state.owners[ti]
		if state.blocked[ti] == 0 and (ow == 0 or ow == GameState.RUINS_OWNER_ID) and BuildingsOps.tile_touches_water(state, ti):
			if absi(x - port.x) + absi(y - port.y) > 6:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# Pick a coast across the water from one of our Ports: free land first, else a
# weak enemy. A few random tries per think keep this cheap.
static func boat_plan(sim: Simulation, p: Player) -> Dictionary:
	var state: GameState = sim.state
	var port: Building = null
	for b: Building in state.buildings:
		if b.owner_id == p.id and b.type == Balance.BUILDING_PORT:
			port = b
			break
	if port == null:
		return {}
	var path := PackedInt32Array()
	var r: int = Balance.BOAT_RANGE_TILES - 10
	for _attempt in range(4):
		var x: int = clampi(port.x + state.rng.randi_range(-r, r), 0, state.width - 1)
		var y: int = clampi(port.y + state.rng.randi_range(-r, r), 0, state.height - 1)
		var ti: int = state.idx(x, y)
		if state.blocked[ti] == 1 or not BuildingsOps.tile_touches_water(state, ti):
			continue
		var ow: int = state.owners[ti]
		if ow == p.id:
			continue
		if ow > 0 and ow != GameState.RUINS_OWNER_ID:
			var e: Player = state.get_player(ow)
			if e == null or TrucesOps.has_truce(p, ow, state.match_time) or e.troops / float(maxi(e.land, 1)) > 2.0:
				continue
		if BoatsOps.launch_block_reason(sim, p, port.x, port.y, x, y, path) == "":
			var m: Dictionary = BotMoves.move("boat", 0.0, ti, ow)
			m["port"] = port.tile_idx
			return m
	return {}


# A tile deep inside our land where the Crown could move (10+ tiles from enemies).
static func crown_move_spot(sim: Simulation, p: Player) -> Vector2i:
	var state: GameState = sim.state
	for _attempt in range(16):
		var x: int = p.crown_x + state.rng.randi_range(-30, 30)
		var y: int = p.crown_y + state.rng.randi_range(-30, 30)
		if absi(x - p.crown_x) + absi(y - p.crown_y) < 8:
			continue
		if state.in_bounds(x, y) and state.owners[state.idx(x, y)] == p.id and CrownsOps.move_block_reason(sim, p, x, y) == "":
			return Vector2i(x, y)
	return Vector2i(-1, -1)
