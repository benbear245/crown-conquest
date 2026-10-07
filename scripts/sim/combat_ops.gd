class_name CombatOps
extends RefCounted

# Attacks: starting them, advancing their fronts ring by ring, tile costs and
# defense. Pure sim, called by Simulation.

const NEIGHBOR_OFFSETS: Array[Vector2i] = TerritoryOps.NEIGHBOR_OFFSETS


# Opens an attack from an already-paid troop pool. Shared by tap attacks and
# boat landings. Returns false (nothing changed) if the attack isn't allowed.
static func can_attack(sim: Simulation, attacker: Player, defender_id: int) -> bool:
	var state: GameState = sim.state
	if state.is_peace():
		return false
	if not state.is_player_owner(defender_id) or defender_id == attacker.id:
		return false
	var defender: Player = state.get_player(defender_id)
	if defender == null or not defender.is_alive:
		return false
	return sim.active_attack_count(attacker.id) < Balance.MAX_SIMULTANEOUS_ATTACKS


static func open_attack(sim: Simulation, attacker: Player, defender_id: int, troops: float, front: Dictionary) -> void:
	var state: GameState = sim.state
	# Attacking a truce partner breaks the truce and makes you an Oathbreaker.
	if TrucesOps.has_truce(attacker, defender_id, state.match_time):
		TrucesOps.break_truce(sim, attacker.id, defender_id)
	var atk := Attack.new()
	atk.attacker_id = attacker.id
	atk.defender_id = defender_id
	atk.troops_remaining = troops
	atk.front = front
	atk.advance_timer = Balance.ATTACK_RING_INTERVAL_SEC
	state.attacks.append(atk)
	if attacker.is_bot:
		attacker.plan_target_id = defender_id


static func build_attack_front(state: GameState, attacker: Player, defender_id: int) -> Dictionary:
	var out: Dictionary = {}
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


# --- Ticking -----------------------------------------------------------------

static func tick_attacks(sim: Simulation) -> void:
	var state: GameState = sim.state
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
		_advance_attack(sim, a)
		# _advance_attack may have removed this attack (defender eliminated).
		if i >= state.attacks.size() or state.attacks[i] != a:
			continue
		if a.troops_remaining <= 0.0 or a.front.is_empty():
			state.attacks.remove_at(i)
			continue
		i += 1


static func _advance_attack(sim: Simulation, a: Attack) -> void:
	var state: GameState = sim.state
	var defender: Player = state.get_player(a.defender_id)
	if defender == null or not defender.is_alive or defender.land <= 0:
		a.troops_remaining = 0.0
		return
	var d_ratio: float = defender.troops / float(defender.land)
	var shield_active: bool = AbilitiesOps.is_crown_shield_active(defender, state.match_time) and not state.is_final_siege()
	var shield_r2: int = defender.crown_zone_radius() * defender.crown_zone_radius()
	var new_front: Dictionary = {}
	var stalled_cost: float = 0.0
	var captured: int = 0
	for ni: int in a.front.keys():
		if state.owners[ni] != a.defender_id:
			continue
		if state.is_blocked_terrain(state.terrain[ni]):
			continue
		var pos: Vector2i = state.idx_to_xy(ni)
		# Crown Shield: can't take tiles inside the defender's Crown zone.
		if shield_active and defender.crown_x >= 0:
			var dxs: int = pos.x - defender.crown_x
			var dys: int = pos.y - defender.crown_y
			if dxs * dxs + dys * dys <= shield_r2:
				new_front[ni] = true
				continue
		var cost: float = attack_tile_cost(sim, ni, d_ratio, a.attacker_id)
		if a.troops_remaining < cost:
			new_front[ni] = true
			stalled_cost += cost
			continue
		a.troops_remaining -= cost
		captured += 1
		defender.troops = maxf(0.0, defender.troops - Balance.DEFENDER_LOSS_PER_TILE * d_ratio)
		var was_centre: bool = state.crown_centres.get(a.defender_id, -1) == ni
		TerritoryOps.claim_tile(sim, a.attacker_id, pos.x, pos.y)
		sim.mark_flash(ni)
		if was_centre:
			MatchOps.eliminate_player(sim, a.defender_id, a.attacker_id)
			# Defender is gone; this attack was removed by end_attacks_touching.
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
	a.last_ring_cost = stalled_cost
	# Out of steam: the attack can't afford a single tile, so it pulls back on
	# its own (same refund as a retreat) and frees the attack slot.
	if captured == 0 and stalled_cost > 0.0:
		var attacker: Player = state.get_player(a.attacker_id)
		if attacker != null:
			attacker.troops += a.troops_remaining * Balance.RETREAT_RETURN_FRACTION
		a.troops_remaining = 0.0


# Troop cost for the attacker to take one enemy tile.
static func attack_tile_cost(sim: Simulation, tile_idx: int, d_ratio: float, attacker_id: int = 0) -> float:
	var state: GameState = sim.state
	var t: int = state.terrain[tile_idx]
	var terrain_def: float = 1.0
	if t >= 0 and t < Balance.TERRAIN_DEFENSE.size():
		terrain_def = Balance.TERRAIN_DEFENSE[t]
	var extra_def: float = combined_defense_at(sim, tile_idx)
	# Bombard halves the defender's defense on tiles inside its area.
	if AbilitiesOps.tile_in_any_bombard(state, tile_idx):
		extra_def *= Balance.BOMBARD_DEFENSE_MULT
	var cost: float = Balance.ATTACK_TILE_COST_BASE + Balance.ATTACK_TILE_COST_SCALE * d_ratio * terrain_def * extra_def
	var p: Player = state.get_player(attacker_id)
	if p == null:
		return cost
	var now: float = state.match_time
	# Rally reduces attack cost by 30% while active.
	if AbilitiesOps.is_rally_active(p, now):
		cost *= 1.0 - Balance.RALLY_ATTACK_DISCOUNT
	# Shrine of War holders attack for less.
	if ShrinesOps.holds_kind(state, attacker_id, Balance.SHRINE_WAR):
		cost *= 1.0 - Balance.SHRINE_WAR_ATTACK_DISCOUNT
	# Oathbreaker: +20% cost for 45 s after breaking a truce.
	if TrucesOps.is_oathbreaker(p, now):
		cost *= 1.0 + Balance.OATHBREAKER_ATTACK_PENALTY
	# Rising Empire: everyone's attacks on the leader cost 15% less.
	var rising: int = sim.rising_empire_id()
	if rising > 0 and state.owners[tile_idx] == rising and attacker_id != rising:
		cost *= 1.0 - Balance.RISING_EMPIRE_ATTACK_DISCOUNT
	return cost


# Non-terrain defense: Crown tile and zone, plus Fort, Wall and Shrine.
# Crown tiles ignore the x4 building cap. Final Siege weakens Crown tiles
# and disables the zone bonus and Keep upgrades. A Crown that is being moved
# has no special defense at all.
static func combined_defense_at(sim: Simulation, tile_idx: int) -> float:
	var state: GameState = sim.state
	var owner_id: int = state.owners[tile_idx]
	if not state.is_player_owner(owner_id):
		return 1.0
	var now: float = state.match_time
	var is_siege: bool = state.is_final_siege()
	var owner_player: Player = state.get_player(owner_id)
	var moving: bool = owner_player != null and owner_player.is_moving_crown(now)
	# Crown tile: its own defense, ignores the x4 cap and other buildings.
	if state.crown_tiles.has(tile_idx) and state.crown_tiles[tile_idx] == owner_id:
		if moving:
			return 1.0
		if is_siege:
			return Balance.FINAL_SIEGE_CROWN_TILE_DEFENSE
		return owner_player.crown_tile_defense() if owner_player != null else Balance.CROWN_TILE_DEFENSE
	var def: float = 1.0
	var pos: Vector2i = state.idx_to_xy(tile_idx)
	if not is_siege and not moving and owner_player != null and owner_player.crown_x >= 0:
		var dx: int = pos.x - owner_player.crown_x
		var dy: int = pos.y - owner_player.crown_y
		var r: int = owner_player.crown_zone_radius()
		if dx * dx + dy * dy <= r * r:
			def *= owner_player.crown_zone_defense()
	# Fort coverage: best of this player's working Forts whose radius covers the tile.
	if owner_player != null and owner_player.fort_tiles.size() > 0:
		var best_fort: float = 1.0
		for ft_idx: int in owner_player.fort_tiles:
			var b: Building = state.building_at_tile.get(ft_idx, null)
			if b == null or b.owner_id != owner_id or not b.is_active(now):
				continue
			var r: int = b.radius()
			var fdx: int = pos.x - b.x
			var fdy: int = pos.y - b.y
			if fdx * fdx + fdy * fdy <= r * r:
				best_fort = maxf(best_fort, b.defense_mult())
		def *= best_fort
	if state.wall_tiles.has(tile_idx) and state.wall_tiles[tile_idx] == owner_id:
		def *= Balance.WALL_DEFENSE
	if state.shrine_at_tile.has(tile_idx):
		def *= Balance.SHRINE_DEFENSE
	return minf(def, Balance.BUILDING_DEFENSE_CAP)


static func retreat(sim: Simulation, player_id: int, local_index: int) -> bool:
	var state: GameState = sim.state
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


static func end_attacks_touching(state: GameState, player_id: int) -> void:
	var i := 0
	while i < state.attacks.size():
		var a: Attack = state.attacks[i]
		if a.attacker_id == player_id or a.defender_id == player_id:
			state.attacks.remove_at(i)
			continue
		i += 1


# Sets crown_alert_until for any player whose Crown zone an attack front reaches.
static func check_crown_alerts(sim: Simulation) -> void:
	var state: GameState = sim.state
	for a: Attack in state.attacks:
		var defender: Player = state.get_player(a.defender_id)
		if defender == null or defender.crown_x < 0:
			continue
		var r: int = defender.crown_zone_radius()
		var r2: int = r * r
		for ni: int in a.front.keys():
			var pos: Vector2i = state.idx_to_xy(ni)
			var dx: int = pos.x - defender.crown_x
			var dy: int = pos.y - defender.crown_y
			if dx * dx + dy * dy <= r2:
				if defender.crown_alert_until <= state.match_time:
					sim.emit({"type": "crown_alert", "player_id": defender.id, "attacker_id": a.attacker_id})
				defender.crown_alert_until = state.match_time + 2.0
				break
