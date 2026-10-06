class_name Simulation
extends RefCounted

# Drives the match. 10 ticks per second. Never touches nodes.
# Pure data in, pure data out.

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

var state: GameState = GameState.new()
var map_type: int = Balance.MAP_TYPE_CONTINENT
var size_preset: int = Balance.MAP_SIZE_MEDIUM


# --- Match setup -------------------------------------------------------------

func start_default_match(match_seed: int = 0) -> void:
	start_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, match_seed)


func start_match(size: int, mt: int, match_seed: int) -> void:
	size_preset = size
	map_type = mt
	var dims := MapGen.dims_for_size(size)
	state.configure(dims.x, dims.y, match_seed)
	MapGen.generate(state, mt)
	_add_local_player()


func _add_local_player() -> void:
	var p := Player.new()
	p.id = 1
	p.display_name = "You"
	p.color = Balance.color_for_player(1)
	p.troops = Balance.STARTING_TROOPS
	state.players.append(p)
	var start := _find_starting_tile(10)
	_claim_circle(p, start.x, start.y, Balance.STARTING_LAND_RADIUS)


# Spirals outward from (preferred_x, height/2) to find a non-blocked tile with
# a mostly non-blocked neighbourhood. Used to drop the local player's start.
func _find_starting_tile(preferred_x: int) -> Vector2i:
	@warning_ignore("integer_division")
	var cy: int = state.height / 2
	var fallback := Vector2i(clampi(preferred_x, 2, state.width - 3), cy)
	for radius in range(maxi(state.width, state.height)):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if radius > 0 and absi(dx) != radius and absi(dy) != radius:
					continue
				var x := preferred_x + dx
				var y := cy + dy
				if not state.in_bounds(x, y):
					continue
				if state.is_blocked_terrain(state.terrain[state.idx(x, y)]):
					continue
				if _non_blocked_neighbour_count(x, y, Balance.STARTING_LAND_RADIUS) >= 25:
					return Vector2i(x, y)
	return fallback


func _non_blocked_neighbour_count(cx: int, cy: int, r: int) -> int:
	var r2 := r * r
	var n := 0
	for y in range(maxi(0, cy - r), mini(state.height, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(state.width, cx + r + 1)):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy > r2:
				continue
			if not state.is_blocked_terrain(state.terrain[state.idx(x, y)]):
				n += 1
	return n


func _claim_circle(player: Player, cx: int, cy: int, r: int) -> void:
	var r2 := r * r
	for y in range(maxi(0, cy - r), mini(state.height, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(state.width, cx + r + 1)):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy > r2:
				continue
			if state.is_blocked_terrain(state.terrain[state.idx(x, y)]):
				continue
			_claim_tile(player.id, x, y)


# --- Tick loop ---------------------------------------------------------------

func advance_tick() -> void:
	_apply_growth()
	_apply_expansions()
	state.tick_count += 1


func _apply_growth() -> void:
	for p in state.players:
		if not p.is_alive:
			continue
		var cap := p.troop_cap()
		if p.troops > cap:
			var extra := p.troops - cap
			p.troops = cap + extra * (1.0 - Balance.OVER_CAP_SHRINK_PER_SEC * Balance.TICK_DELTA)
		else:
			var base_tps := p.troops_per_second_at(cap)
			var mult := _growth_multiplier(p)
			p.troops += base_tps * mult * Balance.TICK_DELTA
			if p.troops > cap:
				p.troops = cap


# Sum of additive growth modifiers. Gems live here; Underdog and Empire upkeep
# land in Prompt 10.
func _growth_multiplier(p: Player) -> float:
	var gem_bonus := minf(float(p.gem_tiles) * Balance.GEM_GROWTH_BONUS_PER_TILE, Balance.GEM_GROWTH_BONUS_MAX)
	return 1.0 + gem_bonus


func _apply_expansions() -> void:
	for p in state.players:
		if p.expansion_troops <= 0.0 or not p.is_alive:
			continue
		p.expansion_timer -= Balance.TICK_DELTA
		if p.expansion_timer > 0.0:
			continue
		p.expansion_timer += Balance.EXPANSION_RING_INTERVAL_SEC
		_expand_one_ring(p)


# --- Player commands ---------------------------------------------------------

# Returns true if the expansion was accepted. The tapped tile must be free
# (or Ruins) and touch the player's border.
func player_expand(player_id: int, tx: int, ty: int, fraction: float) -> bool:
	var p := state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	if not state.in_bounds(tx, ty):
		return false
	var target_owner: int = state.owners[state.idx(tx, ty)]
	if target_owner == player_id:
		return false
	# Prompt 2: expansion only. Attacks land in Prompt 5.
	if target_owner != 0 and target_owner != GameState.RUINS_OWNER_ID:
		return false
	if state.is_blocked_terrain(state.terrain[state.idx(tx, ty)]):
		return false
	if not _tile_touches_player(tx, ty, player_id):
		return false
	var frac := clampf(fraction, Balance.SEND_MIN_FRACTION, Balance.SEND_MAX_FRACTION)
	var send_amount := floorf(p.troops * frac)
	if send_amount <= 0.0:
		return false
	p.troops -= send_amount
	p.expansion_troops += send_amount
	# Start the first ring soon so the player sees instant feedback.
	if p.expansion_timer <= 0.0:
		p.expansion_timer = Balance.EXPANSION_RING_INTERVAL_SEC
	return true


# --- Expansion engine --------------------------------------------------------

func _expand_one_ring(player: Player) -> void:
	var frontier := _collect_frontier(player)
	if frontier.is_empty():
		_refund_expansion(player)
		return
	var min_cost := INF
	for ni: int in frontier:
		var ow: int = state.owners[ni]
		var cost := _claim_cost_idx(ni, ow)
		if cost < min_cost:
			min_cost = cost
		if player.expansion_troops < cost:
			continue
		player.expansion_troops -= cost
		var p := state.idx_to_xy(ni)
		_claim_tile(player.id, p.x, p.y)
	if player.expansion_troops < min_cost:
		_refund_expansion(player)


func _collect_frontier(player: Player) -> PackedInt32Array:
	# Free (unowned/ruins) non-blocked tiles 4-adjacent to this player's border.
	var seen := {}
	var out := PackedInt32Array()
	for i: int in player.border.keys():
		var pos := state.idx_to_xy(i)
		for off in NEIGHBOR_OFFSETS:
			var nx := pos.x + off.x
			var ny := pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var ni := state.idx(nx, ny)
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


func _claim_cost_idx(tile_idx: int, prev_owner: int) -> float:
	var t: int = state.terrain[tile_idx]
	if t < 0 or t >= Balance.TERRAIN_CLAIM_COST.size():
		return Balance.CLAIM_COST_BASE
	var cost := Balance.CLAIM_COST_BASE * Balance.TERRAIN_CLAIM_COST[t]
	if prev_owner == GameState.RUINS_OWNER_ID:
		cost *= Balance.RUINS_CLAIM_MULT
	return cost


func _refund_expansion(player: Player) -> void:
	player.troops += player.expansion_troops
	player.expansion_troops = 0.0
	player.expansion_timer = 0.0


# --- Tile claim + border bookkeeping -----------------------------------------

func _claim_tile(player_id: int, x: int, y: int) -> void:
	var i := state.idx(x, y)
	var prev: int = state.owners[i]
	if prev == player_id:
		return
	state.set_owner_idx(i, player_id)
	_update_borders_on_change(i, prev, player_id)


func _update_borders_on_change(i: int, from_owner: int, to_owner: int) -> void:
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
		if _tile_is_border(i, to_owner):
			to_player.border[i] = true
	# Any neighbour owned by either player may have become/stopped being border.
	for off in NEIGHBOR_OFFSETS:
		var nx := pos.x + off.x
		var ny := pos.y + off.y
		if not state.in_bounds(nx, ny):
			continue
		var ni := state.idx(nx, ny)
		var nowner: int = state.owners[ni]
		var np := state.get_player(nowner)
		if np == null:
			continue
		if _tile_is_border(ni, nowner):
			np.border[ni] = true
		else:
			np.border.erase(ni)


func _tile_is_border(i: int, owner_id: int) -> bool:
	var pos := state.idx_to_xy(i)
	for off in NEIGHBOR_OFFSETS:
		var nx := pos.x + off.x
		var ny := pos.y + off.y
		if not state.in_bounds(nx, ny):
			continue
		if state.owners[state.idx(nx, ny)] != owner_id:
			return true
	return false


func _tile_touches_player(x: int, y: int, player_id: int) -> bool:
	for off in NEIGHBOR_OFFSETS:
		var nx := x + off.x
		var ny := y + off.y
		if not state.in_bounds(nx, ny):
			continue
		if state.owners[state.idx(nx, ny)] == player_id:
			return true
	return false
