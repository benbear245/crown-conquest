class_name MatchOps
extends RefCounted

# Match flow: Crown placement, moving a Crown, elimination and the win
# conditions. Pure sim, called by Simulation.

const CROWN_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1,  0), Vector2i(0,  0), Vector2i(1,  0),
	Vector2i(-1,  1), Vector2i(0,  1), Vector2i(1,  1),
]


# --- Placement ---------------------------------------------------------------

static func tick_placement(sim: Simulation) -> void:
	var state: GameState = sim.state
	state.placement_time_left -= Balance.TICK_DELTA
	# Bots place as soon as they get a chance (first tick that reaches them).
	for p in state.players:
		if p.is_bot and p.crown_x < 0:
			var pos := find_valid_crown_position(state)
			if pos.x >= 0:
				place_crown(sim, p, pos.x, pos.y)
	if state.placement_time_left > 0.0:
		return
	for p in state.players:
		if p.crown_x < 0:
			var pos := find_valid_crown_position(state)
			place_crown(sim, p, pos.x, pos.y)
	ShrinesOps.place_shrines(sim)
	state.phase = Balance.PHASE_MATCH
	sim.emit({"type": "match_started"})


static func place_crown(sim: Simulation, player: Player, cx: int, cy: int) -> void:
	var state: GameState = sim.state
	player.crown_x = cx
	player.crown_y = cy
	player.troops = Balance.STARTING_TROOPS
	_stamp_crown(state, player.id, cx, cy)
	# Claim the starting radius-4 circle (which includes the 3x3).
	TerritoryOps.claim_circle(sim, player, cx, cy, Balance.STARTING_LAND_RADIUS)


static func _stamp_crown(state: GameState, player_id: int, cx: int, cy: int) -> void:
	for off in CROWN_OFFSETS:
		var tx: int = cx + off.x
		var ty: int = cy + off.y
		if not state.in_bounds(tx, ty):
			continue
		var ti := state.idx(tx, ty)
		state.crown_tiles[ti] = player_id
		state.dirty_tiles[ti] = true
	state.crown_centres[player_id] = state.idx(cx, cy)


# Rebuilds every Crown's 3x3 from the players' Crown positions (online
# clients, whose Crown data arrives as positions).
static func restamp_all_crowns(state: GameState) -> void:
	for t_idx: int in state.crown_tiles.keys():
		state.dirty_tiles[t_idx] = true
	state.crown_tiles.clear()
	state.crown_centres.clear()
	for p: Player in state.players:
		if p.is_alive and p.crown_x >= 0:
			_stamp_crown(state, p.id, p.crown_x, p.crown_y)


static func _clear_crown(state: GameState, player_id: int) -> void:
	for t_idx: int in state.crown_tiles.keys():
		if state.crown_tiles[t_idx] == player_id:
			state.crown_tiles.erase(t_idx)
			state.dirty_tiles[t_idx] = true
	state.crown_centres.erase(player_id)


static func is_valid_crown_tile(state: GameState, x: int, y: int, min_dist_from_other: int) -> bool:
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
		if state.is_blocked_terrain(state.terrain[state.idx(tx, ty)]):
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


static func find_valid_crown_position(state: GameState) -> Vector2i:
	var min_x: int = Balance.CROWN_MIN_DIST_FROM_EDGE
	var min_y: int = Balance.CROWN_MIN_DIST_FROM_EDGE
	var max_x: int = state.width - Balance.CROWN_MIN_DIST_FROM_EDGE
	var max_y: int = state.height - Balance.CROWN_MIN_DIST_FROM_EDGE
	@warning_ignore("integer_division")
	var relaxed: int = Balance.CROWN_MIN_DIST_FROM_OTHER / 2
	# Try full spacing first, then relax the inter-Crown distance.
	for spacing: int in [Balance.CROWN_MIN_DIST_FROM_OTHER, relaxed]:
		for _attempt in range(800):
			var x: int = state.rng.randi_range(min_x, max_x - 1)
			var y: int = state.rng.randi_range(min_y, max_y - 1)
			if is_valid_crown_tile(state, x, y, spacing):
				return Vector2i(x, y)
	return Vector2i(-1, -1)


# --- Moving the Crown --------------------------------------------------------

# Why a Crown move to (x, y) isn't allowed right now, or "" if it is.
static func crown_move_blocker(sim: Simulation, p: Player, x: int, y: int) -> String:
	var state: GameState = sim.state
	if p.crown_moved:
		return "Already moved this match"
	if state.match_time < Balance.CROWN_MOVE_UNLOCK_SEC:
		return "Unlocks at %s" % GameState.format_time(Balance.CROWN_MOVE_UNLOCK_SEC)
	if p.crown_x < 0:
		return "No Crown"
	if not state.in_bounds(x, y):
		return "Off the map"
	for off in CROWN_OFFSETS:
		var tx: int = x + off.x
		var ty: int = y + off.y
		if not state.in_bounds(tx, ty):
			return "Too close to the edge"
		var ti: int = state.idx(tx, ty)
		if state.owners[ti] != p.id or state.is_blocked_terrain(state.terrain[ti]):
			return "All 9 tiles must be your land"
		if state.building_at_tile.has(ti) or state.shrine_at_tile.has(ti):
			return "Tiles must be clear of buildings"
	if absi(x - p.crown_x) <= 2 and absi(y - p.crown_y) <= 2:
		return "Too close to your current Crown"
	var r: int = Balance.CROWN_MOVE_MIN_DIST_FROM_ENEMY
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var nx: int = x + dx
			var ny: int = y + dy
			if not state.in_bounds(nx, ny):
				continue
			var ow: int = state.owners[state.idx(nx, ny)]
			if state.is_player_owner(ow) and ow != p.id:
				return "Must be %d+ tiles from enemy land" % r
	return ""


static func start_crown_move(sim: Simulation, p: Player, x: int, y: int) -> bool:
	if crown_move_blocker(sim, p, x, y) != "":
		return false
	var cost: float = floorf(p.troops * Balance.CROWN_MOVE_COST_FRACTION)
	p.troops -= cost
	p.crown_moved = true
	p.crown_move_to = Vector2i(x, y)
	p.crown_move_until = sim.state.match_time + Balance.CROWN_MOVE_DURATION_SEC
	sim.announce("%s is moving their Crown!" % p.display_name)
	return true


# Finishes Crown moves whose 5 seconds are up. If the new spot was lost in
# the meantime the move fails and the Crown stays where it was.
static func tick_crown_moves(sim: Simulation) -> void:
	var state: GameState = sim.state
	for p: Player in state.players:
		if p.crown_move_to.x < 0 or not p.is_alive:
			continue
		if p.crown_move_until > state.match_time:
			continue
		var to: Vector2i = p.crown_move_to
		p.crown_move_to = Vector2i(-1, -1)
		var all_ours: bool = true
		for off in CROWN_OFFSETS:
			if state.owners[state.idx(to.x + off.x, to.y + off.y)] != p.id:
				all_ours = false
				break
		if not all_ours:
			sim.announce("%s's Crown move failed." % p.display_name, [p.id])
			continue
		_clear_crown(state, p.id)
		p.crown_x = to.x
		p.crown_y = to.y
		_stamp_crown(state, p.id, to.x, to.y)
		sim.emit({"type": "crown_moved", "player_id": p.id, "x": to.x, "y": to.y})
		sim.announce("%s's Crown has a new home." % p.display_name, [p.id])


# --- Elimination and winning --------------------------------------------------

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
	var centre: Vector2i = Vector2i(victim.crown_x, victim.crown_y)
	# Victim's territory becomes Ruins.
	for i in range(state.owners.size()):
		if state.owners[i] == victim_id:
			state.owners[i] = GameState.RUINS_OWNER_ID
			state.dirty_tiles[i] = true
	_clear_crown(state, victim_id)
	victim.crown_move_to = Vector2i(-1, -1)
	victim.border.clear()
	victim.land = 0
	victim.gem_tiles = 0
	BuildingsOps.remove_all_for(state, victim)
	var bo_idx := 0
	while bo_idx < state.boats.size():
		var bo: Boat = state.boats[bo_idx]
		if bo.owner_id == victim_id:
			state.boats.remove_at(bo_idx)
			continue
		bo_idx += 1
	CombatOps.end_attacks_touching(state, victim_id)
	TerritoryOps.rebuild_borders_for_all(state)
	ShrinesOps.refresh_all(sim)
	var capturer_name: String = capturer.display_name if capturer != null else "An attacker"
	sim.emit({
		"type": "crown_fell", "victim_id": victim_id, "capturer_id": capturer_id,
		"x": centre.x, "y": centre.y, "plunder": int(plunder),
	})
	sim.announce("%s has taken %s's Crown!" % [capturer_name, victim.display_name])


static func check_win_conditions(sim: Simulation) -> void:
	var state: GameState = sim.state
	var alive: Array[Player] = []
	for p: Player in state.players:
		if p.is_alive:
			alive.append(p)
	if alive.size() <= 1:
		if alive.size() == 1:
			end_match(sim, alive[0].id, "Last Crown standing")
		else:
			end_match(sim, 0, "Draw")
		return
	for p: Player in alive:
		if state.land_fraction(p) >= Balance.DOMINION_WIN_FRACTION:
			end_match(sim, p.id, "Dominion win (60%+ of the usable map)")
			return
	if state.match_time >= Balance.MATCH_TIME_LIMIT_SEC:
		var leader: Player = alive[0]
		for p: Player in alive:
			if p.land > leader.land:
				leader = p
		end_match(sim, leader.id, "Most land at the 15:00 limit")


static func end_match(sim: Simulation, winner_id: int, reason: String) -> void:
	var state: GameState = sim.state
	state.phase = Balance.PHASE_ENDED
	state.winner_id = winner_id
	state.win_reason = reason
	state.attacks.clear()
	sim.emit({"type": "match_ended", "winner_id": winner_id})
	var w: Player = state.get_player(winner_id)
	if w != null:
		sim.announce("%s wins! %s" % [w.display_name, reason])
	else:
		sim.announce("Match ends: %s" % reason)
