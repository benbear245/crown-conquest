class_name CombatOps
extends RefCounted

# Attacks, tile defense, Crown alerts and elimination. Pure sim code.

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]
# How long the "Crown under attack" alert stays up after the last front touch.
const CROWN_ALERT_HOLD_SEC: float = 2.0


# Target tile must be owned by another live player and touch the attacker's border.
# Up to Balance.MAX_SIMULTANEOUS_ATTACKS active attacks per player.
static func player_attack(sim: Simulation, player_id: int, tx: int, ty: int, fraction: float) -> bool:
	var state: GameState = sim.state
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
	if active_attack_count(state, player_id) >= Balance.MAX_SIMULTANEOUS_ATTACKS:
		return false
	var front: Dictionary = build_attack_front(state, player_id, target_owner)
	if front.is_empty():
		return false
	var frac: float = clampf(fraction, Balance.SEND_MIN_FRACTION, Balance.SEND_MAX_FRACTION)
	var send: float = floorf(p.troops * frac)
	if send <= 0.0:
		return false
	# Attacking a truce partner breaks the truce and makes you an Oathbreaker.
	if TrucesOps.has_truce(p, target_owner, state.match_time):
		TrucesOps.break_truce(sim, player_id, target_owner)
	p.troops -= send
	var atk := Attack.new()
	atk.attacker_id = player_id
	atk.defender_id = target_owner
	atk.troops_remaining = send
	atk.troops_sent = send
	atk.front = front
	atk.advance_timer = Balance.ATTACK_RING_INTERVAL_SEC
	state.attacks.append(atk)
	return true


static func player_retreat(sim: Simulation, player_id: int, local_index: int) -> bool:
	var state: GameState = sim.state
	var seen: int = 0
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


static func active_attack_count(state: GameState, player_id: int) -> int:
	var n: int = 0
	for a: Attack in state.attacks:
		if a.attacker_id == player_id:
			n += 1
	return n


static func build_attack_front(state: GameState, attacker_id: int, defender_id: int) -> Dictionary:
	var out: Dictionary = {}
	var attacker: Player = state.get_player(attacker_id)
	if attacker == null:
		return out
	for i: int in attacker.border.keys():
		var pos: Vector2i = state.idx_to_xy(i)
		for off in NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var ni: int = state.idx(nx, ny)
			if state.owners[ni] != defender_id:
				continue
			if state.is_blocked_terrain(state.terrain[ni]):
				continue
			out[ni] = true
	return out


# --- Per-tick ----------------------------------------------------------------

static func tick_attacks(sim: Simulation) -> void:
	var state: GameState = sim.state
	var i: int = 0
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
		advance_attack(sim, a)
		# advance_attack may have removed this attack (defender eliminated).
		if i >= state.attacks.size() or state.attacks[i] != a:
			continue
		if a.troops_remaining <= 0.0 or a.front.is_empty():
			state.attacks.remove_at(i)
			continue
		i += 1


static func advance_attack(sim: Simulation, a: Attack) -> void:
	var state: GameState = sim.state
	var defender: Player = state.get_player(a.defender_id)
	if defender == null or not defender.is_alive or defender.land <= 0:
		a.troops_remaining = 0.0
		return
	var d_ratio: float = defender.troops / float(defender.land)
	var shield_active: bool = AbilitiesOps.is_crown_shield_active(defender, state.match_time) and not state.is_final_siege()
	var shield_r2: int = defender.crown_zone_radius() * defender.crown_zone_radius()
	var new_front: Dictionary = {}
	a.tiles_taken_last_ring = 0
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
		var cost: float = attack_tile_cost(sim, ni, d_ratio, a.attacker_id)
		if a.troops_remaining < cost:
			new_front[ni] = true
			continue
		a.troops_remaining -= cost
		a.tiles_taken_last_ring += 1
		defender.troops = maxf(0.0, defender.troops - Balance.DEFENDER_LOSS_PER_TILE * d_ratio)
		var pos: Vector2i = state.idx_to_xy(ni)
		var was_centre: bool = state.crown_centres.get(a.defender_id, -1) == ni
		TerritoryOps.claim_tile(sim, a.attacker_id, pos.x, pos.y)
		sim.mark_flash(ni)
		if was_centre:
			eliminate_player(sim, a.defender_id, a.attacker_id)
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


static func attack_tile_cost(sim: Simulation, tile_idx: int, d_ratio: float, attacker_id: int = 0) -> float:
	var state: GameState = sim.state
	var t: int = state.terrain[tile_idx]
	var terrain_def: float = 1.0
	if t >= 0 and t < Balance.TERRAIN_DEFENSE.size():
		terrain_def = Balance.TERRAIN_DEFENSE[t]
	var extra_def: float = combined_defense_at(state, tile_idx)
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
			var owner_id: int = state.owners[tile_idx]
			var rising: int = sim.rising_empire_id()
			if rising > 0 and owner_id == rising and attacker_id != rising:
				cost *= (1.0 - Balance.RISING_EMPIRE_ATTACK_DISCOUNT)
	return cost


# Non-terrain defense: Crown tile and zone, plus Fort and Wall.
# Crown tiles ignore the x4 building cap. Final Siege weakens Crown tiles
# and disables the zone bonus and Keep upgrades. A Crown that is moving has
# no special defense until it lands.
static func combined_defense_at(state: GameState, tile_idx: int) -> float:
	var owner_id: int = state.owners[tile_idx]
	if owner_id <= 0 or owner_id == GameState.RUINS_OWNER_ID:
		return 1.0
	var is_siege: bool = state.is_final_siege()
	var owner_player: Player = state.get_player(owner_id)
	var crown_active: bool = owner_player != null and owner_player.crown_move_until <= state.match_time
	# Crown tile: its own defense, ignores the x4 cap and other buildings.
	if crown_active and state.crown_tiles.has(tile_idx) and state.crown_tiles[tile_idx] == owner_id:
		if is_siege:
			return Balance.FINAL_SIEGE_CROWN_TILE_DEFENSE
		return owner_player.crown_tile_defense()
	var def: float = 1.0
	if crown_active and not is_siege and owner_player.crown_x >= 0:
		var pos: Vector2i = state.idx_to_xy(tile_idx)
		var dx: int = pos.x - owner_player.crown_x
		var dy: int = pos.y - owner_player.crown_y
		var r: int = owner_player.crown_zone_radius()
		if dx * dx + dy * dy <= r * r:
			def *= owner_player.crown_zone_defense()
	# Fort coverage: the best of this player's Forts whose radius covers the tile.
	if owner_player != null and owner_player.fort_tiles.size() > 0:
		def *= BuildingsOps.best_fort_defense_at(state, owner_player, tile_idx)
	# Wall tile?
	if state.wall_tiles.has(tile_idx) and state.wall_tiles[tile_idx] == owner_id:
		def *= Balance.WALL_DEFENSE
	return minf(def, Balance.BUILDING_DEFENSE_CAP)


# Sets crown_alert_until on any player whose Crown zone an enemy front touches.
# Runs in headless mode too, because bots react to it (Crown Shield).
static func check_crown_alerts(state: GameState) -> void:
	if state.attacks.is_empty():
		return
	for a: Attack in state.attacks:
		var defender: Player = state.get_player(a.defender_id)
		if defender == null or defender.crown_x < 0:
			continue
		if defender.crown_alert_until >= state.match_time + CROWN_ALERT_HOLD_SEC - Balance.TICK_DELTA * 0.5:
			continue
		var r: int = defender.crown_zone_radius()
		var r2: int = r * r
		for ni: int in a.front.keys():
			var pos: Vector2i = state.idx_to_xy(ni)
			var dx: int = pos.x - defender.crown_x
			var dy: int = pos.y - defender.crown_y
			if dx * dx + dy * dy <= r2:
				defender.crown_alert_until = state.match_time + CROWN_ALERT_HOLD_SEC
				defender.crown_alert_attacker = a.attacker_id
				break


# --- Elimination -------------------------------------------------------------

static func eliminate_player(sim: Simulation, victim_id: int, capturer_id: int) -> void:
	var state: GameState = sim.state
	var victim: Player = state.get_player(victim_id)
	if victim == null or not victim.is_alive:
		return
	victim.is_alive = false
	victim.eliminated_at = state.match_time
	var plunder_frac: float = Balance.FINAL_SIEGE_PLUNDER_FRACTION if state.is_final_siege() else Balance.CROWN_PLUNDER_FRACTION
	var plunder: float = victim.troops * plunder_frac
	victim.troops = 0.0
	victim.expansion_troops = 0.0
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
	for t_idx: int in state.crown_tiles.keys():
		if state.crown_tiles[t_idx] == victim_id:
			state.crown_tiles.erase(t_idx)
			state.dirty_tiles[t_idx] = true
	state.crown_centres.erase(victim_id)
	victim.border.clear()
	victim.land = 0
	victim.gem_tiles = 0
	victim.active_truces.clear()
	for other: Player in state.players:
		other.active_truces.erase(victim_id)
	BuildingsOps.remove_all_for(state, victim)
	end_attacks_touching(state, victim_id)
	TerritoryOps.rebuild_borders_for_all(state)
	var capturer_name: String = capturer.display_name if capturer != null else "An attacker"
	sim.announce("%s has taken %s's Crown!" % [capturer_name, victim.display_name], 5.0)
	state.events.append({
		"type": "crown_fall", "victim_id": victim_id, "capturer_id": capturer_id,
		"plunder": plunder, "x": victim.crown_x, "y": victim.crown_y,
	})


static func end_attacks_touching(state: GameState, player_id: int) -> void:
	var i: int = 0
	while i < state.attacks.size():
		var a: Attack = state.attacks[i]
		if a.attacker_id == player_id or a.defender_id == player_id:
			state.attacks.remove_at(i)
			continue
		i += 1
