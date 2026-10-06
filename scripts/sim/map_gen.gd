class_name MapGen
extends RefCounted

# Pure-sim map generator. Fills GameState.terrain from the seeded RNG only,
# so a given (map_type, seed, size) produces the same map every time.

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]


static func dims_for_size(size_preset: int) -> Vector2i:
	match size_preset:
		Balance.MAP_SIZE_SMALL:
			return Vector2i(Balance.MAP_SMALL_WIDTH, Balance.MAP_SMALL_HEIGHT)
		Balance.MAP_SIZE_LARGE:
			return Vector2i(Balance.MAP_LARGE_WIDTH, Balance.MAP_LARGE_HEIGHT)
		_:
			return Vector2i(Balance.MAP_MEDIUM_WIDTH, Balance.MAP_MEDIUM_HEIGHT)


static func players_for_size(size_preset: int) -> int:
	match size_preset:
		Balance.MAP_SIZE_SMALL:
			return Balance.MAP_SMALL_PLAYERS
		Balance.MAP_SIZE_LARGE:
			return Balance.MAP_LARGE_PLAYERS
		_:
			return Balance.MAP_MEDIUM_PLAYERS


# Generates terrain into state.terrain. Expects state.width/height/seed set.
static func generate(state: GameState, map_type: int) -> void:
	var resolved := map_type
	if map_type == Balance.MAP_TYPE_RANDOM:
		resolved = state.rng.randi_range(0, 2)
	var w := state.width
	var h := state.height

	var elevation := FastNoiseLite.new()
	elevation.noise_type = FastNoiseLite.TYPE_PERLIN
	elevation.seed = state.seed
	elevation.frequency = 0.025
	elevation.fractal_octaves = 4
	elevation.fractal_lacunarity = 2.0
	elevation.fractal_gain = 0.5

	var biome := FastNoiseLite.new()
	biome.noise_type = FastNoiseLite.TYPE_PERLIN
	biome.seed = state.seed + 1337
	biome.frequency = 0.05

	var elevs := PackedFloat32Array()
	elevs.resize(w * h)
	for y in range(h):
		for x in range(w):
			var e := elevation.get_noise_2d(float(x), float(y))
			e = _apply_shape(e, x, y, w, h, resolved)
			elevs[y * w + x] = e

	var sample := elevs.duplicate()
	sample.sort()
	var n := sample.size()

	var water_share := _water_share_for(resolved)
	var mountain_share := _mountain_share_for(resolved)
	var hill_share := _hill_share_for(resolved)

	var water_th: float = sample[clampi(int(water_share * n), 0, n - 1)]
	var mountain_th: float = sample[clampi(int((1.0 - mountain_share) * n), 0, n - 1)]
	var hill_th: float = sample[clampi(int((1.0 - mountain_share - hill_share) * n), 0, n - 1)]

	for i in range(n):
		var e := elevs[i]
		if e <= water_th:
			state.terrain[i] = Balance.TERRAIN_WATER
			continue
		if e >= mountain_th:
			state.terrain[i] = Balance.TERRAIN_MOUNTAINS
			continue
		if e >= hill_th:
			state.terrain[i] = Balance.TERRAIN_HILLS
			continue
		var p := state.idx_to_xy(i)
		var b := biome.get_noise_2d(float(p.x), float(p.y))
		if b > 0.15:
			state.terrain[i] = Balance.TERRAIN_FOREST
		else:
			state.terrain[i] = Balance.TERRAIN_PLAINS

	_place_gem_clusters(state)


static func _apply_shape(elevation: float, x: int, y: int, w: int, h: int, mt: int) -> float:
	match mt:
		Balance.MAP_TYPE_CONTINENT:
			var dx := (float(x) - float(w) * 0.5) / (float(w) * 0.5)
			var dy := (float(y) - float(h) * 0.5) / (float(h) * 0.5)
			var dist: float = sqrt(dx * dx + dy * dy)
			return elevation - maxf(0.0, (dist - 0.55)) * 1.4
		Balance.MAP_TYPE_ARCHIPELAGO:
			return elevation - 0.18
		Balance.MAP_TYPE_HIGHLANDS:
			return elevation + 0.12
		_:
			return elevation


static func _water_share_for(mt: int) -> float:
	match mt:
		Balance.MAP_TYPE_ARCHIPELAGO:
			return 0.35
		Balance.MAP_TYPE_HIGHLANDS:
			return 0.05
		_:
			return Balance.TERRAIN_SHARE_WATER


static func _mountain_share_for(mt: int) -> float:
	match mt:
		Balance.MAP_TYPE_HIGHLANDS:
			return 0.12
		_:
			return Balance.TERRAIN_SHARE_MOUNTAINS


static func _hill_share_for(mt: int) -> float:
	match mt:
		Balance.MAP_TYPE_HIGHLANDS:
			return 0.22
		_:
			return Balance.TERRAIN_SHARE_HILLS


static func _place_gem_clusters(state: GameState) -> void:
	var target_gems := int(float(state.terrain.size()) * Balance.TERRAIN_SHARE_GEM)
	var placed := 0
	var attempts := 0
	while placed < target_gems and attempts < 400:
		attempts += 1
		var cx := state.rng.randi_range(2, state.width - 3)
		var cy := state.rng.randi_range(2, state.height - 3)
		var start_terrain: int = state.terrain[state.idx(cx, cy)]
		if start_terrain != Balance.TERRAIN_PLAINS and start_terrain != Balance.TERRAIN_FOREST \
				and start_terrain != Balance.TERRAIN_HILLS:
			continue
		var cluster_size := state.rng.randi_range(Balance.GEM_CLUSTER_MIN, Balance.GEM_CLUSTER_MAX)
		placed += _grow_gem_cluster(state, cx, cy, cluster_size)


static func _grow_gem_cluster(state: GameState, cx: int, cy: int, size: int) -> int:
	var added := 0
	var frontier: Array[Vector2i] = [Vector2i(cx, cy)]
	var seen := {state.idx(cx, cy): true}
	while added < size and not frontier.is_empty():
		var pick := state.rng.randi_range(0, frontier.size() - 1)
		var p: Vector2i = frontier[pick]
		frontier.remove_at(pick)
		var ti := state.idx(p.x, p.y)
		var t: int = state.terrain[ti]
		if t == Balance.TERRAIN_MOUNTAINS or t == Balance.TERRAIN_WATER or t == Balance.TERRAIN_GEM:
			continue
		state.terrain[ti] = Balance.TERRAIN_GEM
		added += 1
		for off in NEIGHBOR_OFFSETS:
			var np := p + off
			if not state.in_bounds(np.x, np.y):
				continue
			var ni := state.idx(np.x, np.y)
			if not seen.has(ni):
				seen[ni] = true
				frontier.append(np)
	return added
