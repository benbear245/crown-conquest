class_name AbilitiesOps
extends RefCounted

# All four abilities: validation, activation, per-tick effects. Called from
# Simulation (local player taps + Bot ability picks). Keeps simulation.gd lean.

# Ability ids match the HUD bar order.
const ID_SWIFT_MARCH: int = 0
const ID_CROWN_SHIELD: int = 1
const ID_RALLY: int = 2
const ID_BOMBARD: int = 3


# --- Lookups -----------------------------------------------------------------

static func is_swift_march_active(p: Player, now: float) -> bool:
	return p.swift_march_until > now


static func is_crown_shield_active(p: Player, now: float) -> bool:
	return p.crown_shield_until > now


static func is_rally_active(p: Player, now: float) -> bool:
	return p.rally_until > now


static func is_active(ability_id: int, p: Player, now: float) -> bool:
	match ability_id:
		ID_SWIFT_MARCH:
			return is_swift_march_active(p, now)
		ID_CROWN_SHIELD:
			return is_crown_shield_active(p, now)
		ID_RALLY:
			return is_rally_active(p, now)
		ID_BOMBARD:
			return p.bombard_until > now
	return false


static func active_until(ability_id: int, p: Player) -> float:
	match ability_id:
		ID_SWIFT_MARCH:
			return p.swift_march_until
		ID_CROWN_SHIELD:
			return p.crown_shield_until
		ID_RALLY:
			return p.rally_until
		ID_BOMBARD:
			return p.bombard_until
	return 0.0


static func duration_sec(ability_id: int) -> float:
	match ability_id:
		ID_SWIFT_MARCH:
			return Balance.SWIFT_MARCH_DURATION_SEC
		ID_CROWN_SHIELD:
			return Balance.CROWN_SHIELD_DURATION_SEC
		ID_RALLY:
			return Balance.RALLY_DURATION_SEC
		ID_BOMBARD:
			return Balance.BOMBARD_DURATION_SEC
	return 0.0


static func cooldown_sec(ability_id: int, p: Player) -> float:
	match ability_id:
		ID_SWIFT_MARCH:
			return Balance.SWIFT_MARCH_COOLDOWN_SEC
		ID_CROWN_SHIELD:
			return crown_shield_cooldown_sec(p)
		ID_RALLY:
			return Balance.RALLY_COOLDOWN_SEC
		ID_BOMBARD:
			return Balance.BOMBARD_COOLDOWN_SEC
	return 0.0


# Short cost text for the ability bar ("Free", "10%").
static func cost_label(ability_id: int) -> String:
	match ability_id:
		ID_RALLY:
			return "%d%% troops" % int(Balance.RALLY_COST_FRACTION * 100.0)
		ID_BOMBARD:
			return "%d%% troops" % int(Balance.BOMBARD_COST_FRACTION * 100.0)
	return "Free"


static func _count_use(p: Player, ability_id: int, sim: Simulation = null) -> void:
	p.abilities_used[ability_id] = int(p.abilities_used.get(ability_id, 0)) + 1
	if sim != null:
		sim.emit_event({"type": "ability", "player_id": p.id, "ability": ability_id})


static func crown_shield_cooldown_sec(p: Player) -> float:
	var cd: float = Balance.CROWN_SHIELD_COOLDOWN_SEC
	if p.keep_level >= 2:
		cd -= Balance.KEEP_2_CROWN_SHIELD_CD_REDUCTION_SEC
	return maxf(cd, 10.0)


static func unlock_sec(ability_id: int) -> float:
	match ability_id:
		ID_RALLY:
			return Balance.RALLY_UNLOCK_SEC
		ID_BOMBARD:
			return Balance.BOMBARD_UNLOCK_SEC
		_:
			return 0.0


static func cost_now(ability_id: int, p: Player) -> float:
	match ability_id:
		ID_RALLY:
			return floorf(p.troops * Balance.RALLY_COST_FRACTION)
		ID_BOMBARD:
			return floorf(p.troops * Balance.BOMBARD_COST_FRACTION)
		_:
			return 0.0


static func cooldown_until(ability_id: int, p: Player) -> float:
	match ability_id:
		ID_SWIFT_MARCH:
			return p.swift_march_cd_until
		ID_CROWN_SHIELD:
			return p.crown_shield_cd_until
		ID_RALLY:
			return p.rally_cd_until
		ID_BOMBARD:
			return p.bombard_cd_until
		_:
			return 0.0


# --- Activation --------------------------------------------------------------

static func activate_swift_march(sim: Simulation, p: Player) -> bool:
	var now: float = sim.state.match_time
	if p.swift_march_cd_until > now:
		return false
	p.swift_march_until = now + Balance.SWIFT_MARCH_DURATION_SEC
	p.swift_march_cd_until = now + Balance.SWIFT_MARCH_COOLDOWN_SEC
	_count_use(p, ID_SWIFT_MARCH, sim)
	return true


static func activate_crown_shield(sim: Simulation, p: Player) -> bool:
	if sim.state.is_final_siege():
		return false
	var now: float = sim.state.match_time
	if p.crown_shield_cd_until > now:
		return false
	p.crown_shield_until = now + Balance.CROWN_SHIELD_DURATION_SEC
	p.crown_shield_cd_until = now + crown_shield_cooldown_sec(p)
	_count_use(p, ID_CROWN_SHIELD, sim)
	return true


static func activate_rally(sim: Simulation, p: Player) -> bool:
	var now: float = sim.state.match_time
	if now < Balance.RALLY_UNLOCK_SEC:
		return false
	if p.rally_cd_until > now:
		return false
	var c: float = floorf(p.troops * Balance.RALLY_COST_FRACTION)
	if p.troops < c:
		return false
	p.troops -= c
	p.rally_until = now + Balance.RALLY_DURATION_SEC
	p.rally_cd_until = now + Balance.RALLY_COOLDOWN_SEC
	_count_use(p, ID_RALLY, sim)
	return true


static func activate_bombard(sim: Simulation, p: Player, target_x: int, target_y: int) -> bool:
	var state: GameState = sim.state
	var now: float = state.match_time
	if now < Balance.BOMBARD_UNLOCK_SEC:
		return false
	if p.bombard_cd_until > now:
		return false
	if not state.in_bounds(target_x, target_y):
		return false
	# Never on a truce partner's land (that would be an attack).
	var target_owner: int = state.owners[state.idx(target_x, target_y)]
	if target_owner > 0 and TrucesOps.has_truce(p, target_owner, now):
		return false
	# Target must be within BOMBARD_RANGE_TILES of any of the player's border tiles.
	if not bombard_in_range(sim, p, target_x, target_y):
		return false
	var c: float = floorf(p.troops * Balance.BOMBARD_COST_FRACTION)
	if p.troops < c:
		return false
	p.troops -= c
	p.bombard_cd_until = now + Balance.BOMBARD_COOLDOWN_SEC
	p.bombard_until = now + Balance.BOMBARD_DURATION_SEC
	_count_use(p, ID_BOMBARD, sim)
	state.bombards.append({
		"owner_id": p.id,
		"target_x": target_x,
		"target_y": target_y,
		"until": now + Balance.BOMBARD_DURATION_SEC,
		"last_damage_at": now,
	})
	# Mark area dirty so Map re-paints cracked overlay on next render.
	var r: int = Balance.BOMBARD_AREA_RADIUS_TILES
	var r2: int = r * r
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r2:
				continue
			var nx: int = target_x + dx
			var ny: int = target_y + dy
			if state.in_bounds(nx, ny):
				state.dirty_tiles[state.idx(nx, ny)] = true
	return true


static func bombard_in_range(sim: Simulation, p: Player, target_x: int, target_y: int) -> bool:
	var r2: int = Balance.BOMBARD_RANGE_TILES * Balance.BOMBARD_RANGE_TILES
	var state: GameState = sim.state
	for i_v in p.border.keys():
		var i: int = i_v
		var pos: Vector2i = state.idx_to_xy(i)
		var dx: int = pos.x - target_x
		var dy: int = pos.y - target_y
		if dx * dx + dy * dy <= r2:
			return true
	return false


# Enemy tiles a Bombard at (x, y) would hit (for the targeting preview).
static func bombard_enemy_tiles(state: GameState, owner_id: int, x: int, y: int) -> int:
	var r: int = Balance.BOMBARD_AREA_RADIUS_TILES
	var n: int = 0
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r or not state.in_bounds(x + dx, y + dy):
				continue
			var ow: int = state.owners[state.idx(x + dx, y + dy)]
			if ow > 0 and ow != owner_id and ow != GameState.RUINS_OWNER_ID:
				n += 1
	return n


# --- Per-tick effects --------------------------------------------------------

static func tick(sim: Simulation) -> void:
	var state: GameState = sim.state
	# Clear active flags whose timer expired isn't needed; _until comparisons
	# just stop reporting active. But damage ticks for live bombards:
	var now: float = state.match_time
	var i := 0
	while i < state.bombards.size():
		var b: Dictionary = state.bombards[i]
		if now >= float(b["until"]):
			# Mark area dirty so the cracked overlay clears.
			var tx: int = int(b["target_x"])
			var ty: int = int(b["target_y"])
			var ra: int = Balance.BOMBARD_AREA_RADIUS_TILES
			var ra2: int = ra * ra
			for dy_e in range(-ra, ra + 1):
				for dx_e in range(-ra, ra + 1):
					if dx_e * dx_e + dy_e * dy_e > ra2:
						continue
					var nx_e: int = tx + dx_e
					var ny_e: int = ty + dy_e
					if state.in_bounds(nx_e, ny_e):
						state.dirty_tiles[state.idx(nx_e, ny_e)] = true
			state.bombards.remove_at(i)
			continue
		# Damage over time: 2 troops per tile hit, per second.
		var elapsed: float = now - float(b.get("last_damage_at", now))
		if elapsed > 0.0:
			b["last_damage_at"] = now
			var tx: int = int(b["target_x"])
			var ty: int = int(b["target_y"])
			var r: int = Balance.BOMBARD_AREA_RADIUS_TILES
			var r2: int = r * r
			var dmg_per_tile: float = Balance.BOMBARD_DAMAGE_PER_TILE_PER_SEC * elapsed
			var owner_damage: Dictionary = {}      # owner_id -> total damage
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx * dx + dy * dy > r2:
						continue
					var nx: int = tx + dx
					var ny: int = ty + dy
					if not state.in_bounds(nx, ny):
						continue
					var ni: int = state.idx(nx, ny)
					var ow: int = state.owners[ni]
					if ow <= 0 or ow == GameState.RUINS_OWNER_ID:
						continue
					if ow == int(b["owner_id"]):
						continue
					var bomber: Player = state.get_player(int(b["owner_id"]))
					if bomber != null and TrucesOps.has_truce(bomber, ow, now):
						continue
					owner_damage[ow] = float(owner_damage.get(ow, 0.0)) + dmg_per_tile
			for ow_v in owner_damage.keys():
				var ow: int = ow_v
				var vp: Player = state.get_player(ow)
				if vp != null:
					vp.troops = maxf(0.0, vp.troops - owner_damage[ow])
		i += 1


# Checks whether a tile sits inside any active Bombard area; used to halve
# the defender's defense in `combined_defense_at`.
static func tile_in_any_bombard(state: GameState, tile_idx: int) -> bool:
	if state.bombards.is_empty():
		return false
	var pos: Vector2i = state.idx_to_xy(tile_idx)
	var r2: int = Balance.BOMBARD_AREA_RADIUS_TILES * Balance.BOMBARD_AREA_RADIUS_TILES
	for b_v in state.bombards:
		var b: Dictionary = b_v
		if state.match_time >= float(b["until"]):
			continue
		var dx: int = pos.x - int(b["target_x"])
		var dy: int = pos.y - int(b["target_y"])
		if dx * dx + dy * dy <= r2:
			return true
	return false
