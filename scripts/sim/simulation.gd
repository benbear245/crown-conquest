class_name Simulation
extends RefCounted

# Drives the match. 10 ticks per second. Never touches nodes.

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
const CROWN_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1,  0), Vector2i(0,  0), Vector2i(1,  0),
	Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1),
]

var state: GameState = GameState.new()
var map_type: int = Balance.MAP_TYPE_CONTINENT
var size_preset: int = Balance.MAP_SIZE_MEDIUM
var local_player_id: int = 1


# --- Match setup -------------------------------------------------------------

func start_default_match(match_seed: int = 0) -> void:
	start_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, match_seed, 7)


func start_match(size: int, mt: int, match_seed: int, num_bots: int = -1) -> void:
	size_preset = size
	map_type = mt
	var dims := MapGen.dims_for_size(size)
	state.configure(dims.x, dims.y, match_seed)
	MapGen.generate(state, mt)
	if num_bots < 0:
		num_bots = MapGen.players_for_size(size) - 1
	_setup_players(num_bots)


func _setup_players(num_bots: int) -> void:
	var total: int = clampi(num_bots + 1, 1, Balance.PLAYER_COLORS.size() - 1)
	for i in range(total):
		var p := Player.new()
		p.id = i + 1
		p.color = Balance.color_for_player(p.id)
		if i == 0:
			p.display_name = "You"
			p.is_bot = false
		else:
			p.display_name = Balance.generate_name(state.rng)
			p.is_bot = true
			p.difficulty = Balance.BOT_DIFFICULTY_EASY
			p.personality = state.rng.randi() % 4
			p.think_timer = state.rng.randf_range(0.5, 2.0)
		state.players.append(p)


# --- Tick loop ---------------------------------------------------------------

func advance_tick() -> void:
	match state.phase:
		Balance.PHASE_PLACEMENT:
			_tick_placement()
		Balance.PHASE_MATCH:
			state.match_time += Balance.TICK_DELTA
			_apply_growth()
			_apply_expansions()
			_tick_attacks()
			_tick_flashes()
			_tick_bots()
	state.tick_count += 1


func _tick_flashes() -> void:
	if state.flash_tiles.is_empty():
		return
	var expired: Array = []
	for i: int in state.flash_tiles.keys():
		if state.match_time >= state.flash_tiles[i]:
			expired.append(i)
	for i: int in expired:
		state.flash_tiles.erase(i)
		state.dirty_tiles[i] = true


func _tick_attacks() -> void:
	var i := 0
	while i < state.attacks.size():
		var a: Attack = state.attacks[i]
		if a.troops_remaining <= 0.0:
			state.attacks.remove_at(i)
			continue
		a.advance_timer -= Balance.TICK_DELTA
		if a.advance_timer > 0.0:
			i += 1
			continue
		a.advance_timer += Balance.ATTACK_RING_INTERVAL_SEC
		_advance_attack(a)
		if a.troops_remaining <= 0.0 or a.front.is_empty():
			state.attacks.remove_at(i)
			continue
		i += 1


func _advance_attack(a: Attack) -> void:
	var defender: Player = state.get_player(a.defender_id)
	if defender == null or not defender.is_alive or defender.land <= 0:
		a.troops_remaining = 0.0
		return
	var d_ratio: float = defender.troops / float(defender.land)
	var new_front: Dictionary = {}
	for ni: int in a.front.keys():
		var cur_owner: int = state.owners[ni]
		if cur_owner != a.defender_id:
			continue  # tile moved out of defender's hands already
		if state.is_blocked_terrain(state.terrain[ni]):
			continue
		var cost: float = _attack_tile_cost(ni, d_ratio)
		if a.troops_remaining < cost:
			new_front[ni] = true   # keep for next ring if we survive
			continue
		a.troops_remaining -= cost
		defender.troops = maxf(0.0, defender.troops - Balance.DEFENDER_LOSS_PER_TILE * d_ratio)
		var pos: Vector2i = state.idx_to_xy(ni)
		_claim_tile(a.attacker_id, pos.x, pos.y)
		_mark_flash(ni)
		for off in NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var nni: int = state.idx(nx, ny)
			if state.owners[nni] == a.defender_id:
				new_front[nni] = true
	a.front = new_front


func _attack_tile_cost(tile_idx: int, d_ratio: float) -> float:
	var t: int = state.terrain[tile_idx]
	var terrain_def: float = 1.0
	if t >= 0 and t < Balance.TERRAIN_DEFENSE.size():
		terrain_def = Balance.TERRAIN_DEFENSE[t]
	var extra_def: float = combined_defense_at(tile_idx)
	return Balance.ATTACK_TILE_COST_BASE + Balance.ATTACK_TILE_COST_SCALE * d_ratio * terrain_def * extra_def


# Non-terrain defense: Crown tile and zone (Prompt 6) and Fort / Wall (Prompt 8)
# live here so the attack cost function stays stable. Capped by BUILDING_DEFENSE_CAP
# everywhere except Crown tiles themselves.
func combined_defense_at(_tile_idx: int) -> float:
	return 1.0


func _mark_flash(tile_idx: int) -> void:
	state.flash_tiles[tile_idx] = state.match_time + 0.3
	state.dirty_tiles[tile_idx] = true


func _tick_placement() -> void:
	state.placement_time_left -= Balance.TICK_DELTA
	# Bots place as soon as they get a chance (first tick that reaches them).
	for p in state.players:
		if p.is_bot and p.crown_x < 0:
			var pos := _find_valid_crown_position()
			if pos.x >= 0:
				_place_crown(p, pos.x, pos.y)
	if state.placement_time_left <= 0.0:
		for p in state.players:
			if p.crown_x < 0:
				var pos := _find_valid_crown_position()
				_place_crown(p, pos.x, pos.y)
		state.phase = Balance.PHASE_MATCH


func _tick_bots() -> void:
	for p in state.players:
		if p.is_alive and p.is_bot:
			Bots.tick(self, p)


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


func _growth_multiplier(p: Player) -> float:
	var gem_bonus: float = minf(float(p.gem_tiles) * Balance.GEM_GROWTH_BONUS_PER_TILE, Balance.GEM_GROWTH_BONUS_MAX)
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

func player_place_crown(player_id: int, x: int, y: int) -> bool:
	if state.phase != Balance.PHASE_PLACEMENT:
		return false
	var p := state.get_player(player_id)
	if p == null or p.crown_x >= 0:
		return false
	if not _is_valid_crown_tile(x, y, Balance.CROWN_MIN_DIST_FROM_OTHER):
		return false
	_place_crown(p, x, y)
	return true


func player_expand(player_id: int, tx: int, ty: int, fraction: float) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	var p := state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	if not state.in_bounds(tx, ty):
		return false
	var target_owner: int = state.owners[state.idx(tx, ty)]
	if target_owner == player_id:
		return false
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
	if p.expansion_timer <= 0.0:
		p.expansion_timer = Balance.EXPANSION_RING_INTERVAL_SEC
	return true


# Target tile must be owned by another live player and touch the attacker's border.
# Up to Balance.MAX_SIMULTANEOUS_ATTACKS active attacks per player.
func player_attack(player_id: int, tx: int, ty: int, fraction: float) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	if state.match_time < Balance.PEACE_PERIOD_SEC:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	if not state.in_bounds(tx, ty):
		return false
	var target_owner: int = state.owners[state.idx(tx, ty)]
	if target_owner == 0 or target_owner == GameState.RUINS_OWNER_ID or target_owner == player_id:
		return false
	var defender: Player = state.get_player(target_owner)
	if defender == null or not defender.is_alive:
		return false
	if active_attack_count(player_id) >= Balance.MAX_SIMULTANEOUS_ATTACKS:
		return false
	var front: Dictionary = _build_attack_front(player_id, target_owner)
	if front.is_empty():
		return false
	var frac: float = clampf(fraction, Balance.SEND_MIN_FRACTION, Balance.SEND_MAX_FRACTION)
	var send: float = floorf(p.troops * frac)
	if send <= 0.0:
		return false
	p.troops -= send
	var atk := Attack.new()
	atk.attacker_id = player_id
	atk.defender_id = target_owner
	atk.troops_remaining = send
	atk.front = front
	atk.advance_timer = Balance.ATTACK_RING_INTERVAL_SEC
	state.attacks.append(atk)
	return true


func player_retreat(player_id: int, local_index: int) -> bool:
	var seen := 0
	for i in range(state.attacks.size()):
		var a: Attack = state.attacks[i]
		if a.attacker_id != player_id:
			continue
		if seen == local_index:
			var p: Player = state.get_player(player_id)
			if p != null:
				p.troops += a.troops_remaining * Balance.RETREAT_RETURN_FRACTION
			state.attacks.remove_at(i)
			return true
		seen += 1
	return false


func active_attack_count(player_id: int) -> int:
	var n := 0
	for a: Attack in state.attacks:
		if a.attacker_id == player_id:
			n += 1
	return n


func attacks_by(player_id: int) -> Array:
	var out: Array = []
	for a: Attack in state.attacks:
		if a.attacker_id == player_id:
			out.append(a)
	return out


func _build_attack_front(attacker_id: int, defender_id: int) -> Dictionary:
	var out: Dictionary = {}
	var attacker: Player = state.get_player(attacker_id)
	if attacker == null:
		return out
	for i: int in attacker.border.keys():
		var pos := state.idx_to_xy(i)
		for off in NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var ni := state.idx(nx, ny)
			if state.owners[ni] != defender_id:
				continue
			if state.is_blocked_terrain(state.terrain[ni]):
				continue
			out[ni] = true
	return out


# --- Crown placement --------------------------------------------------------

func _place_crown(player: Player, cx: int, cy: int) -> void:
	player.crown_x = cx
	player.crown_y = cy
	player.troops = Balance.STARTING_TROOPS
	# Mark 3x3 Crown tiles for drawing and the centre.
	for off in CROWN_OFFSETS:
		var tx: int = cx + off.x
		var ty: int = cy + off.y
		if not state.in_bounds(tx, ty):
			continue
		var ti := state.idx(tx, ty)
		state.crown_tiles[ti] = player.id
		state.dirty_tiles[ti] = true
	state.crown_centres[player.id] = state.idx(cx, cy)
	# Claim the starting radius-4 circle (which includes the 3x3).
	_claim_circle(player, cx, cy, Balance.STARTING_LAND_RADIUS)


func _is_valid_crown_tile(x: int, y: int, min_dist_from_other: int) -> bool:
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
		var tt: int = state.terrain[state.idx(tx, ty)]
		if state.is_blocked_terrain(tt):
			return false
	# Keep Crowns apart.
	var md2: int = min_dist_from_other * min_dist_from_other
	for other in state.players:
		if other.crown_x < 0:
			continue
		var dx: int = other.crown_x - x
		var dy: int = other.crown_y - y
		if dx * dx + dy * dy < md2:
			return false
	return true


func _find_valid_crown_position() -> Vector2i:
	var min_x: int = Balance.CROWN_MIN_DIST_FROM_EDGE
	var min_y: int = Balance.CROWN_MIN_DIST_FROM_EDGE
	var max_x: int = state.width - Balance.CROWN_MIN_DIST_FROM_EDGE
	var max_y: int = state.height - Balance.CROWN_MIN_DIST_FROM_EDGE
	# Try full spacing first.
	for _attempt in range(800):
		var x: int = state.rng.randi_range(min_x, max_x - 1)
		var y: int = state.rng.randi_range(min_y, max_y - 1)
		if _is_valid_crown_tile(x, y, Balance.CROWN_MIN_DIST_FROM_OTHER):
			return Vector2i(x, y)
	# Fallback: relax the inter-Crown distance.
	@warning_ignore("integer_division")
	var relaxed: int = Balance.CROWN_MIN_DIST_FROM_OTHER / 2
	for _attempt in range(800):
		var x: int = state.rng.randi_range(min_x, max_x - 1)
		var y: int = state.rng.randi_range(min_y, max_y - 1)
		if _is_valid_crown_tile(x, y, relaxed):
			return Vector2i(x, y)
	return Vector2i(-1, -1)


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
		var nx: int = pos.x + off.x
		var ny: int = pos.y + off.y
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
		var nx: int = pos.x + off.x
		var ny: int = pos.y + off.y
		if not state.in_bounds(nx, ny):
			continue
		if state.owners[state.idx(nx, ny)] != owner_id:
			return true
	return false


func _tile_touches_player(x: int, y: int, player_id: int) -> bool:
	for off in NEIGHBOR_OFFSETS:
		var nx: int = x + off.x
		var ny: int = y + off.y
		if not state.in_bounds(nx, ny):
			continue
		if state.owners[state.idx(nx, ny)] == player_id:
			return true
	return false
