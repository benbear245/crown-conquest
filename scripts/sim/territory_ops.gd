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
	var budget: int = Balance.EXPANSION_TILES_PER_TICK_BUDGET
	for p: Player in state.players:
		if p.expansion_troops <= 0.0 or not p.is_alive:
			continue
		p.expansion_timer -= Balance.TICK_DELTA
		if p.expansion_timer > 0.0:
			continue
		if budget <= 0:
			continue   # this tick's budget is used up: expand next tick
		# Swift March doubles the ring speed (half the interval).
		var interval: float = Balance.EXPANSION_RING_INTERVAL_SEC
		if AbilitiesOps.is_swift_march_active(p, state.match_time):
			interval *= 1.0 / Balance.SWIFT_MARCH_SPEED_MULT
		p.expansion_timer += interval
		budget -= expand_one_ring(sim, p, mini(budget, Balance.EXPANSION_MAX_TILES_PER_RING))


# Claims one ring of free land (at most max_tiles). Returns tiles claimed.
static func expand_one_ring(sim: Simulation, player: Player, max_tiles: int = Balance.EXPANSION_MAX_TILES_PER_RING) -> int:
	var state: GameState = sim.state
	var frontier: PackedInt32Array = collect_frontier(state, player)
	if frontier.is_empty():
		refund_expansion(player)
		return 0
	var discount: float = claim_discount(sim, player)
	var claim_costs: PackedFloat32Array = Balance.TERRAIN_CLAIM_COST
	var terrain: PackedByteArray = state.terrain
	var w: int = state.width
	var min_cost: float = INF
	var claimed: int = 0
	for ni: int in frontier:
		# Same maths as claim_cost_idx(): (base x terrain) [x ruins] x discount.
		var cost: float = Balance.CLAIM_COST_BASE * claim_costs[terrain[ni]]
		if state.owners[ni] == GameState.RUINS_OWNER_ID:
			cost *= Balance.RUINS_CLAIM_MULT
		cost *= discount
		if cost < min_cost:
			min_cost = cost
		if player.expansion_troops < cost:
			continue
		if claimed >= max_tiles:
			min_cost = 0.0   # stopped early, not out of troops: no refund
			break
		player.expansion_troops -= cost
		claimed += 1
		@warning_ignore("integer_division")
		claim_tile(sim, player.id, ni % w, ni / w)
	if claimed > 0:
		sim.emit_event({"type": "expand", "player_id": player.id, "tiles": claimed})
	if player.expansion_troops < min_cost:
		refund_expansion(player)
	return claimed


# Multiplier on free-land and Ruins claim costs: Swift March and Underdog.
static func claim_discount(sim: Simulation, player: Player) -> float:
	var discount: float = 1.0
	if AbilitiesOps.is_swift_march_active(player, sim.state.match_time):
		discount *= 1.0 - Balance.SWIFT_MARCH_CLAIM_DISCOUNT
	if sim.is_underdog(player):
		discount *= 1.0 - Balance.UNDERDOG_CLAIM_DISCOUNT
	return discount


# Free / Ruins tiles touching the player's border, in border order (the order
# matters: it decides which tiles a ring claims first).
static func collect_frontier(state: GameState, player: Player) -> PackedInt32Array:
	var seen: Dictionary = {}
	var out := PackedInt32Array()
	var owners: PackedByteArray = state.owners
	var blocked: PackedByteArray = state.blocked
	var w: int = state.width
	var h: int = state.height
	for i: int in player.border.keys():
		var x: int = i % w
		@warning_ignore("integer_division")
		var y: int = i / w
		# Neighbour order: right, left, down, up (same as NEIGHBOR_OFFSETS).
		for k in range(4):
			var ni: int
			if k == 0:
				if x + 1 >= w:
					continue
				ni = i + 1
			elif k == 1:
				if x <= 0:
					continue
				ni = i - 1
			elif k == 2:
				if y + 1 >= h:
					continue
				ni = i + w
			else:
				if y <= 0:
					continue
				ni = i - w
			if seen.has(ni):
				continue
			var ow: int = owners[ni]
			if ow != 0 and ow != GameState.RUINS_OWNER_ID:
				continue
			if blocked[ni] == 1:
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
	var i: int = y * state.width + x
	var prev: int = state.owners[i]
	if prev == player_id:
		return
	# Destroy any building/wall the previous owner had here; the capturer
	# gets 25% of its cost as loot.
	if prev > 0 and prev != GameState.RUINS_OWNER_ID:
		if state.building_at_tile.has(i):
			BuildingsOps.destroy_building_at(sim, i, prev, player_id)
		if state.wall_tiles.has(i):
			BuildingsOps.destroy_wall_at(sim, i, prev, player_id)
	state.set_owner_idx(i, player_id)
	update_borders_on_change(state, i, prev, player_id)


static func _player_or_null(players: Array[Player], id: int) -> Player:
	if id >= 1 and id <= players.size():
		return players[id - 1]
	return null


static func update_borders_on_change(state: GameState, i: int, from_owner: int, to_owner: int) -> void:
	var players: Array[Player] = state.players
	var owners: PackedByteArray = state.owners
	var w: int = state.width
	var h: int = state.height
	var x: int = i % w
	@warning_ignore("integer_division")
	var y: int = i / w
	var from_player: Player = _player_or_null(players, from_owner)
	var to_player: Player = _player_or_null(players, to_owner)
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
		if _is_border(owners, w, h, i, x, y, to_owner):
			to_player.border[i] = true
	# Any neighbour may have become / stopped being border. Order: right,
	# left, down, up (same as NEIGHBOR_OFFSETS; the border dict order matters).
	for k in range(4):
		var ni: int
		var nx: int = x
		var ny: int = y
		if k == 0:
			if x + 1 >= w:
				continue
			ni = i + 1
			nx = x + 1
		elif k == 1:
			if x <= 0:
				continue
			ni = i - 1
			nx = x - 1
		elif k == 2:
			if y + 1 >= h:
				continue
			ni = i + w
			ny = y + 1
		else:
			if y <= 0:
				continue
			ni = i - w
			ny = y - 1
		var nowner: int = owners[ni]
		var np: Player = _player_or_null(players, nowner)
		if np == null:
			continue
		if _is_border(owners, w, h, ni, nx, ny, nowner):
			np.border[ni] = true
		else:
			np.border.erase(ni)


static func _is_border(owners: PackedByteArray, w: int, h: int, i: int, x: int, y: int, owner_id: int) -> bool:
	if x + 1 < w and owners[i + 1] != owner_id:
		return true
	if x > 0 and owners[i - 1] != owner_id:
		return true
	if y + 1 < h and owners[i + w] != owner_id:
		return true
	if y > 0 and owners[i - w] != owner_id:
		return true
	return false


static func tile_is_border(state: GameState, i: int, owner_id: int) -> bool:
	var w: int = state.width
	@warning_ignore("integer_division")
	return _is_border(state.owners, w, state.height, i, i % w, i / w, owner_id)


static func tile_touches_player(state: GameState, x: int, y: int, player_id: int) -> bool:
	for off in NEIGHBOR_OFFSETS:
		var nx: int = x + off.x
		var ny: int = y + off.y
		if not state.in_bounds(nx, ny):
			continue
		if state.owners[state.idx(nx, ny)] == player_id:
			return true
	return false
