class_name ShrinesOps
extends RefCounted

# Shrines: contested objectives placed between the Crowns when the match
# starts. Holding a Shrine's centre tile grants its blessing:
#   Plenty: +troop growth.  War: cheaper attacks.  Sight: see rivals' troops.

const SANCTUM_OFFSETS: Array[Vector2i] = MatchOps.CROWN_OFFSETS
const EDGE_MARGIN: int = 4
const SAMPLES_PER_SHRINE: int = 500
# Prefer spots no further than this from the nearest Crown, so Shrines sit in
# the fought-over middle rather than in empty corners.
const PREFERRED_MAX_CROWN_DIST: float = 35.0


static func kinds_for_size(size_preset: int) -> PackedInt32Array:
	match size_preset:
		Balance.MAP_SIZE_SMALL:
			return Balance.SHRINE_KINDS_SMALL
		Balance.MAP_SIZE_LARGE:
			return Balance.SHRINE_KINDS_LARGE
		_:
			return Balance.SHRINE_KINDS_MEDIUM


static func place_shrines(sim: Simulation) -> void:
	var state: GameState = sim.state
	for kind: int in kinds_for_size(sim.size_preset):
		var spot := _pick_spot(state, Balance.SHRINE_MIN_DIST_FROM_CROWN, Balance.SHRINE_MIN_DIST_BETWEEN)
		if spot.x < 0:
			# Crowded map: relax the spacing rather than skip the Shrine.
			@warning_ignore("integer_division")
			spot = _pick_spot(state, Balance.SHRINE_MIN_DIST_FROM_CROWN / 2, Balance.SHRINE_MIN_DIST_BETWEEN / 2)
		if spot.x < 0:
			continue
		var s := Shrine.new()
		s.kind = kind
		s.x = spot.x
		s.y = spot.y
		s.tile_idx = state.idx(spot.x, spot.y)
		state.shrines.append(s)
		for off in SANCTUM_OFFSETS:
			var ti: int = state.idx(spot.x + off.x, spot.y + off.y)
			state.shrine_at_tile[ti] = s
			state.dirty_tiles[ti] = true
	refresh_all(sim)


static func _pick_spot(state: GameState, min_crown: int, min_between: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score: float = -INF
	for _i in range(SAMPLES_PER_SHRINE):
		var x: int = state.rng.randi_range(EDGE_MARGIN, state.width - EDGE_MARGIN - 1)
		var y: int = state.rng.randi_range(EDGE_MARGIN, state.height - EDGE_MARGIN - 1)
		if not _sanctum_ok(state, x, y):
			continue
		var d1: float = INF          # nearest Crown
		var d2: float = INF          # second-nearest Crown
		for p: Player in state.players:
			if p.crown_x < 0:
				continue
			var d: float = Vector2(x - p.crown_x, y - p.crown_y).length()
			if d < d1:
				d2 = d1
				d1 = d
			elif d < d2:
				d2 = d
		if d1 < float(min_crown):
			continue
		var too_close: bool = false
		for other: Shrine in state.shrines:
			if Vector2(x - other.x, y - other.y).length() < float(min_between):
				too_close = true
				break
		if too_close:
			continue
		# Best spots are about equally far from the two nearest Crowns.
		var score: float = -absf(d2 - d1) - 0.5 * maxf(0.0, d1 - PREFERRED_MAX_CROWN_DIST)
		if score > best_score:
			best_score = score
			best = Vector2i(x, y)
	return best


static func _sanctum_ok(state: GameState, x: int, y: int) -> bool:
	for off in SANCTUM_OFFSETS:
		var ti: int = state.idx(x + off.x, y + off.y)
		if state.is_blocked_terrain(state.terrain[ti]):
			return false
		if state.owners[ti] != 0 or state.crown_tiles.has(ti) or state.shrine_at_tile.has(ti):
			return false
	return true


# Called by TerritoryOps.claim_tile when a sanctum tile changes hands.
static func on_tile_changed(sim: Simulation, tile_idx: int) -> void:
	var s: Shrine = sim.state.shrine_at_tile[tile_idx]
	if s.tile_idx != tile_idx:
		return
	_update_holder(sim, s, true)


static func refresh_all(sim: Simulation) -> void:
	for s: Shrine in sim.state.shrines:
		_update_holder(sim, s, false)


static func _update_holder(sim: Simulation, s: Shrine, announce: bool) -> void:
	var ow: int = sim.state.owners[s.tile_idx]
	var holder: int = ow if sim.state.is_player_owner(ow) else 0
	if holder == s.holder_id:
		return
	s.holder_id = holder
	if holder > 0:
		sim.state.usage["Shrine taken"] = int(sim.state.usage.get("Shrine taken", 0)) + 1
	if not announce or holder == 0:
		return
	var p: Player = sim.state.get_player(holder)
	if p == null:
		return
	sim.emit({"type": "shrine_taken", "player_id": holder, "kind": s.kind, "x": s.x, "y": s.y})
	sim.announce("%s seized the %s" % [p.display_name, Shrine.kind_label(s.kind)])


static func holds_kind(state: GameState, player_id: int, kind: int) -> bool:
	for s: Shrine in state.shrines:
		if s.kind == kind and s.holder_id == player_id:
			return true
	return false


static func count_held(state: GameState, player_id: int, kind: int) -> int:
	var n := 0
	for s: Shrine in state.shrines:
		if s.kind == kind and s.holder_id == player_id:
			n += 1
	return n


static func growth_bonus(state: GameState, player_id: int) -> float:
	return Balance.SHRINE_PLENTY_GROWTH_BONUS * float(count_held(state, player_id, Balance.SHRINE_PLENTY))
