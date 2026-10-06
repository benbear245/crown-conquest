class_name GameState
extends RefCounted

# All match data. Pure data, no nodes. The Simulation mutates this.
# Terrain and owner live in packed byte arrays (one byte per tile).

var width: int = Balance.MAP_MEDIUM_WIDTH
var height: int = Balance.MAP_MEDIUM_HEIGHT

var terrain: PackedByteArray = PackedByteArray()
var owners: PackedByteArray = PackedByteArray()      # 0 = unowned; 255 = Ruins
# 1 where the terrain can't be owned (mountains, water). Filled once by
# finalize_terrain() so hot loops avoid the per-tile terrain lookup.
var blocked: PackedByteArray = PackedByteArray()
var players: Array[Player] = []

const RUINS_OWNER_ID: int = 255

# Set of tile indices changed since the last Map.render() call.
# Keys are tile indices; values are always true. Cleared by the renderer.
var dirty_tiles: Dictionary = {}
# Headless runs (balance simulator) have no renderer to clear dirty_tiles.
var track_dirty: bool = true

var tick_count: int = 0
var match_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()

# Match phase and clocks. Set by Simulation; read by HUD and bots.
var phase: int = Balance.PHASE_PLACEMENT
var placement_time_left: float = 0.0
var match_time: float = 0.0

# tile idx -> player_id for any of the 9 Crown tiles (3x3 block).
var crown_tiles: Dictionary = {}
# player_id -> tile idx of the Crown centre (the life tile).
var crown_centres: Dictionary = {}

# Active attacks (all players). Simulation ticks and consumes these.
var attacks: Array = []
# Recently captured tile idx -> absolute match_time when flash expires.
var flash_tiles: Dictionary = {}

# All standing structures. Walls live in wall_tiles instead because they're
# single-tile features without a radius.
var buildings: Array = []                      # Array[Building]
var wall_tiles: Dictionary = {}                # tile_idx -> owner_id
# Fast lookup: tile_idx -> Building for the Fort/Fort II/Barracks/Port stamped there.
var building_at_tile: Dictionary = {}
# Active boats (all players).
var boats: Array = []                          # Array[Boat]
# Floating numbers for the HUD ("+75 loot", "+1,240 plunder").
# Entries: {tile_idx, text, owner_id, until}. Skipped in headless runs.
var popups: Array = []
# Active Bombards: each entry has owner_id, target_x, target_y, until.
var bombards: Array = []
# Pending truce offers awaiting an answer. Entries: {from_id, to_id, decide_at}.
var pending_truces: Array = []
# One-shot events for the presentation layer (sounds, shake, vibration).
# The game scene drains this every frame; the balance sim clears it.
var events: Array = []

# End-of-match outcome, set by Simulation.end_match. In Teams the whole
# winning team wins (winner_team), winner_id is its best player.
var winner_id: int = 0
var winner_team: int = -1
var win_reason: String = ""
# Map type actually generated (Random resolved to Continent/Archipelago/Highlands).
var resolved_map_type: int = 0
# Teams mode: players have a team and an ally (see Player.team / ally_id).
var teams_mode: bool = false
# Tutorial: no placement countdown, no Final Siege, no 15:00 limit and no
# Dominion win: the tutorial match ends when a Crown falls.
var tutorial_rules: bool = false
# Top-of-screen banner shown by the HUD until the expiry.
var active_announcement_text: String = ""
var active_announcement_until: float = 0.0

# Fair play caches (refreshed once a second by FairPlayOps).
var avg_alive_land: float = 0.0
var rising_empire_id: int = -1
var fair_play_next_tick: int = 0

# Usable (not water / mountain) tile count. Terrain never changes after map
# generation, so this is computed once.
var _usable_tiles: int = -1


static func format_time(seconds: float) -> String:
	var total: int = int(seconds)
	@warning_ignore("integer_division")
	var mm: int = total / 60
	var ss: int = total % 60
	return "%d:%02d" % [mm, ss]


# 1240 -> "1,240"
static func format_int(n: int) -> String:
	var s: String = str(absi(n))
	var out: String = ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


func is_final_siege() -> bool:
	return match_time >= Balance.FINAL_SIEGE_START_SEC and not tutorial_rules


func configure(w: int, h: int, new_seed: int) -> void:
	width = w
	height = h
	match_seed = new_seed
	rng.seed = new_seed
	terrain = PackedByteArray()
	terrain.resize(w * h)
	owners = PackedByteArray()
	owners.resize(w * h)
	players = []
	dirty_tiles.clear()
	crown_tiles.clear()
	crown_centres.clear()
	attacks = []
	flash_tiles.clear()
	buildings = []
	wall_tiles.clear()
	building_at_tile.clear()
	boats = []
	popups = []
	bombards = []
	pending_truces = []
	events = []
	winner_id = 0
	winner_team = -1
	win_reason = ""
	teams_mode = false
	tutorial_rules = false
	active_announcement_text = ""
	active_announcement_until = 0.0
	tick_count = 0
	phase = Balance.PHASE_PLACEMENT
	placement_time_left = Balance.PLACEMENT_PHASE_SEC
	match_time = 0.0
	avg_alive_land = 0.0
	rising_empire_id = -1
	fair_play_next_tick = 0
	_usable_tiles = -1


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
	set_owner_idx(idx(x, y), owner_id)


func set_owner_idx(i: int, owner_id: int) -> void:
	if owners[i] != owner_id:
		owners[i] = owner_id
		if track_dirty:
			dirty_tiles[i] = true


# Call once after map generation (terrain is fixed after that).
func finalize_terrain() -> void:
	blocked = PackedByteArray()
	blocked.resize(terrain.size())
	for i in range(terrain.size()):
		blocked[i] = 1 if is_blocked_terrain(terrain[i]) else 0
	_usable_tiles = -1


func get_terrain_at(x: int, y: int) -> int:
	return terrain[idx(x, y)]


func set_terrain(x: int, y: int, t: int) -> void:
	var i := idx(x, y)
	if terrain[i] != t:
		terrain[i] = t
		dirty_tiles[i] = true
		_usable_tiles = -1


func is_blocked_terrain(t: int) -> bool:
	if t < 0 or t >= Balance.TERRAIN_BLOCKED.size():
		return false
	return Balance.TERRAIN_BLOCKED[t] == 1


# Player ids are 1..players.size() in order, so this is an index lookup.
func get_player(player_id: int) -> Player:
	if player_id >= 1 and player_id <= players.size():
		var p: Player = players[player_id - 1]
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
	if _usable_tiles < 0:
		var n := 0
		for i in range(terrain.size()):
			if not is_blocked_terrain(terrain[i]):
				n += 1
		_usable_tiles = n
	return _usable_tiles


func land_fraction(p: Player) -> float:
	return float(p.land) / float(maxi(total_usable_tiles(), 1))


func idx_to_xy(i: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(i % width, i / width)
