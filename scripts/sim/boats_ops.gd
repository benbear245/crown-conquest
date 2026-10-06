class_name BoatsOps
extends RefCounted

# Launching boats and advancing them. BFS over water tiles from the Port to a
# water tile next to the target coast; capped by Balance.BOAT_RANGE_TILES.


# Why a boat can't go from this Port to (target_x, target_y), or "" if it can.
# On success `out_path` receives the water path.
static func launch_block_reason(sim: Simulation, player: Player, port_x: int, port_y: int,
		target_x: int, target_y: int, out_path: PackedInt32Array) -> String:
	var state: GameState = sim.state
	if not state.in_bounds(port_x, port_y) or not state.in_bounds(target_x, target_y):
		return "Off the map"
	var b: Building = state.building_at_tile.get(state.idx(port_x, port_y), null)
	if b == null or b.owner_id != player.id or b.type != Balance.BUILDING_PORT:
		return "Not your Port"
	var target_ti: int = state.idx(target_x, target_y)
	if state.is_blocked_terrain(state.terrain[target_ti]):
		return "Pick a land tile on a coast"
	var ow: int = state.owners[target_ti]
	if ow == player.id:
		return "That's your own land"
	var is_enemy: bool = ow > 0 and ow != GameState.RUINS_OWNER_ID
	if is_enemy and state.match_time < Balance.PEACE_PERIOD_SEC:
		return "No attacks during the peace period"
	var start_tiles: PackedInt32Array = PackedInt32Array()
	for off in TerritoryOps.NEIGHBOR_OFFSETS:
		var nx: int = port_x + off.x
		var ny: int = port_y + off.y
		if state.in_bounds(nx, ny) and state.terrain[state.idx(nx, ny)] == Balance.TERRAIN_WATER:
			start_tiles.append(state.idx(nx, ny))
	if start_tiles.is_empty():
		return "Port has no water"
	var path: PackedInt32Array = _bfs_water_path(state, start_tiles, target_x, target_y)
	if path.is_empty():
		return "No sea route within %d tiles" % Balance.BOAT_RANGE_TILES
	out_path.clear()
	out_path.append_array(path)
	return ""


static func try_launch(sim: Simulation, player: Player, port_x: int, port_y: int,
		target_x: int, target_y: int, fraction: float) -> bool:
	var path := PackedInt32Array()
	if launch_block_reason(sim, player, port_x, port_y, target_x, target_y, path) != "":
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
	sim.state.boats.append(boat)
	player.boats_launched += 1
	return true


# Returns water tile indices from one of start_tiles to a water tile next to
# (target_x, target_y), then the landing tile. Empty if no route in range.
static func _bfs_water_path(state: GameState, start_tiles: PackedInt32Array,
		target_x: int, target_y: int) -> PackedInt32Array:
	var came_from: Dictionary = {}
	var dist: Dictionary = {}
	var queue := PackedInt32Array()
	for s: int in start_tiles:
		queue.append(s)
		dist[s] = 0
		came_from[s] = -1
	var head: int = 0
	var end_ti: int = -1
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var cur_d: int = dist[cur]
		var pos: Vector2i = state.idx_to_xy(cur)
		if absi(pos.x - target_x) + absi(pos.y - target_y) == 1:
			end_ti = cur
			break
		if cur_d >= Balance.BOAT_RANGE_TILES:
			continue
		for off in TerritoryOps.NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var ni: int = state.idx(nx, ny)
			if state.terrain[ni] != Balance.TERRAIN_WATER or dist.has(ni):
				continue
			dist[ni] = cur_d + 1
			came_from[ni] = cur
			queue.append(ni)
	if end_ti < 0:
		return PackedInt32Array()
	var reversed := PackedInt32Array()
	var cur2: int = end_ti
	while cur2 >= 0:
		reversed.append(cur2)
		cur2 = came_from.get(cur2, -1)
	reversed.reverse()
	# Landing tile is the final step so the boat visually lands.
	reversed.append(state.idx(target_x, target_y))
	return reversed


# Advance all boats. When a boat reaches the end of its path it lands.
static func tick(sim: Simulation) -> void:
	var state: GameState = sim.state
	var step: float = Balance.BOAT_SPEED_TILES_PER_SEC * Balance.TICK_DELTA
	var i: int = 0
	while i < state.boats.size():
		var b: Boat = state.boats[i]
		b.progress += step
		if b.progress >= float(b.path.size() - 1):
			state.boats.remove_at(i)
			land(sim, b)
			continue
		i += 1


# Landing: free land is claimed and the rest continues as an expansion; enemy
# land opens an attack from the landing tile. Short of troops: the boat is lost.
static func land(sim: Simulation, b: Boat) -> void:
	var state: GameState = sim.state
	var p: Player = state.get_player(b.owner_id)
	if p == null or not p.is_alive or not state.in_bounds(b.landing_tile_x, b.landing_tile_y):
		return
	var ti: int = state.idx(b.landing_tile_x, b.landing_tile_y)
	var ow: int = state.owners[ti]
	if ow == p.id:
		# Already ours (we expanded there meanwhile): troops join the expansion.
		_add_to_expansion(p, b.troops)
		return
	if ow > 0 and ow != GameState.RUINS_OWNER_ID:
		_land_on_enemy(sim, p, b, ti, ow)
		return
	var cost: float = TerritoryOps.claim_cost_idx(state, ti, ow) * TerritoryOps.claim_discount(sim, p)
	if b.troops < cost:
		if p.id == sim.local_player_id:
			sim.announce("A boat was lost — not enough troops to land.", 3.0)
		return
	TerritoryOps.claim_tile(sim, p.id, b.landing_tile_x, b.landing_tile_y)
	_add_to_expansion(p, b.troops - cost)


static func _land_on_enemy(sim: Simulation, p: Player, b: Boat, ti: int, defender_id: int) -> void:
	var state: GameState = sim.state
	var defender: Player = state.get_player(defender_id)
	if defender == null or not defender.is_alive:
		return
	if TrucesOps.has_truce(p, defender_id, state.match_time):
		TrucesOps.break_truce(sim, p.id, defender_id)
	# Join an attack already running against this defender, if any.
	for a: Attack in state.attacks:
		if a.attacker_id == p.id and a.defender_id == defender_id:
			a.troops_remaining += b.troops
			a.troops_sent += b.troops
			a.front[ti] = true
			a.zone_cache_valid = false
			return
	if CombatOps.active_attack_count(state, p.id) >= Balance.MAX_SIMULTANEOUS_ATTACKS:
		return
	var atk := Attack.new()
	atk.attacker_id = p.id
	atk.defender_id = defender_id
	atk.troops_remaining = b.troops
	atk.troops_sent = b.troops
	atk.front = {ti: true}
	atk.advance_timer = Balance.ATTACK_RING_INTERVAL_SEC
	state.attacks.append(atk)


static func _add_to_expansion(p: Player, amount: float) -> void:
	if amount <= 0.0:
		return
	p.expansion_troops += amount
	if p.expansion_timer <= 0.0:
		p.expansion_timer = Balance.EXPANSION_RING_INTERVAL_SEC
