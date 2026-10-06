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
	if p.ally_id == target_owner:
		return false   # Teams: allies can't attack each other
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
	# Inline index maths (a Large empire's border is 1,000+ tiles and bots
	# start attacks often). Neighbour order: right, left, down, up, the same
	# as NEIGHBOR_OFFSETS, so the front's order is unchanged.
	var owners: PackedByteArray = state.owners
	var blocked: PackedByteArray = state.blocked
	var w: int = state.width
	var h: int = state.height
	for i: int in attacker.border.keys():
		var x: int = i % w
		@warning_ignore("integer_division")
		var y: int = i / w
		if x + 1 < w and owners[i + 1] == defender_id and blocked[i + 1] == 0:
			out[i + 1] = true
		if x > 0 and owners[i - 1] == defender_id and blocked[i - 1] == 0:
			out[i - 1] = true
		if y + 1 < h and owners[i + w] == defender_id and blocked[i + w] == 0:
			out[i + w] = true
		if y > 0 and owners[i - w] == defender_id and blocked[i - w] == 0:
			out[i - w] = true
	return out


# --- Per-tick ----------------------------------------------------------------

static func tick_attacks(sim: Simulation) -> void:
	var state: GameState = sim.state
	var budget: int = attack_tile_budget(state)
	var i: int = 0
	while i < state.attacks.size():
		var a: Attack = state.attacks[i]
		if a.troops_remaining <= 0.0:
			state.attacks.remove_at(i)
			continue
		a.advance_timer -= Balance.TICK_DELTA
		if not a.ring_active:
			if a.advance_timer > 0.0:
				i += 1
				continue
			a.advance_timer += Balance.ATTACK_RING_INTERVAL_SEC
			start_ring(a)
		if budget <= 0:
			i += 1   # out of budget this tick: this ring carries on next tick
			continue
		var before: int = a.ring_pos
		var finished: bool = advance_ring(sim, a, mini(a.ring_chunk, budget))
		budget -= a.ring_pos - before
		# The ring may have removed this attack (defender eliminated).
		if i >= state.attacks.size() or state.attacks[i] != a:
			continue
		if a.troops_remaining <= 0.0:
			state.attacks.remove_at(i)
			continue
		if not finished:
			i += 1
			continue
		if a.front.is_empty():
			state.attacks.remove_at(i)
			continue
		# Stalled: took nothing and can't pay for any tile on the front (and
		# it isn't just waiting out a Crown Shield). It ends like a retreat.
		if a.tiles_taken_last_ring == 0 and not a.shield_blocked and a.troops_remaining < a.cheapest_blocked_cost:
			var attacker: Player = state.get_player(a.attacker_id)
			if attacker != null:
				attacker.troops += a.troops_remaining * Balance.RETREAT_RETURN_FRACTION
			state.attacks.remove_at(i)
			continue
		i += 1


# Attack tiles all attacks may take this tick: the Medium-map budget, scaled
# down for bigger maps (more players, more work each tick).
static func attack_tile_budget(state: GameState) -> int:
	var medium: float = float(Balance.MAP_MEDIUM_WIDTH * Balance.MAP_MEDIUM_HEIGHT)
	var k: float = minf(1.0, medium / float(maxi(state.tile_count(), 1)))
	return maxi(50, roundi(Balance.ATTACK_TILES_PER_TICK_BUDGET * k))


# Ticks a ring is spread over (4 at 0.4 s per ring and 10 ticks per second).
static func ring_ticks() -> int:
	return maxi(1, roundi(Balance.ATTACK_RING_INTERVAL_SEC / Balance.TICK_DELTA))


# Starts eating the current front: the ring's tiles are worked through over
# the next ring_ticks() ticks, a share per tick.
static func start_ring(a: Attack) -> void:
	a.ring_active = true
	a.ring_queue = a.front.keys()
	a.ring_pos = 0
	a.ring_chunk = mini(ceili(float(a.ring_queue.size()) / float(ring_ticks())), Balance.ATTACK_RING_MAX_TILES_PER_TICK)
	a.ring_new_front = {}
	a.tiles_taken_last_ring = 0
	a.cheapest_blocked_cost = INF
	a.shield_blocked = false


# A whole ring at once (tests and tools; the game spreads it over ticks).
static func advance_attack(sim: Simulation, a: Attack) -> void:
	start_ring(a)
	advance_ring(sim, a, a.ring_queue.size())


# Works through up to `max_tiles` tiles of the current ring; returns true when
# the ring is done (then `front` becomes the new front). The per-tile price is
# the same maths as attack_tile_cost() + combined_defense_at(), with
# everything that is constant for this batch worked out once up front (this
# loop is the simulator's hot path).
static func advance_ring(sim: Simulation, a: Attack, max_tiles: int) -> bool:
	var state: GameState = sim.state
	var defender: Player = state.get_player(a.defender_id)
	if defender == null or not defender.is_alive or defender.land <= 0:
		a.troops_remaining = 0.0
		a.ring_active = false
		return true
	var attacker: Player = state.get_player(a.attacker_id)
	var now: float = state.match_time
	var w: int = state.width
	var h: int = state.height
	var owners: PackedByteArray = state.owners
	var d_ratio: float = defender.troops / float(defender.land)
	var is_siege: bool = state.is_final_siege()
	var shield_active: bool = AbilitiesOps.is_crown_shield_active(defender, now) and not is_siege
	var zone_r: int = defender.crown_zone_radius()
	var zone_r2: int = zone_r * zone_r
	var cx: int = defender.crown_x
	var cy: int = defender.crown_y
	var centre_idx: int = state.crown_centres.get(a.defender_id, -1)
	# Defense context (see combined_defense_at).
	var crown_active: bool = defender.crown_move_until <= now
	var crown_tile_def: float = Balance.FINAL_SIEGE_CROWN_TILE_DEFENSE if is_siege else defender.crown_tile_defense()
	var zone_on: bool = crown_active and not is_siege and cx >= 0
	var zone_def: float = defender.crown_zone_defense()
	var forts: PackedInt32Array = _fort_cache(state, defender)
	var has_walls: bool = defender.wall_count > 0
	var any_bombard: bool = not state.bombards.is_empty()
	var terrain_defense: PackedFloat32Array = Balance.TERRAIN_DEFENSE
	# Attacker multipliers (see attack_tile_cost).
	var rally_on: bool = attacker != null and AbilitiesOps.is_rally_active(attacker, now)
	var oath_on: bool = attacker != null and TrucesOps.is_oathbreaker(attacker, now)
	var rising: int = sim.rising_empire_id()
	var rising_on: bool = attacker != null and rising > 0 and a.defender_id == rising and a.attacker_id != rising
	var new_front: Dictionary = a.ring_new_front
	var queue: Array = a.ring_queue
	var end: int = mini(queue.size(), a.ring_pos + maxi(max_tiles, 1))
	while a.ring_pos < end:
		var ni: int = queue[a.ring_pos]
		a.ring_pos += 1
		if owners[ni] != a.defender_id:
			continue
		if state.blocked[ni] == 1:
			continue
		var x: int = ni % w
		@warning_ignore("integer_division")
		var y: int = ni / w
		var dxz: int = x - cx
		var dyz: int = y - cy
		var in_zone: bool = dxz * dxz + dyz * dyz <= zone_r2
		# Crown Shield: can't take tiles inside the defender's Crown zone.
		if shield_active and cx >= 0 and in_zone:
			new_front[ni] = true
			a.shield_blocked = true
			continue
		# --- tile cost ---
		var extra_def: float
		# (Crown tiles always sit inside the Crown zone, so skip the lookup outside it.)
		if crown_active and in_zone and state.crown_tiles.has(ni) and state.crown_tiles[ni] == a.defender_id:
			extra_def = crown_tile_def
		else:
			var def: float = 1.0
			if zone_on and in_zone:
				def *= zone_def
			if not forts.is_empty():
				def *= _best_fort(forts, x, y)
			if has_walls and state.wall_tiles.has(ni) and state.wall_tiles[ni] == a.defender_id:
				def *= Balance.WALL_DEFENSE
			extra_def = minf(def, Balance.BUILDING_DEFENSE_CAP)
		if any_bombard and AbilitiesOps.tile_in_any_bombard(state, ni):
			extra_def *= Balance.BOMBARD_DEFENSE_MULT
		var cost: float = Balance.ATTACK_TILE_COST_BASE + Balance.ATTACK_TILE_COST_SCALE * d_ratio * terrain_defense[state.terrain[ni]] * extra_def
		if rally_on:
			cost *= (1.0 - Balance.RALLY_ATTACK_DISCOUNT)
		if oath_on:
			cost *= (1.0 + Balance.OATHBREAKER_ATTACK_PENALTY)
		if rising_on:
			cost *= (1.0 - Balance.RISING_EMPIRE_ATTACK_DISCOUNT)
		if a.troops_remaining < cost:
			new_front[ni] = true
			if cost < a.cheapest_blocked_cost:
				a.cheapest_blocked_cost = cost
			continue
		# --- capture ---
		a.troops_remaining -= cost
		a.tiles_taken_last_ring += 1
		defender.troops = maxf(0.0, defender.troops - Balance.DEFENDER_LOSS_PER_TILE * d_ratio)
		var had_fort: bool = not forts.is_empty() and state.building_at_tile.has(ni)
		TerritoryOps.claim_tile(sim, a.attacker_id, x, y)
		if had_fort:
			forts = _fort_cache(state, defender)   # a Fort fell: its cover is gone
		if not sim.headless:
			sim.mark_flash(ni)
		if ni == centre_idx:
			a.ring_active = false
			eliminate_player(sim, a.defender_id, a.attacker_id)
			# Defender is gone; this attack was removed by end_attacks_touching.
			return true
		# Defender tiles next to the captured one join the front (right, left, down, up).
		if x + 1 < w and owners[ni + 1] == a.defender_id:
			new_front[ni + 1] = true
		if x > 0 and owners[ni - 1] == a.defender_id:
			new_front[ni - 1] = true
		if y + 1 < h and owners[ni + w] == a.defender_id:
			new_front[ni + w] = true
		if y > 0 and owners[ni - w] == a.defender_id:
			new_front[ni - w] = true
	if a.ring_pos < queue.size():
		return false
	a.ring_active = false
	a.ring_queue = []
	a.ring_new_front = {}
	a.front = new_front
	a.zone_cache_valid = false
	if a.tiles_taken_last_ring > 0:
		sim.emit_event({"type": "attack_ring", "attacker_id": a.attacker_id, "defender_id": a.defender_id, "tiles": a.tiles_taken_last_ring})
	a.stalled_rings = 0 if a.tiles_taken_last_ring > 0 else a.stalled_rings + 1
	return true


# The defender's Forts packed flat: x, y, r^2 and the defense multiplier x 1000
# per Fort (a packed array is much faster to walk than an array of arrays).
static func _fort_cache(state: GameState, owner: Player) -> PackedInt32Array:
	var out := PackedInt32Array()
	for ft_idx: int in owner.fort_tiles:
		var b: Building = state.building_at_tile.get(ft_idx, null)
		if b == null or b.owner_id != owner.id:
			continue
		var r: int = b.radius()
		out.append(b.x)
		out.append(b.y)
		out.append(r * r)
		out.append(roundi(b.defense_mult() * 1000.0))
	return out


static func _best_fort(forts: PackedInt32Array, x: int, y: int) -> float:
	var best: int = 1000
	var k: int = 0
	var n: int = forts.size()
	while k < n:
		var fdx: int = x - forts[k]
		var fdy: int = y - forts[k + 1]
		if fdx * fdx + fdy * fdy <= forts[k + 2] and forts[k + 3] > best:
			best = forts[k + 3]
		k += 4
	return best / 1000.0


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
# Crown tiles ignore the building cap. Final Siege weakens Crown tiles
# and disables the zone bonus and Keep upgrades. A Crown that is moving has
# no special defense until it lands.
static func combined_defense_at(state: GameState, tile_idx: int) -> float:
	var owner_id: int = state.owners[tile_idx]
	if owner_id <= 0 or owner_id == GameState.RUINS_OWNER_ID:
		return 1.0
	var is_siege: bool = state.is_final_siege()
	var owner_player: Player = state.get_player(owner_id)
	var crown_active: bool = owner_player != null and owner_player.crown_move_until <= state.match_time
	# Crown tile: its own defense, ignores the building cap and other buildings.
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
	var w: int = state.width
	for a: Attack in state.attacks:
		var defender: Player = state.get_player(a.defender_id)
		if defender == null or defender.crown_x < 0:
			continue
		if defender.crown_alert_until >= state.match_time + CROWN_ALERT_HOLD_SEC - Balance.TICK_DELTA * 0.5:
			continue
		# Whether the front touches the zone only changes when the front or the
		# Crown (position, Keep radius) changes, so it's cached on the attack.
		var r: int = defender.crown_zone_radius()
		var key := Vector3i(defender.crown_x, defender.crown_y, r)
		if not a.zone_cache_valid or a.zone_cache_key != key:
			a.zone_cache_key = key
			a.zone_cache_valid = true
			a.zone_touch = false
			var r2: int = r * r
			for ni: int in a.front.keys():
				var dx: int = ni % w - defender.crown_x
				@warning_ignore("integer_division")
				var dy: int = ni / w - defender.crown_y
				if dx * dx + dy * dy <= r2:
					a.zone_touch = true
					break
		if a.zone_touch:
			defender.crown_alert_until = state.match_time + CROWN_ALERT_HOLD_SEC
			defender.crown_alert_attacker = a.attacker_id


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
		if victim.crown_x >= 0:
			sim.add_popup(state.idx(victim.crown_x, victim.crown_y), "+%s plunder" % GameState.format_int(int(plunder)), capturer_id)
	# Victim's territory becomes Ruins. find() is native code and jumps
	# straight to the victim's tiles (a GDScript loop over a Large map took
	# several ms); the Map repaints it all over the next frames.
	var i: int = state.owners.find(victim_id)
	while i != -1:
		state.owners[i] = GameState.RUINS_OWNER_ID
		i = state.owners.find(victim_id, i + 1)
	state.repaint_all = state.track_dirty
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
	# Other players' borders don't change: the victim's land was already "not
	# theirs" and Ruins still are, so no full-map border rebuild is needed.
	var capturer_name: String = capturer.display_name if capturer != null else "An attacker"
	sim.announce("%s has taken %s's Crown!" % [capturer_name, victim.display_name], 5.0)
	sim.emit_event({
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
