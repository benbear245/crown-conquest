class_name TerritoryOps
extends RefCounted

# Who owns which tile: claiming tiles, keeping each player's border set up to
# date, and the free-land expansion engine. Pure sim, called by Simulation.

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


# --- Claiming ----------------------------------------------------------------

static func claim_tile(sim: Simulation, player_id: int, x: int, y: int) -> void:
	var state: GameState = sim.state
	var i := state.idx(x, y)
	var prev: int = state.owners[i]
	if prev == player_id:
		return
	# Destroy any building/wall the previous owner had here; the capturer
	# gets 25% of its cost as loot.
	if state.is_player_owner(prev):
		BuildingsOps.destroy_at_capture(sim, i, prev, player_id)
	state.set_owner_idx(i, player_id)
	_update_borders_on_change(state, i, prev, player_id)
	if state.shrine_at_tile.has(i):
		ShrinesOps.on_tile_changed(sim, i)


static func claim_circle(sim: Simulation, player: Player, cx: int, cy: int, r: int) -> void:
	var state: GameState = sim.state
	var r2 := r * r
	for y in range(maxi(0, cy - r), mini(state.height, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(state.width, cx + r + 1)):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy > r2:
				continue
			if state.is_blocked_terrain(state.terrain[state.idx(x, y)]):
				continue
			claim_tile(sim, player.id, x, y)


static func _update_borders_on_change(state: GameState, i: int, from_owner: int, to_owner: int) -> void:
	var pos := state.idx_to_xy(i)
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
		var ni := state.idx(nx, ny)
		var nowner: int = state.owners[ni]
		var np := state.get_player(nowner)
		if np == null:
			continue
		if tile_is_border(state, ni, nowner):
			np.border[ni] = true
		else:
			np.border.erase(ni)


static func tile_is_border(state: GameState, i: int, owner_id: int) -> bool:
	var pos := state.idx_to_xy(i)
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


# Player ids whose land touches this player's border (excluding Ruins).
static func neighbour_ids(state: GameState, player: Player) -> Dictionary:
	var out: Dictionary = {}               # player_id -> one of their tiles next to us
	for i: int in player.border.keys():
		var pos := state.idx_to_xy(i)
		for off in NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var ni := state.idx(nx, ny)
			var ow: int = state.owners[ni]
			if ow == player.id or not state.is_player_owner(ow):
				continue
			out[ow] = ni
	return out


# --- Expansion engine --------------------------------------------------------

static func apply_expansions(sim: Simulation) -> void:
	var now: float = sim.state.match_time
	for p in sim.state.players:
		if p.expansion_troops <= 0.0 or not p.is_alive:
			continue
		p.expansion_timer -= Balance.TICK_DELTA
		if p.expansion_timer > 0.0:
			continue
		# Swift March doubles the ring speed (half the interval).
		var interval: float = Balance.EXPANSION_RING_INTERVAL_SEC
		if AbilitiesOps.is_swift_march_active(p, now):
			interval *= 1.0 / Balance.SWIFT_MARCH_SPEED_MULT
		p.expansion_timer += interval
		_expand_one_ring(sim, p)


static func claim_discount(sim: Simulation, player: Player) -> float:
	var discount: float = 1.0
	if AbilitiesOps.is_swift_march_active(player, sim.state.match_time):
		discount *= 1.0 - Balance.SWIFT_MARCH_CLAIM_DISCOUNT
	if sim.is_underdog(player):
		discount *= 1.0 - Balance.UNDERDOG_CLAIM_DISCOUNT
	return discount


static func _expand_one_ring(sim: Simulation, player: Player) -> void:
	var state: GameState = sim.state
	var frontier := collect_frontier(state, player)
	if frontier.is_empty():
		refund_expansion(player)
		return
	var discount: float = claim_discount(sim, player)
	var min_cost := INF
	for ni: int in frontier:
		var cost := claim_cost_idx(state, ni) * discount
		if cost < min_cost:
			min_cost = cost
		if player.expansion_troops < cost:
			continue
		player.expansion_troops -= cost
		var p := state.idx_to_xy(ni)
		claim_tile(sim, player.id, p.x, p.y)
	if player.expansion_troops < min_cost:
		refund_expansion(player)


# Free or Ruins tiles touching the player's border.
static func collect_frontier(state: GameState, player: Player) -> PackedInt32Array:
	var seen := {}
	var out := PackedInt32Array()
	for i: int in player.border.keys():
		var pos := state.idx_to_xy(i)
		for off in NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var ni := state.idx(nx, ny)
			if seen.has(ni):
				continue
			if state.is_player_owner(state.owners[ni]):
				continue
			if state.is_blocked_terrain(state.terrain[ni]):
				continue
			seen[ni] = true
			out.append(ni)
	return out


static func claim_cost_idx(state: GameState, tile_idx: int) -> float:
	var t: int = state.terrain[tile_idx]
	if t < 0 or t >= Balance.TERRAIN_CLAIM_COST.size():
		return Balance.CLAIM_COST_BASE
	var cost := Balance.CLAIM_COST_BASE * Balance.TERRAIN_CLAIM_COST[t]
	if state.owners[tile_idx] == GameState.RUINS_OWNER_ID:
		cost *= Balance.RUINS_CLAIM_MULT
	return cost


static func refund_expansion(player: Player) -> void:
	player.troops += player.expansion_troops
	player.expansion_troops = 0.0
	player.expansion_timer = 0.0
