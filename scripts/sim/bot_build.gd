class_name BotBuild
extends RefCounted

# Building choices for bots: Keep upgrades, Forts, Barracks, Walls,
# Watchtowers, Ports and boats. Adds scored candidates to the bot's move list.

const B_KEEP: int = 0
const B_FORT: int = 1
const B_FORT2: int = 2
const B_BARRACKS: int = 3
const B_WALLS: int = 4
const B_WATCHTOWER: int = 5
const B_PORT: int = 6
const B_BOAT: int = 7
const WALLS_PER_MOVE: int = 10


static func add_moves(_sim: Simulation, p: Player, ctx: Dictionary, moves: Array[Dictionary]) -> void:
	var hard: bool = p.difficulty == Balance.BOT_DIFFICULTY_HARD
	var normal_up: bool = p.difficulty >= Balance.BOT_DIFFICULTY_NORMAL
	var turtle: bool = p.personality == Balance.BOT_PERSONALITY_TURTLE
	var threatened: bool = not (ctx["attacked_by"] as Dictionary).is_empty()
	var now: float = ctx["now"]
	# Keep upgrades (Normal: Keep 1 only; Hard: all three).
	var next_keep: int = p.keep_level + 1
	var keep_cap: int = 3 if hard else (1 if normal_up else 0)
	if next_keep <= keep_cap and now >= Balance.KEEP_UNLOCK_SEC[next_keep] \
			and p.troops >= Balance.KEEP_COST[next_keep] * 1.5:
		moves.append({"kind": Bots.MOVE_BUILD, "what": B_KEEP, "score": 1.3 if turtle else 0.8})
	# Fort: every difficulty may build them (Easy rarely).
	var fort_cost: float = BuildingsOps.next_cost(p, Balance.BUILDING_FORT)
	if fort_cost > 0.0 and p.troops >= fort_cost * 1.3:
		var score: float = 0.9 if turtle else 0.6
		if threatened:
			score *= 1.4
		if not normal_up:
			score *= 0.4
		moves.append({"kind": Bots.MOVE_BUILD, "what": B_FORT, "score": score})
	if not normal_up:
		return
	if hard and p.fort_count > 0 and p.troops >= Balance.FORT2_COST * 1.4:
		moves.append({"kind": Bots.MOVE_BUILD, "what": B_FORT2, "score": 0.7})
	var barracks_cost: float = BuildingsOps.next_cost(p, Balance.BUILDING_BARRACKS)
	if barracks_cost > 0.0 and now >= Balance.BARRACKS_UNLOCK_SEC and p.troops >= barracks_cost * 1.3 \
			and float(ctx["ratio"]) > 0.75:
		moves.append({"kind": Bots.MOVE_BUILD, "what": B_BARRACKS, "score": 0.9})
	if not hard:
		return
	if threatened and p.wall_count < Balance.WALL_LIMIT and p.troops >= Balance.WALL_COST_PER_TILE * WALLS_PER_MOVE * 3.0:
		moves.append({"kind": Bots.MOVE_BUILD, "what": B_WALLS, "score": 1.1 if turtle else 0.7})
	var tower_cost: float = BuildingsOps.next_cost(p, Balance.BUILDING_WATCHTOWER)
	if tower_cost > 0.0 and p.watchtower_count == 0 and now > 120.0 and p.troops >= tower_cost * 1.6:
		var t_score: float = 0.8 if p.personality == Balance.BOT_PERSONALITY_OPPORTUNIST or turtle else 0.6
		moves.append({"kind": Bots.MOVE_BUILD, "what": B_WATCHTOWER, "score": t_score})
	# Ports and boats: reach land across the water once the walkable land
	# nearby is taken (or straight away on island maps).
	var little_free: bool = (ctx["frontier"] as PackedInt32Array).size() < 20
	var port_cost: float = BuildingsOps.next_cost(p, Balance.BUILDING_PORT)
	if p.port_count == 0 and port_cost > 0.0 and p.troops >= port_cost * 1.5 and now > 90.0:
		moves.append({"kind": Bots.MOVE_BUILD, "what": B_PORT, "score": 0.75 if little_free else 0.35})
	elif p.port_count > 0 and little_free and ctx["can_spend"]:
		moves.append({"kind": Bots.MOVE_BUILD, "what": B_BOAT, "score": 0.65})


static func execute(sim: Simulation, p: Player, m: Dictionary) -> void:
	var state: GameState = sim.state
	match int(m["what"]):
		B_KEEP:
			sim.player_buy_keep(p.id, p.keep_level + 1)
		B_FORT:
			_build_at(sim, p, Balance.BUILDING_FORT, _pick_front_tile(sim, p, 6))
		B_BARRACKS:
			_build_at(sim, p, Balance.BUILDING_BARRACKS, _pick_near_crown(sim, p))
		B_WATCHTOWER:
			_build_at(sim, p, Balance.BUILDING_WATCHTOWER, _pick_front_tile(sim, p, 5))
		B_FORT2:
			for t: int in p.fort_tiles:
				var pos: Vector2i = state.idx_to_xy(t)
				var b: Building = state.building_at_tile.get(t, null)
				if b != null and b.type == Balance.BUILDING_FORT and sim.player_upgrade_fort(p.id, pos.x, pos.y):
					return
		B_WALLS:
			_build_walls(sim, p)
		B_PORT:
			_build_at(sim, p, Balance.BUILDING_PORT, _pick_coast_tile(sim, p))
		B_BOAT:
			_launch_boat(sim, p)


static func _build_at(sim: Simulation, p: Player, type: int, tile: int) -> void:
	if tile < 0:
		return
	var pos: Vector2i = sim.state.idx_to_xy(tile)
	sim.player_build(p.id, type, pos.x, pos.y)


# A buildable tile a few steps inside the border that faces an enemy, so the
# building covers the front line. Falls back to a tile near the Crown.
static func _pick_front_tile(sim: Simulation, p: Player, depth: int) -> int:
	var state: GameState = sim.state
	if p.crown_x < 0:
		return -1
	var border: Array = p.border.keys()
	var crown := Vector2(p.crown_x, p.crown_y)
	for _attempt in range(10):
		var bi: int = border[state.rng.randi_range(0, border.size() - 1)]
		var bpos: Vector2i = state.idx_to_xy(bi)
		var to_crown: Vector2 = crown - Vector2(bpos)
		if to_crown.length() < 1.0:
			continue
		var step: Vector2 = to_crown.normalized() * float(depth)
		var x: int = int(round(bpos.x + step.x))
		var y: int = int(round(bpos.y + step.y))
		if not state.in_bounds(x, y):
			continue
		var ti: int = state.idx(x, y)
		if BuildingsOps.tile_is_buildable(sim, p.id, ti):
			return ti
	return _pick_near_crown(sim, p)


static func _pick_near_crown(sim: Simulation, p: Player) -> int:
	var state: GameState = sim.state
	if p.crown_x < 0:
		return -1
	for _attempt in range(12):
		var x: int = p.crown_x + state.rng.randi_range(-6, 6)
		var y: int = p.crown_y + state.rng.randi_range(-6, 6)
		if not state.in_bounds(x, y):
			continue
		var ti: int = state.idx(x, y)
		if BuildingsOps.tile_is_buildable(sim, p.id, ti):
			return ti
	return -1


static func _pick_coast_tile(sim: Simulation, p: Player) -> int:
	var state: GameState = sim.state
	var border: Array = p.border.keys()
	for _attempt in range(30):
		var ti: int = border[state.rng.randi_range(0, border.size() - 1)]
		if BuildingsOps.tile_touches_water(state, ti) and BuildingsOps.tile_is_buildable(sim, p.id, ti):
			return ti
	return -1


# Walls on own border tiles that touch whoever is attacking us.
static func _build_walls(sim: Simulation, p: Player) -> void:
	var state: GameState = sim.state
	var attackers: Dictionary = {}
	for a: Attack in state.attacks:
		if a.defender_id == p.id:
			attackers[a.attacker_id] = true
	var built := 0
	for bi: int in p.border.keys():
		if built >= WALLS_PER_MOVE:
			return
		if state.wall_tiles.has(bi):
			continue
		var pos: Vector2i = state.idx_to_xy(bi)
		for off in TerritoryOps.NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if state.in_bounds(nx, ny) and attackers.has(state.owners[state.idx(nx, ny)]):
				if sim.player_build_wall(p.id, pos.x, pos.y):
					built += 1
				break


# Boats from a Port to free or enemy coast within range.
static func _launch_boat(sim: Simulation, p: Player) -> void:
	var state: GameState = sim.state
	var port: Building = null
	for b: Building in state.buildings:
		if b.owner_id == p.id and b.type == Balance.BUILDING_PORT:
			port = b
			break
	if port == null:
		return
	var r: int = Balance.BOAT_RANGE_TILES
	for _attempt in range(25):
		var x: int = port.x + state.rng.randi_range(-r, r)
		var y: int = port.y + state.rng.randi_range(-r, r)
		if not state.in_bounds(x, y):
			continue
		var ti: int = state.idx(x, y)
		var ow: int = state.owners[ti]
		if ow == p.id or state.is_blocked_terrain(state.terrain[ti]):
			continue
		if not BuildingsOps.tile_touches_water(state, ti):
			continue
		if TrucesOps.has_truce(p, ow, state.match_time):
			continue
		if sim.player_launch_boat(p.id, port.x, port.y, x, y, 0.35):
			return
