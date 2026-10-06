class_name TerritoryOps
extends RefCounted

# Tile ownership, borders and the free-land expansion engine. Pure sim code:
# every function takes the Simulation and mutates its GameState.

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


# --- Expansion ---------------------------------------------------------------

static func player_expand(sim: Simulation, player_id: int, tx: int, ty: int, fraction: float) -> bool:
	var state: GameState = sim.state
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	if not state.in_bounds(tx, ty):
		return false
	var ti: int = state.idx(tx, ty)
	var target_owner: int = state.owners[ti]
	if target_owner != 0 and target_owner != GameState.RUINS_OWNER_ID:
		return false
	if state.is_blocked_terrain(state.terrain[ti]):
		return false
	if not tile_touches_player(state, tx, ty, player_id):
		return false
	var frac: float = clampf(fraction, Balance.SEND_MIN_FRACTION, Balance.SEND_MAX_FRACTION)
	var send_amount: float = floorf(p.troops * frac)
	if send_amount <= 0.0:
		return false
	p.troops -= send_amount
	p.expansion_troops += send_amount
	if p.expansion_timer <= 0.0:
		p.expansion_timer = Balance.EXPANSION_RING_INTERVAL_SEC
	return true


static func apply_expansions(sim: Simulation) -> void:
	var state: GameState = sim.state
	for p: Player in state.players:
		if p.expansion_troops <= 0.0 or not p.is_alive:
			continue
		p.expansion_timer -= Balance.TICK_DELTA
		if p.expansion_timer > 0.0:
			continue
		# Swift March doubles the ring speed (half the interval).
		var interval: float = Balance.EXPANSION_RING_INTERVAL_SEC
		if AbilitiesOps.is_swift_march_active(p, state.match_time):
			interval *= 1.0 / Balance.SWIFT_MARCH_SPEED_MULT
		p.expansion_timer += interval
		expand_one_ring(sim, p)


static func expand_one_ring(sim: Simulation, player: Player) -> void:
	var state: GameState = sim.state
	var frontier: PackedInt32Array = collect_frontier(state, player)
	if frontier.is_empty():
		refund_expansion(player)
		return
	var discount: float = claim_discount(sim, player)
	var min_cost: float = INF
	for ni: int in frontier:
		var cost: float = claim_cost_idx(state, ni, state.owners[ni]) * discount
		if cost < min_cost:
			min_cost = cost
		if player.expansion_troops < cost:
			continue
		player.expansion_troops -= cost
		var pos: Vector2i = state.idx_to_xy(ni)
		claim_tile(sim, player.id, pos.x, pos.y)
	if player.expansion_troops < min_cost:
		refund_expansion(player)


# Multiplier on free-land and Ruins claim costs: Swift March and Underdog.
static func claim_discount(sim: Simulation, player: Player) -> float:
	var discount: float = 1.0
	if AbilitiesOps.is_swift_march_active(player, sim.state.match_time):
		discount *= 1.0 - Balance.SWIFT_MARCH_CLAIM_DISCOUNT
	if sim.is_underdog(player):
		discount *= 1.0 - Balance.UNDERDOG_CLAIM_DISCOUNT
	return discount


static func collect_frontier(state: GameState, player: Player) -> PackedInt32Array:
	var seen: Dictionary = {}
	var out := PackedInt32Array()
	for i: int in player.border.keys():
		var pos: Vector2i = state.idx_to_xy(i)
		for off in NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var ni: int = state.idx(nx, ny)
			if seen.has(ni):
				continue
			var ow: int = state.owners[ni]
			if ow != 0 and ow != GameState.RUINS_OWNER_ID:
				continue
			if state.is_blocked_terrain(state.terrain[ni]):
				continue
			seen[ni] = true
			out.append(ni)
	return out


static func claim_cost_idx(state: GameState, tile_idx: int, prev_owner: int) -> float:
	var t: int = state.terrain[tile_idx]
	if t < 0 or t >= Balance.TERRAIN_CLAIM_COST.size():
		return Balance.CLAIM_COST_BASE
	var cost: float = Balance.CLAIM_COST_BASE * Balance.TERRAIN_CLAIM_COST[t]
	if prev_owner == GameState.RUINS_OWNER_ID:
		cost *= Balance.RUINS_CLAIM_MULT
	return cost


static func refund_expansion(player: Player) -> void:
	player.troops += player.expansion_troops
	player.expansion_troops = 0.0
	player.expansion_timer = 0.0


# --- Claiming tiles ----------------------------------------------------------

static func claim_circle(sim: Simulation, player: Player, cx: int, cy: int, r: int) -> void:
	var state: GameState = sim.state
	var r2: int = r * r
	for y in range(maxi(0, cy - r), mini(state.height, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(state.width, cx + r + 1)):
			var dx: int = x - cx
			var dy: int = y - cy
			if dx * dx + dy * dy > r2:
				continue
			if state.is_blocked_terrain(state.terrain[state.idx(x, y)]):
				continue
			# Never steal another player's tiles when stamping a starting circle.
			var ow: int = state.owners[state.idx(x, y)]
			if ow != 0 and ow != GameState.RUINS_OWNER_ID and ow != player.id:
				continue
			claim_tile(sim, player.id, x, y)


static func claim_tile(sim: Simulation, player_id: int, x: int, y: int) -> void:
	var state: GameState = sim.state
	var i: int = state.idx(x, y)
	var prev: int = state.owners[i]
	if prev == player_id:
		return
	# Destroy any building/wall the previous owner had here; the capturer
	# gets 25% of its cost as loot.
	if prev > 0 and prev != GameState.RUINS_OWNER_ID:
		BuildingsOps.destroy_building_at(sim, i, prev, player_id)
		BuildingsOps.destroy_wall_at(sim, i, prev, player_id)
	state.set_owner_idx(i, player_id)
	update_borders_on_change(state, i, prev, player_id)


static func update_borders_on_change(state: GameState, i: int, from_owner: int, to_owner: int) -> void:
	var pos: Vector2i = state.idx_to_xy(i)
	var from_player: Player = state.get_player(from_owner)
	var to_player: Player = state.get_player(to_owner)
	var is_gem: bool = state.terrain[i] == Balance.TERRAIN_GEM
	if from_player != null:
		from_player.border.erase(i)
		from_player.land -= 1
		if is_gem:
			from_player.gem_tiles -= 1
	if to_player != null:
		to_player.land += 1
		if is_gem:
			to_player.gem_tiles += 1
		if to_player.land > to_player.peak_land:
			to_player.peak_land = to_player.land
		if tile_is_border(state, i, to_owner):
			to_player.border[i] = true
	# Any neighbour owned by either player may have become/stopped being border.
	for off in NEIGHBOR_OFFSETS:
		var nx: int = pos.x + off.x
		var ny: int = pos.y + off.y
		if not state.in_bounds(nx, ny):
			continue
		var ni: int = state.idx(nx, ny)
		var nowner: int = state.owners[ni]
		var np: Player = state.get_player(nowner)
		if np == null:
			continue
		if tile_is_border(state, ni, nowner):
			np.border[ni] = true
		else:
			np.border.erase(ni)


static func tile_is_border(state: GameState, i: int, owner_id: int) -> bool:
	var pos: Vector2i = state.idx_to_xy(i)
	for off in NEIGHBOR_OFFSETS:
		var nx: int = pos.x + off.x
		var ny: int = pos.y + off.y
		if not state.in_bounds(nx, ny):
			continue
		if state.owners[state.idx(nx, ny)] != owner_id:
			return true
	return false


static func tile_touches_player(state: GameState, x: int, y: int, player_id: int) -> bool:
	for off in NEIGHBOR_OFFSETS:
		var nx: int = x + off.x
		var ny: int = y + off.y
		if not state.in_bounds(nx, ny):
			continue
		if state.owners[state.idx(nx, ny)] == player_id:
			return true
	return false


static func rebuild_borders_for_all(state: GameState) -> void:
	for p: Player in state.players:
		p.border.clear()
	for i in range(state.owners.size()):
		var ow: int = state.owners[i]
		var p: Player = state.get_player(ow)
		if p == null:
			continue
		if tile_is_border(state, i, ow):
			p.border[i] = true
