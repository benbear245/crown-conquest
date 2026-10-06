class_name BoatsOps
extends RefCounted

# Launching boats and advancing them. BFS over water tiles from the Port to a
# landing tile adjacent to the target coast; capped by Balance.BOAT_RANGE_TILES.


static func try_launch(sim: Simulation, player: Player, port_x: int, port_y: int,
		target_x: int, target_y: int, fraction: float) -> bool:
	var state: GameState = sim.state
	if not state.in_bounds(port_x, port_y) or not state.in_bounds(target_x, target_y):
		return false
	var port_ti: int = state.idx(port_x, port_y)
	var b: Building = state.building_at_tile.get(port_ti, null)
	if b == null or b.owner_id != player.id or b.type != Balance.BUILDING_PORT:
		return false
	# Target must be a non-water, non-mountain tile owned by nobody-or-enemy.
	var target_ti: int = state.idx(target_x, target_y)
	var tt: int = state.terrain[target_ti]
	if tt == Balance.TERRAIN_WATER or tt == Balance.TERRAIN_MOUNTAINS:
		return false
	var ow: int = state.owners[target_ti]
	if ow == player.id:
		return false
	# BFS from water tiles adjacent to the Port.
	var start_tiles: Array = []
	for off in Simulation.NEIGHBOR_OFFSETS:
		var nx: int = port_x + off.x
		var ny: int = port_y + off.y
		if not state.in_bounds(nx, ny):
			continue
		if state.terrain[state.idx(nx, ny)] == Balance.TERRAIN_WATER:
			start_tiles.append(state.idx(nx, ny))
	if start_tiles.is_empty():
		return false
	var path: PackedInt32Array = _bfs_water_path(state, start_tiles, target_x, target_y)
	if path.is_empty():
		return false
	var frac: float = clampf(fraction, Balance.SEND_MIN_FRACTION, Balance.SEND_MAX_FRACTION)
	var send: float = floorf(player.troops * frac)
	if send <= 0.0:
		return false
	player.troops -= send
	var boat := Boat.new()
	boat.owner_id = player.id
	boat.troops = send
	boat.path = path
	boat.landing_tile_x = target_x
	boat.landing_tile_y = target_y
	boat.send_fraction = frac
	state.boats.append(boat)
	return true


# Returns path of water tile indices from one of start_tiles to a water tile
# adjacent to (target_x, target_y). Empty if no path within BOAT_RANGE_TILES.
static func _bfs_water_path(state: GameState, start_tiles: Array,
		target_x: int, target_y: int) -> PackedInt32Array:
	var came_from: Dictionary = {}
	var dist: Dictionary = {}
	var frontier: Array = []
	for s in start_tiles:
		frontier.append(s)
		dist[s] = 0
		came_from[s] = -1
	var end_ti: int = -1
	while not frontier.is_empty():
		var cur: int = frontier.pop_front()
		var cur_d: int = dist[cur]
		if cur_d >= Balance.BOAT_RANGE_TILES:
			continue
		var pos: Vector2i = state.idx_to_xy(cur)
		# If any neighbour is the target tile, we're done.
		for off in Simulation.NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if nx == target_x and ny == target_y:
				end_ti = cur
				break
		if end_ti >= 0:
			break
		for off in Simulation.NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var ni: int = state.idx(nx, ny)
			if state.terrain[ni] != Balance.TERRAIN_WATER:
				continue
			if dist.has(ni):
				continue
			dist[ni] = cur_d + 1
			came_from[ni] = cur
			frontier.append(ni)
	if end_ti < 0:
		return PackedInt32Array()
	# Walk the path back and reverse.
	var reversed: Array = []
	var cur2: int = end_ti
	while cur2 >= 0:
		reversed.append(cur2)
		cur2 = came_from.get(cur2, -1)
	reversed.reverse()
	# Append landing tile as the final step so the boat visually lands.
	reversed.append(state.idx(target_x, target_y))
	var out := PackedInt32Array()
	for v in reversed:
		out.append(v)
	return out


# Advance all boats by TICK_DELTA. When a boat reaches the end of its path,
# convert into an expansion or attack on the landing tile.
static func tick(sim: Simulation) -> void:
	var state: GameState = sim.state
	var step: float = Balance.BOAT_SPEED_TILES_PER_SEC * Balance.TICK_DELTA
	var i := 0
	while i < state.boats.size():
		var b: Boat = state.boats[i]
		b.progress += step
		if b.progress >= float(b.path.size() - 1):
			sim.boat_land(b)
			state.boats.remove_at(i)
			continue
		i += 1
