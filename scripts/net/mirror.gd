class_name Mirror
extends RefCounted

# Client side: keeps a read-only copy of the match (a Simulation that never
# ticks) up to date from the server's updates, so the map and HUD can draw it
# exactly as they draw a local game. Rivals' hidden numbers stay at zero
# unless the server says this player may see them.

var sim: Simulation = Simulation.new()
var is_ready: bool = false


func apply(msg: Dictionary) -> Array:
	if String(msg["t"]) == "full":
		_apply_full(msg)
	if not is_ready:
		return []
	_apply_tick(msg)
	return msg.get("events", [])


func _apply_full(msg: Dictionary) -> void:
	var state: GameState = sim.state
	sim.size_preset = int(msg["size"])
	sim.map_type = int(msg["map_type"])
	sim.local_player_id = int(msg["you"])
	state.configure(int(msg["w"]), int(msg["h"]), 0)
	state.terrain = msg["terrain"]
	state.owners = msg["owners"]
	state.players = []
	var players: Array = msg["players"]
	for i in range(players.size()):
		var p := Player.new()
		p.id = i + 1
		state.players.append(p)
	for packed: int in (msg["structures"] as PackedInt32Array):
		_apply_tile(state, packed, false)
	is_ready = true


func _apply_tick(msg: Dictionary) -> void:
	var state: GameState = sim.state
	state.tick_count = int(msg["tick"])
	state.phase = int(msg["phase"])
	state.match_time = float(msg["time"])
	state.placement_time_left = float(msg["placement_left"])
	state.winner_id = int(msg["winner"])
	state.win_reason = String(msg["reason"])
	sim.set_fair_play_view(int(msg["rising"]), float(msg["avg_land"]))
	_expire_flashes(state)
	var changed := PackedInt32Array()
	for packed: int in (msg["tiles"] as PackedInt32Array):
		var i: int = packed & 0xFFFF
		if _apply_tile(state, packed, true):
			changed.append(i)
	_apply_players(state, msg)
	_update_local_border(state, changed)
	_apply_dynamic(state, msg)


# Returns true if the owner changed.
func _apply_tile(state: GameState, packed: int, flash: bool) -> bool:
	var i: int = packed & 0xFFFF
	var owner_id: int = (packed >> 16) & 0xFF
	var code: int = (packed >> 24) & 0xFF
	if i >= state.owners.size():
		return false
	var owner_changed: bool = state.owners[i] != owner_id
	state.owners[i] = owner_id
	state.dirty_tiles[i] = true
	if owner_changed and flash:
		state.flash_tiles[i] = state.match_time + 0.3
	# Structures on this tile.
	var old: Building = state.building_at_tile.get(i, null)
	if old != null:
		state.buildings.erase(old)
		state.building_at_tile.erase(i)
	state.wall_tiles.erase(i)
	if code == Protocol.STRUCT_WALL:
		state.wall_tiles[i] = owner_id
	elif code >= Protocol.STRUCT_BUILDING_BASE:
		var b := Building.new()
		b.type = (code & ~Protocol.STRUCT_DISABLED) - Protocol.STRUCT_BUILDING_BASE
		b.owner_id = owner_id
		var pos: Vector2i = state.idx_to_xy(i)
		b.x = pos.x
		b.y = pos.y
		b.tile_idx = i
		b.disabled_until = INF if (code & Protocol.STRUCT_DISABLED) != 0 else 0.0
		state.buildings.append(b)
		state.building_at_tile[i] = b
	return owner_changed


func _apply_players(state: GameState, msg: Dictionary) -> void:
	var players: Array = msg["players"]
	var crowns_moved: bool = false
	for i in range(mini(players.size(), state.players.size())):
		var p: Player = state.players[i]
		var old_crown := Vector3i(p.crown_x, p.crown_y, int(p.is_alive))
		_set_fields(p, Snapshot.PUBLIC_FIELDS, players[i])
		if old_crown != Vector3i(p.crown_x, p.crown_y, int(p.is_alive)):
			crowns_moved = true
		if p.id == sim.local_player_id:
			_set_fields(p, Snapshot.PRIVATE_FIELDS, msg["me"])
			continue
		var r: Dictionary = (msg["rivals"] as Dictionary).get(p.id, {})
		p.remote_view = r.get("view", {})
		p.troops = float(r.get("troops", 0.0))
		p.plan_target_id = int(r.get("plan", -1))
		if r.has("spy"):
			_set_fields(p, Snapshot.SPY_FIELDS, r["spy"])
	if crowns_moved:
		MatchOps.restamp_all_crowns(state)


func _set_fields(p: Player, names: Array[String], values: Array) -> void:
	for k in range(mini(names.size(), values.size())):
		p.set(names[k], values[k])


func _apply_dynamic(state: GameState, msg: Dictionary) -> void:
	var old_fronts: Dictionary = {}          # "attacker:defender" -> front
	for a: Attack in state.attacks:
		old_fronts["%d:%d" % [a.attacker_id, a.defender_id]] = a.front
	state.attacks = []
	for a_v: Array in msg["attacks"]:
		var a := Attack.new()
		a.attacker_id = int(a_v[0])
		a.defender_id = int(a_v[1])
		a.troops_remaining = maxf(0.0, float(a_v[2]))
		if a_v[3] == null:
			a.front = old_fronts.get("%d:%d" % [a.attacker_id, a.defender_id], {})
		else:
			for ti: int in (a_v[3] as PackedInt32Array):
				a.front[ti] = true
		state.attacks.append(a)
	state.boats = []
	for b_v: Array in msg["boats"]:
		var b := Boat.new()
		b.owner_id = int(b_v[0])
		b.path = PackedInt32Array([int(b_v[1])])
		state.boats.append(b)
	var was_bombarded: Array = state.bombards
	state.bombards = msg["bombards"]
	if was_bombarded.size() != state.bombards.size():
		_mark_bombard_areas(state, was_bombarded)
		_mark_bombard_areas(state, state.bombards)
	_apply_shrines(state, msg["shrines"])
	state.pending_truces = msg["truces"]


func _apply_shrines(state: GameState, packed: PackedInt32Array) -> void:
	@warning_ignore("integer_division")
	var count: int = packed.size() / 4
	if count != state.shrines.size():
		state.shrines = []
		state.shrine_at_tile.clear()
		for k in range(count):
			var s := Shrine.new()
			s.kind = packed[k * 4]
			s.x = packed[k * 4 + 1]
			s.y = packed[k * 4 + 2]
			s.tile_idx = state.idx(s.x, s.y)
			state.shrines.append(s)
			for off in ShrinesOps.SANCTUM_OFFSETS:
				var ti: int = state.idx(s.x + off.x, s.y + off.y)
				state.shrine_at_tile[ti] = s
				state.dirty_tiles[ti] = true
	for k in range(count):
		(state.shrines[k] as Shrine).holder_id = packed[k * 4 + 3]


func _expire_flashes(state: GameState) -> void:
	for i: int in state.flash_tiles.keys():
		if state.match_time >= state.flash_tiles[i]:
			state.flash_tiles.erase(i)
			state.dirty_tiles[i] = true


func _mark_bombard_areas(state: GameState, list: Array) -> void:
	var r: int = Balance.BOMBARD_AREA_RADIUS_TILES
	for b: Dictionary in list:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x: int = int(b["target_x"]) + dx
				var y: int = int(b["target_y"]) + dy
				if state.in_bounds(x, y):
					state.dirty_tiles[state.idx(x, y)] = true


# Only the local player's border matters on a client (Sabotage target lookup,
# Bombard range), so it is kept up to date around changed tiles only.
func _update_local_border(state: GameState, changed: PackedInt32Array) -> void:
	var me: Player = state.get_player(sim.local_player_id)
	if me == null:
		return
	if me.border.is_empty() and me.land > 0:
		for i in range(state.owners.size()):
			if state.owners[i] == me.id and TerritoryOps.tile_is_border(state, i, me.id):
				me.border[i] = true
		return
	for i: int in changed:
		var pos: Vector2i = state.idx_to_xy(i)
		for off: Vector2i in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var x: int = pos.x + off.x
			var y: int = pos.y + off.y
			if not state.in_bounds(x, y):
				continue
			var ni: int = state.idx(x, y)
			if state.owners[ni] == me.id and TerritoryOps.tile_is_border(state, ni, me.id):
				me.border[ni] = true
			else:
				me.border.erase(ni)
