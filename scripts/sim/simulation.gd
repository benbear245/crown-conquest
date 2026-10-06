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
# Headless mode: skip HUD-only bookkeeping (crown alerts, flash fades) so the
# balance sim can run many matches without paying for rendering state it won't use.
var headless: bool = false
var _final_siege_announced: bool = false
# Cached average land of alive players for Underdog / Empire upkeep checks.
# Refreshed once a second (10 ticks) rather than every tick, since the number
# changes slowly compared to the hot path.
var _avg_land_cache: float = 0.0
var _avg_recompute_at: int = 0
# Who the Rising Empire is (-1 if nobody owns > 30% of the map). Refreshed with
# the avg cache. Used by _attack_tile_cost to discount attacks on them.
var _rising_empire_id: int = -1


# --- Match setup -------------------------------------------------------------

func start_default_match(match_seed: int = 0) -> void:
	start_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, match_seed, 7)


func start_match(size: int, mt: int, match_seed: int, num_bots: int = -1) -> void:
	size_preset = size
	map_type = mt
	_final_siege_announced = false
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
			_announce_final_siege_once()
			_recompute_avg_land_once_per_second()
			_apply_growth()
			_apply_expansions()
			AbilitiesOps.tick(self)
			TrucesOps.tick(self)
			_tick_attacks()
			_tick_boats()
			if not headless:
				_tick_flashes()
				_check_crown_alerts()
				_tick_loot_popups()
			_tick_bots()
			_check_win_conditions()
	state.tick_count += 1


func _announce_final_siege_once() -> void:
	if _final_siege_announced:
		return
	if not state.is_final_siege():
		return
	_final_siege_announced = true
	_announce("Final Siege begins — Crowns weaken, plunder doubles.")


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
		# _advance_attack may have removed this attack (defender eliminated).
		if i >= state.attacks.size() or state.attacks[i] != a:
			continue
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
	var shield_active: bool = AbilitiesOps.is_crown_shield_active(defender, state.match_time) and not state.is_final_siege()
	var shield_r2: int = defender.crown_zone_radius() * defender.crown_zone_radius()
	var new_front: Dictionary = {}
	for ni: int in a.front.keys():
		var cur_owner: int = state.owners[ni]
		if cur_owner != a.defender_id:
			continue
		if state.is_blocked_terrain(state.terrain[ni]):
			continue
		# Crown Shield: can't take tiles inside the defender's Crown zone.
		if shield_active and defender.crown_x >= 0:
			var pos2: Vector2i = state.idx_to_xy(ni)
			var dxs: int = pos2.x - defender.crown_x
			var dys: int = pos2.y - defender.crown_y
			if dxs * dxs + dys * dys <= shield_r2:
				new_front[ni] = true
				continue
		var cost: float = _attack_tile_cost(ni, d_ratio, a.attacker_id)
		if a.troops_remaining < cost:
			new_front[ni] = true
			continue
		a.troops_remaining -= cost
		defender.troops = maxf(0.0, defender.troops - Balance.DEFENDER_LOSS_PER_TILE * d_ratio)
		var pos: Vector2i = state.idx_to_xy(ni)
		var was_centre: bool = state.crown_centres.get(a.defender_id, -1) == ni
		_claim_tile(a.attacker_id, pos.x, pos.y)
		_mark_flash(ni)
		if was_centre:
			_eliminate_player(a.defender_id, a.attacker_id)
			# Defender is gone; this attack was removed by _end_attacks_against.
			return
		for off in NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var nni: int = state.idx(nx, ny)
			if state.owners[nni] == a.defender_id:
				new_front[nni] = true
	a.front = new_front


func _attack_tile_cost(tile_idx: int, d_ratio: float, attacker_id: int = 0) -> float:
	var t: int = state.terrain[tile_idx]
	var terrain_def: float = 1.0
	if t >= 0 and t < Balance.TERRAIN_DEFENSE.size():
		terrain_def = Balance.TERRAIN_DEFENSE[t]
	var extra_def: float = combined_defense_at(tile_idx)
	# Bombard halves the defender's defense on tiles inside its area.
	if AbilitiesOps.tile_in_any_bombard(state, tile_idx):
		extra_def *= Balance.BOMBARD_DEFENSE_MULT
	var cost: float = Balance.ATTACK_TILE_COST_BASE + Balance.ATTACK_TILE_COST_SCALE * d_ratio * terrain_def * extra_def
	if attacker_id > 0:
		var p: Player = state.get_player(attacker_id)
		if p != null:
			# Rally reduces attack cost by 30% while active.
			if AbilitiesOps.is_rally_active(p, state.match_time):
				cost *= (1.0 - Balance.RALLY_ATTACK_DISCOUNT)
			# Oathbreaker: +20% cost for 45 s after breaking a truce.
			if TrucesOps.is_oathbreaker(p, state.match_time):
				cost *= (1.0 + Balance.OATHBREAKER_ATTACK_PENALTY)
			# Rising Empire: everyone's attacks on the leader cost 15% less.
			var owner: int = state.owners[tile_idx]
			if _rising_empire_id > 0 and owner == _rising_empire_id and attacker_id != _rising_empire_id:
				cost *= (1.0 - Balance.RISING_EMPIRE_ATTACK_DISCOUNT)
	return cost


# Non-terrain defense: Crown tile and zone, plus Fort and Wall.
# Crown tiles ignore the x4 building cap. Final Siege weakens Crown tiles
# and disables the zone bonus and Keep upgrades.
func combined_defense_at(tile_idx: int) -> float:
	var owner: int = state.owners[tile_idx]
	if owner <= 0 or owner == GameState.RUINS_OWNER_ID:
		return 1.0
	var is_siege: bool = state.is_final_siege()
	var owner_player: Player = state.get_player(owner)
	# Crown tile: its own defense, ignores the x4 cap and other buildings.
	if state.crown_tiles.has(tile_idx) and state.crown_tiles[tile_idx] == owner:
		if is_siege:
			return Balance.FINAL_SIEGE_CROWN_TILE_DEFENSE
		if owner_player != null:
			return owner_player.crown_tile_defense()
		return Balance.CROWN_TILE_DEFENSE
	var def: float = 1.0
	if not is_siege and owner_player != null and owner_player.crown_x >= 0:
		var pos: Vector2i = state.idx_to_xy(tile_idx)
		var dx: int = pos.x - owner_player.crown_x
		var dy: int = pos.y - owner_player.crown_y
		var r: int = owner_player.crown_zone_radius()
		if dx * dx + dy * dy <= r * r:
			def *= owner_player.crown_zone_defense()
	# Fort coverage: max of all this player's Forts whose radius covers the tile.
	if owner_player != null and owner_player.fort_tiles.size() > 0:
		var pos: Vector2i = state.idx_to_xy(tile_idx)
		var best_fort: float = 1.0
		for ft_idx: int in owner_player.fort_tiles:
			var b: Building = state.building_at_tile.get(ft_idx, null)
			if b == null or b.owner_id != owner:
				continue
			var r: int = b.radius()
			var fdx: int = pos.x - b.x
			var fdy: int = pos.y - b.y
			if fdx * fdx + fdy * fdy <= r * r:
				var m: float = b.defense_mult()
				if m > best_fort:
					best_fort = m
		def *= best_fort
	# Wall tile?
	if state.wall_tiles.has(tile_idx) and state.wall_tiles[tile_idx] == owner:
		def *= Balance.WALL_DEFENSE
	return minf(def, Balance.BUILDING_DEFENSE_CAP)


# --- Alerts, win conditions, elimination ------------------------------------

func _check_crown_alerts() -> void:
	if state.attacks.is_empty():
		return
	var r2: int = Balance.CROWN_ZONE_RADIUS * Balance.CROWN_ZONE_RADIUS
	for a: Attack in state.attacks:
		var defender: Player = state.get_player(a.defender_id)
		if defender == null or defender.crown_x < 0:
			continue
		for ni_v in a.front.keys():
			var ni: int = ni_v
			var pos: Vector2i = state.idx_to_xy(ni)
			var dx: int = pos.x - defender.crown_x
			var dy: int = pos.y - defender.crown_y
			if dx * dx + dy * dy <= r2:
				defender.crown_alert_until = state.match_time + 2.0
				break


func _check_win_conditions() -> void:
	var alive: Array = []
	for p: Player in state.players:
		if p.is_alive:
			alive.append(p)
	if alive.size() <= 1:
		if alive.size() == 1:
			_end_match((alive[0] as Player).id, "Last Crown standing")
		else:
			_end_match(0, "Draw")
		return
	var usable: int = state.total_usable_tiles()
	if usable > 0:
		for p: Player in alive:
			if float(p.land) / float(usable) >= Balance.DOMINION_WIN_FRACTION:
				_end_match(p.id, "Dominion win (60%+ of the usable map)")
				return
	if state.match_time >= Balance.MATCH_TIME_LIMIT_SEC:
		var leader: Player = alive[0]
		for p: Player in alive:
			if p.land > leader.land:
				leader = p
		_end_match(leader.id, "Most land at the 15:00 limit")


func _end_match(winner_id: int, reason: String) -> void:
	state.phase = Balance.PHASE_ENDED
	state.winner_id = winner_id
	state.win_reason = reason
	state.attacks.clear()
	if winner_id > 0:
		var w: Player = state.get_player(winner_id)
		if w != null:
			_announce("%s wins! %s" % [w.display_name, reason])
	else:
		_announce("Match ends: %s" % reason)


func _eliminate_player(victim_id: int, capturer_id: int) -> void:
	var victim: Player = state.get_player(victim_id)
	if victim == null or not victim.is_alive:
		return
	victim.is_alive = false
	var plunder_frac: float = Balance.FINAL_SIEGE_PLUNDER_FRACTION if state.is_final_siege() else Balance.CROWN_PLUNDER_FRACTION
	var plunder: float = victim.troops * plunder_frac
	victim.troops = 0.0
	var capturer: Player = state.get_player(capturer_id)
	if capturer != null:
		capturer.troops += plunder
		capturer.crowns_captured += 1
	# Victim's territory becomes Ruins.
	for i in range(state.owners.size()):
		if state.owners[i] == victim_id:
			state.owners[i] = GameState.RUINS_OWNER_ID
			state.dirty_tiles[i] = true
	# Drop the victim's Crown data.
	var crown_tile_keys: Array = state.crown_tiles.keys()
	for t_idx_v in crown_tile_keys:
		var t_idx: int = t_idx_v
		if state.crown_tiles[t_idx] == victim_id:
			state.crown_tiles.erase(t_idx)
			state.dirty_tiles[t_idx] = true
	state.crown_centres.erase(victim_id)
	victim.border.clear()
	victim.land = 0
	victim.gem_tiles = 0
	# Destroy all the victim's buildings and walls (land is Ruins now; no loot).
	var vb_idx := 0
	while vb_idx < state.buildings.size():
		var b: Building = state.buildings[vb_idx]
		if b.owner_id == victim_id:
			state.building_at_tile.erase(b.tile_idx)
			state.buildings.remove_at(vb_idx)
			continue
		vb_idx += 1
	var wall_keys: Array = state.wall_tiles.keys()
	for wk in wall_keys:
		if state.wall_tiles[wk] == victim_id:
			state.wall_tiles.erase(wk)
	victim.fort_count = 0
	victim.barracks_count = 0
	victim.port_count = 0
	victim.wall_count = 0
	victim.fort_tiles = PackedInt32Array()
	# Drop any boats the victim had and any targeting them.
	var bo_idx := 0
	while bo_idx < state.boats.size():
		var bo: Boat = state.boats[bo_idx]
		if bo.owner_id == victim_id:
			state.boats.remove_at(bo_idx)
			continue
		bo_idx += 1
	# End every attack involving the dead player.
	_end_attacks_touching(victim_id)
	_rebuild_borders_for_all()
	var capturer_name: String = capturer.display_name if capturer != null else "An attacker"
	_announce("%s has taken %s's Crown!" % [capturer_name, victim.display_name])


func _end_attacks_touching(player_id: int) -> void:
	var i := 0
	while i < state.attacks.size():
		var a: Attack = state.attacks[i]
		if a.attacker_id == player_id or a.defender_id == player_id:
			state.attacks.remove_at(i)
			continue
		i += 1


func _rebuild_borders_for_all() -> void:
	for p: Player in state.players:
		p.border.clear()
	for i in range(state.owners.size()):
		var ow: int = state.owners[i]
		var p: Player = state.get_player(ow)
		if p == null:
			continue
		if _tile_is_border(i, ow):
			p.border[i] = true


func _announce(text: String) -> void:
	state.active_announcement_text = text
	state.active_announcement_until = state.match_time + 4.0


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
	var mult: float = 1.0
	var gem_bonus: float = minf(float(p.gem_tiles) * Balance.GEM_GROWTH_BONUS_PER_TILE, Balance.GEM_GROWTH_BONUS_MAX)
	mult += gem_bonus
	# Underdog: your land under 50% of the current alive average.
	if _avg_land_cache > 0.0 and float(p.land) < Balance.UNDERDOG_LAND_FRACTION_OF_AVG * _avg_land_cache:
		mult += Balance.UNDERDOG_GROWTH_BONUS
	# Empire upkeep: tiered penalty for owning too much.
	var usable: int = state.total_usable_tiles()
	if usable > 0:
		var frac: float = float(p.land) / float(usable)
		if frac >= Balance.EMPIRE_UPKEEP_LAND_THRESHOLD_2:
			mult += Balance.EMPIRE_UPKEEP_PENALTY_2
		elif frac >= Balance.EMPIRE_UPKEEP_LAND_THRESHOLD_1:
			mult += Balance.EMPIRE_UPKEEP_PENALTY_1
	return maxf(mult, 0.1)


func _recompute_avg_land_once_per_second() -> void:
	if state.tick_count < _avg_recompute_at:
		return
	_avg_recompute_at = state.tick_count + Balance.TICKS_PER_SECOND
	var alive_land: int = 0
	var alive_count: int = 0
	var usable: int = state.total_usable_tiles()
	_rising_empire_id = -1
	var biggest_land: int = -1
	for p: Player in state.players:
		if not p.is_alive:
			continue
		alive_land += p.land
		alive_count += 1
		if p.land > biggest_land:
			biggest_land = p.land
			if usable > 0 and float(p.land) / float(usable) > Balance.RISING_EMPIRE_LAND_THRESHOLD:
				_rising_empire_id = p.id
			else:
				_rising_empire_id = -1
	_avg_land_cache = float(alive_land) / float(maxi(alive_count, 1))


func rising_empire_id() -> int:
	return _rising_empire_id


func is_underdog(p: Player) -> bool:
	if _avg_land_cache <= 0.0:
		return false
	return float(p.land) < Balance.UNDERDOG_LAND_FRACTION_OF_AVG * _avg_land_cache


func _apply_expansions() -> void:
	for p in state.players:
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
	# Attacking a truce partner breaks the truce and makes you an Oathbreaker.
	if TrucesOps.has_truce(p, target_owner, state.match_time):
		TrucesOps.break_truce(self, player_id, target_owner)
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
	var discount: float = 1.0
	if AbilitiesOps.is_swift_march_active(player, state.match_time):
		discount *= 1.0 - Balance.SWIFT_MARCH_CLAIM_DISCOUNT
	if is_underdog(player):
		discount *= 1.0 - Balance.UNDERDOG_CLAIM_DISCOUNT
	var min_cost := INF
	for ni: int in frontier:
		var ow: int = state.owners[ni]
		var cost := _claim_cost_idx(ni, ow) * discount
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
	# Destroy any building/wall the previous owner had here; the capturer
	# gets 25% of its cost as loot.
	if prev > 0 and prev != GameState.RUINS_OWNER_ID:
		_destroy_building_at(i, prev, player_id)
		_destroy_wall_at(i, prev, player_id)
	state.set_owner_idx(i, player_id)
	_update_borders_on_change(i, prev, player_id)


func _destroy_building_at(tile_idx: int, old_owner: int, capturer_id: int) -> void:
	var b: Building = state.building_at_tile.get(tile_idx, null)
	if b == null or b.owner_id != old_owner:
		return
	state.building_at_tile.erase(tile_idx)
	for idx in range(state.buildings.size()):
		if state.buildings[idx] == b:
			state.buildings.remove_at(idx)
			break
	var old_p: Player = state.get_player(old_owner)
	if old_p != null:
		match b.type:
			Balance.BUILDING_FORT, Balance.BUILDING_FORT2:
				old_p.fort_count = maxi(0, old_p.fort_count - 1)
				_remove_from_packed(old_p, tile_idx)
			Balance.BUILDING_BARRACKS:
				old_p.barracks_count = maxi(0, old_p.barracks_count - 1)
			Balance.BUILDING_PORT:
				old_p.port_count = maxi(0, old_p.port_count - 1)
	var cap_p: Player = state.get_player(capturer_id)
	if cap_p != null:
		var loot: float = b.cost() * Balance.CAPTURED_BUILDING_LOOT_FRACTION
		cap_p.troops += loot
		if not headless:
			state.loot_popups[tile_idx] = {"owner_id": capturer_id, "amount": int(loot), "until": state.match_time + 1.6}


func _destroy_wall_at(tile_idx: int, old_owner: int, capturer_id: int) -> void:
	if not state.wall_tiles.has(tile_idx):
		return
	if state.wall_tiles[tile_idx] != old_owner:
		return
	state.wall_tiles.erase(tile_idx)
	var old_p: Player = state.get_player(old_owner)
	if old_p != null:
		old_p.wall_count = maxi(0, old_p.wall_count - 1)
	var cap_p: Player = state.get_player(capturer_id)
	if cap_p != null:
		var loot: float = Balance.WALL_COST_PER_TILE * Balance.CAPTURED_BUILDING_LOOT_FRACTION
		cap_p.troops += loot


func _remove_from_packed(p: Player, tile_idx: int) -> void:
	var out := PackedInt32Array()
	for v in p.fort_tiles:
		if v != tile_idx:
			out.append(v)
	p.fort_tiles = out


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


# --- Building and Keep commands (thin wrappers around BuildingsOps) ---------

func player_build_fort(player_id: int, x: int, y: int) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	return BuildingsOps.build_fort(self, p, x, y)


func player_upgrade_fort(player_id: int, x: int, y: int) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	return BuildingsOps.upgrade_fort(self, p, x, y)


func player_build_barracks(player_id: int, x: int, y: int) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	return BuildingsOps.build_barracks(self, p, x, y)


func player_build_port(player_id: int, x: int, y: int) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	return BuildingsOps.build_port(self, p, x, y)


func player_build_wall(player_id: int, x: int, y: int) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	return BuildingsOps.build_wall(self, p, x, y)


func player_buy_keep(player_id: int, level: int) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	return BuildingsOps.buy_keep(self, p, level)


func player_launch_boat(player_id: int, port_x: int, port_y: int,
		target_x: int, target_y: int, fraction: float) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	return BoatsOps.try_launch(self, p, port_x, port_y, target_x, target_y, fraction)


# --- Ability commands -------------------------------------------------------

func player_activate_swift_march(player_id: int) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	return AbilitiesOps.activate_swift_march(self, p)


func player_activate_crown_shield(player_id: int) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	return AbilitiesOps.activate_crown_shield(self, p)


func player_activate_rally(player_id: int) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	return AbilitiesOps.activate_rally(self, p)


func player_activate_bombard(player_id: int, target_x: int, target_y: int) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return false
	return AbilitiesOps.activate_bombard(self, p, target_x, target_y)


# --- Truce commands ---------------------------------------------------------

func player_offer_truce(player_id: int, target_id: int) -> bool:
	if state.phase != Balance.PHASE_MATCH:
		return false
	return TrucesOps.offer(self, player_id, target_id)


# --- Boats and loot popups ---------------------------------------------------

func _tick_boats() -> void:
	if state.boats.is_empty():
		return
	BoatsOps.tick(self)


func boat_land(b: Boat) -> void:
	var p: Player = state.get_player(b.owner_id)
	if p == null or not p.is_alive:
		return
	var tx: int = b.landing_tile_x
	var ty: int = b.landing_tile_y
	if not state.in_bounds(tx, ty):
		return
	var ti: int = state.idx(tx, ty)
	# Pay to claim the landing tile. If troops short, boat is lost.
	var terrain_cost: float = _claim_cost_idx(ti, state.owners[ti])
	if state.owners[ti] > 0 and state.owners[ti] != GameState.RUINS_OWNER_ID:
		# Enemy: boat opens an attack from this landing tile.
		var defender: Player = state.get_player(state.owners[ti])
		if defender == null or not defender.is_alive:
			return
		if active_attack_count(p.id) >= Balance.MAX_SIMULTANEOUS_ATTACKS:
			return
		var atk := Attack.new()
		atk.attacker_id = p.id
		atk.defender_id = defender.id
		atk.troops_remaining = b.troops
		atk.front = {ti: true}
		atk.advance_timer = Balance.ATTACK_RING_INTERVAL_SEC
		state.attacks.append(atk)
		return
	if b.troops < terrain_cost:
		return
	b.troops -= terrain_cost
	_claim_tile(p.id, tx, ty)
	# Rest of troops roll into the player's expansion bucket.
	p.expansion_troops += b.troops
	if p.expansion_timer <= 0.0:
		p.expansion_timer = Balance.EXPANSION_RING_INTERVAL_SEC


func _tick_loot_popups() -> void:
	if state.loot_popups.is_empty():
		return
	var expired: Array = []
	for k in state.loot_popups.keys():
		var info: Dictionary = state.loot_popups[k]
		if state.match_time >= float(info["until"]):
			expired.append(k)
	for k in expired:
		state.loot_popups.erase(k)
