class_name GameState
extends RefCounted

# All match data. Pure data, no nodes. The Simulation mutates this.
# Terrain and owner live in packed byte arrays (one byte per tile).

var width: int = Balance.MAP_MEDIUM_WIDTH
var height: int = Balance.MAP_MEDIUM_HEIGHT

var terrain: PackedByteArray = PackedByteArray()
var owners: PackedByteArray = PackedByteArray()      # 0 = unowned; 255 = Ruins
var players: Array[Player] = []

const RUINS_OWNER_ID: int = 255

# Set of tile indices changed since the last Map.render() call.
# Keys are tile indices; values are always true. Cleared by the renderer.
var dirty_tiles: Dictionary = {}

var tick_count: int = 0
var seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Match phase and clocks. Set by Simulation; read by HUD and bots.
var phase: int = Balance.PHASE_PLACEMENT
var placement_time_left: float = 0.0
var match_time: float = 0.0

# tile idx -> player_id for any of the 9 Crown tiles (3x3 block).
var crown_tiles: Dictionary = {}
# player_id -> tile idx of the Crown centre (the life tile).
var crown_centres: Dictionary = {}


func configure(w: int, h: int, match_seed: int) -> void:
	width = w
	height = h
	seed = match_seed
	rng.seed = match_seed
	terrain = PackedByteArray()
	terrain.resize(w * h)
	owners = PackedByteArray()
	owners.resize(w * h)
	players = []
	dirty_tiles.clear()
	crown_tiles.clear()
	crown_centres.clear()
	tick_count = 0
	phase = Balance.PHASE_PLACEMENT
	placement_time_left = Balance.PLACEMENT_PHASE_SEC
	match_time = 0.0


func tile_count() -> int:
	return width * height


func idx(x: int, y: int) -> int:
	return y * width + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


func get_owner_at(x: int, y: int) -> int:
	return owners[idx(x, y)]


func get_owner_idx(i: int) -> int:
	return owners[i]


func set_owner(x: int, y: int, owner_id: int) -> void:
	var i := idx(x, y)
	if owners[i] != owner_id:
		owners[i] = owner_id
		dirty_tiles[i] = true


func set_owner_idx(i: int, owner_id: int) -> void:
	if owners[i] != owner_id:
		owners[i] = owner_id
		dirty_tiles[i] = true


func get_terrain_at(x: int, y: int) -> int:
	return terrain[idx(x, y)]


func set_terrain(x: int, y: int, t: int) -> void:
	var i := idx(x, y)
	if terrain[i] != t:
		terrain[i] = t
		dirty_tiles[i] = true


func is_blocked_terrain(t: int) -> bool:
	if t < 0 or t >= Balance.TERRAIN_BLOCKED.size():
		return false
	return Balance.TERRAIN_BLOCKED[t] == 1


func get_player(player_id: int) -> Player:
	for p in players:
		if p.id == player_id:
			return p
	return null


func alive_player_count() -> int:
	var n := 0
	for p in players:
		if p.is_alive:
			n += 1
	return n


func total_usable_tiles() -> int:
	# Tiles whose terrain is not blocked (mountains or water).
	var n := 0
	for i in range(terrain.size()):
		if not is_blocked_terrain(terrain[i]):
			n += 1
	return n


func idx_to_xy(i: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(i % width, i / width)
