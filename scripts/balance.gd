extends Node

# All balance numbers for Crown Conquest. One source of truth.
# Per docs/DESIGN.md. Per-second numbers are divided by TICKS_PER_SECOND each tick.

# --- Simulation ---------------------------------------------------------------
const TICKS_PER_SECOND: int = 10
const TICK_DELTA: float = 1.0 / float(TICKS_PER_SECOND)

# --- Map sizes ----------------------------------------------------------------
const MAP_SIZE_SMALL: int = 0
const MAP_SIZE_MEDIUM: int = 1
const MAP_SIZE_LARGE: int = 2

const MAP_SMALL_WIDTH: int = 160
const MAP_SMALL_HEIGHT: int = 96
const MAP_SMALL_PLAYERS: int = 5

const MAP_MEDIUM_WIDTH: int = 200
const MAP_MEDIUM_HEIGHT: int = 120
const MAP_MEDIUM_PLAYERS: int = 8

const MAP_LARGE_WIDTH: int = 260
const MAP_LARGE_HEIGHT: int = 156
const MAP_LARGE_PLAYERS: int = 12

# --- Map types ---------------------------------------------------------------
const MAP_TYPE_CONTINENT: int = 0
const MAP_TYPE_ARCHIPELAGO: int = 1
const MAP_TYPE_HIGHLANDS: int = 2
const MAP_TYPE_RANDOM: int = 3

# --- Troops -------------------------------------------------------------------
const STARTING_TROOPS: float = 150.0
const STARTING_LAND_RADIUS: int = 4           # 49-tile circle around the Crown
const TROOP_CAP_BASE: float = 200.0
const TROOP_CAP_PER_LAND: float = 3.0
const GROWTH_BASE_PER_SEC: float = 2.0
const GROWTH_PER_LAND_PER_SEC: float = 0.06
const GROWTH_INTEREST_RATE_PER_SEC: float = 0.05  # peaks at troops = cap/2
const OVER_CAP_SHRINK_PER_SEC: float = 0.02
const TROOP_BAR_SWEET_LOW: float = 0.35
const TROOP_BAR_SWEET_HIGH: float = 0.65

# --- Expansion (grabbing free land) ------------------------------------------
const CLAIM_COST_BASE: float = 2.0            # troops per tile x terrain claim cost
const RUINS_CLAIM_MULT: float = 0.5
const EXPANSION_RING_INTERVAL_SEC: float = 0.3
const SEND_MIN_FRACTION: float = 0.10
const SEND_MAX_FRACTION: float = 1.00

# --- Attacking ---------------------------------------------------------------
const ATTACK_TILE_COST_BASE: float = 2.0
const ATTACK_TILE_COST_SCALE: float = 1.5     # multiplied by defender D x defenses
const DEFENDER_LOSS_PER_TILE: float = 0.5     # defender loses 0.5 x D per lost tile
const MAX_SIMULTANEOUS_ATTACKS: int = 3
const ATTACK_RING_INTERVAL_SEC: float = 0.4
const RETREAT_RETURN_FRACTION: float = 0.75
const BUILDING_DEFENSE_CAP: float = 4.0       # Fort x Wall x CrownZone, capped (not Crown tiles)
const PEACE_PERIOD_SEC: float = 60.0

# --- Terrain ------------------------------------------------------------------
# Terrain IDs stored in GameState.terrain (one byte per tile).
const TERRAIN_PLAINS: int = 0
const TERRAIN_FOREST: int = 1
const TERRAIN_HILLS: int = 2
const TERRAIN_MOUNTAINS: int = 3
const TERRAIN_WATER: int = 4
const TERRAIN_GEM: int = 5

# Target shares of the map (sum ~= 1.0). Plains fills the remainder.
const TERRAIN_SHARE_FOREST: float = 0.20
const TERRAIN_SHARE_HILLS: float = 0.10
const TERRAIN_SHARE_MOUNTAINS: float = 0.05
const TERRAIN_SHARE_WATER: float = 0.10
const TERRAIN_SHARE_GEM: float = 0.01

static var TERRAIN_CLAIM_COST: PackedFloat32Array = PackedFloat32Array([1.0, 1.5, 2.0, 0.0, 0.0, 3.0])
static var TERRAIN_DEFENSE: PackedFloat32Array    = PackedFloat32Array([1.0, 1.25, 1.5, 0.0, 0.0, 1.0])
static var TERRAIN_BLOCKED: PackedByteArray       = PackedByteArray([0, 0, 0, 1, 1, 0])  # mountains, water

const GEM_CLUSTER_MIN: int = 6
const GEM_CLUSTER_MAX: int = 12
const GEM_GROWTH_BONUS_PER_TILE: float = 0.005  # +0.5% per owned gem tile
const GEM_GROWTH_BONUS_MAX: float = 0.15

# Base map colours (overlaid with owner tint when claimed).
static var TERRAIN_COLORS: PackedColorArray = PackedColorArray([
	Color(0.76, 0.72, 0.46),   # plains
	Color(0.30, 0.52, 0.28),   # forest
	Color(0.60, 0.52, 0.38),   # hills
	Color(0.42, 0.40, 0.38),   # mountains
	Color(0.20, 0.42, 0.70),   # water
	Color(0.70, 0.42, 0.80),   # gem field
])
const RUINS_COLOR: Color = Color(0.45, 0.42, 0.40)
const OWNER_TERRAIN_TINT: float = 0.35   # how much terrain shows through owned land

# --- Crown --------------------------------------------------------------------
const CROWN_SIZE: int = 3                        # 3x3 block, centre is the life tile
const PLACEMENT_PHASE_SEC: float = 10.0
const CROWN_MIN_DIST_FROM_EDGE: int = 12
const CROWN_MIN_DIST_FROM_OTHER: int = 24
const CROWN_TILE_DEFENSE: float = 3.0            # Crown tiles (base, no Keep)
const CROWN_ZONE_DEFENSE: float = 1.5
const CROWN_ZONE_RADIUS: int = 6
const CROWN_MOVE_UNLOCK_SEC: float = 180.0
const CROWN_MOVE_COST_FRACTION: float = 0.20
const CROWN_MOVE_MIN_DIST_FROM_ENEMY: int = 10
const CROWN_MOVE_DURATION_SEC: float = 5.0
const CROWN_PLUNDER_FRACTION: float = 0.30
const FINAL_SIEGE_PLUNDER_FRACTION: float = 0.60
const FINAL_SIEGE_START_SEC: float = 600.0
const FINAL_SIEGE_CROWN_TILE_DEFENSE: float = 1.5

# --- Keep upgrades (tap Crown to buy) -----------------------------------------
# Index 0 is "base" (no Keep). Index 1 = Keep 1, etc.
static var KEEP_COST: PackedFloat32Array           = PackedFloat32Array([0.0, 300.0, 700.0, 1500.0])
static var KEEP_UNLOCK_SEC: PackedFloat32Array     = PackedFloat32Array([0.0, 0.0, 180.0, 360.0])
static var KEEP_CROWN_TILE_DEF: PackedFloat32Array = PackedFloat32Array([3.0, 4.0, 5.0, 6.0])
static var KEEP_ZONE_DEF: PackedFloat32Array       = PackedFloat32Array([1.5, 1.6, 1.8, 2.0])
static var KEEP_ZONE_RADIUS: PackedInt32Array      = PackedInt32Array([6, 8, 10, 12])
const KEEP_2_CROWN_SHIELD_CD_REDUCTION_SEC: float = 30.0
const KEEP_3_TROOP_CAP_BONUS: float = 0.05

# --- Buildings ----------------------------------------------------------------
const FORT_COST_BASE: float = 300.0
const FORT_COST_PER_EXTRA: float = 150.0
const FORT_RADIUS: int = 8
const FORT_DEFENSE: float = 1.6
const FORT_LIMIT: int = 6

const FORT2_COST: float = 400.0                   # upgrade from Fort I
const FORT2_RADIUS: int = 10
const FORT2_DEFENSE: float = 2.0

const WALL_COST_PER_TILE: float = 4.0
const WALL_DEFENSE: float = 2.5
const WALL_LIMIT: int = 400

const BARRACKS_COST_BASE: float = 400.0
const BARRACKS_COST_PER_EXTRA: float = 200.0
const BARRACKS_TROOP_CAP_BONUS: float = 0.10
const BARRACKS_LIMIT: int = 4
const BARRACKS_UNLOCK_SEC: float = 60.0

const PORT_COST: float = 250.0
const PORT_LIMIT: int = 3
const BOAT_RANGE_TILES: int = 60
const BOAT_SPEED_TILES_PER_SEC: float = 8.0

const BUILD_MIN_DIST_FROM_ENEMY: int = 3
const CAPTURED_BUILDING_LOOT_FRACTION: float = 0.25

# --- Abilities ----------------------------------------------------------------
const SWIFT_MARCH_UNLOCK_SEC: float = 0.0
const SWIFT_MARCH_COST: float = 0.0
const SWIFT_MARCH_COOLDOWN_SEC: float = 45.0
const SWIFT_MARCH_DURATION_SEC: float = 8.0
const SWIFT_MARCH_SPEED_MULT: float = 2.0
const SWIFT_MARCH_CLAIM_DISCOUNT: float = 0.25

const CROWN_SHIELD_UNLOCK_SEC: float = 0.0
const CROWN_SHIELD_COST: float = 0.0
const CROWN_SHIELD_COOLDOWN_SEC: float = 120.0
const CROWN_SHIELD_DURATION_SEC: float = 8.0

const RALLY_UNLOCK_SEC: float = 90.0
const RALLY_COST_FRACTION: float = 0.10
const RALLY_COOLDOWN_SEC: float = 60.0
const RALLY_DURATION_SEC: float = 10.0
const RALLY_ATTACK_DISCOUNT: float = 0.30

const BOMBARD_UNLOCK_SEC: float = 180.0
const BOMBARD_COST_FRACTION: float = 0.15
const BOMBARD_COOLDOWN_SEC: float = 75.0
const BOMBARD_DURATION_SEC: float = 12.0
const BOMBARD_RANGE_TILES: int = 20
const BOMBARD_AREA_RADIUS_TILES: int = 5
const BOMBARD_DEFENSE_MULT: float = 0.5
const BOMBARD_DAMAGE_PER_TILE_PER_SEC: float = 2.0

# --- Fair play ---------------------------------------------------------------
const UNDERDOG_LAND_FRACTION_OF_AVG: float = 0.5
const UNDERDOG_GROWTH_BONUS: float = 0.25
const UNDERDOG_CLAIM_DISCOUNT: float = 0.25

const EMPIRE_UPKEEP_LAND_THRESHOLD_1: float = 0.20
const EMPIRE_UPKEEP_PENALTY_1: float = -0.15
const EMPIRE_UPKEEP_LAND_THRESHOLD_2: float = 0.35
const EMPIRE_UPKEEP_PENALTY_2: float = -0.30

const RISING_EMPIRE_LAND_THRESHOLD: float = 0.30
const RISING_EMPIRE_ATTACK_DISCOUNT: float = 0.15

const DOMINION_WIN_FRACTION: float = 0.60
const MATCH_TIME_LIMIT_SEC: float = 900.0

# --- Truces ------------------------------------------------------------------
const TRUCE_DURATION_SEC: float = 90.0
const TRUCE_LIMIT: int = 2
const TRUCE_BOT_RESPONSE_SEC: float = 2.0
const OATHBREAKER_ATTACK_PENALTY: float = 0.20
const OATHBREAKER_DURATION_SEC: float = 45.0

# --- Bots --------------------------------------------------------------------
const BOT_EASY_THINK_SEC: float = 2.5
const BOT_EASY_SEND_MIN: float = 0.20
const BOT_EASY_SEND_MAX: float = 0.40
const BOT_EASY_RANDOM_MOVE_CHANCE: float = 0.20
const BOT_EASY_NO_CROWN_ATTACK_BEFORE_SEC: float = 240.0

const BOT_NORMAL_THINK_SEC: float = 1.5
const BOT_NORMAL_SEND_MIN: float = 0.30
const BOT_NORMAL_SEND_MAX: float = 0.60

const BOT_HARD_THINK_SEC: float = 0.8
const BOT_HARD_SEND_MIN: float = 0.40
const BOT_HARD_SEND_MAX: float = 0.80

const BOT_DIFFICULTY_EASY: int = 0
const BOT_DIFFICULTY_NORMAL: int = 1
const BOT_DIFFICULTY_HARD: int = 2

const BOT_PERSONALITY_EXPANDER: int = 0
const BOT_PERSONALITY_RAIDER: int = 1
const BOT_PERSONALITY_TURTLE: int = 2
const BOT_PERSONALITY_OPPORTUNIST: int = 3
const BOT_OPPORTUNIST_TRUCE_BREAK_CHANCE: float = 0.20

# --- Teams -------------------------------------------------------------------
const TEAM_SIZE: int = 2
const TEAM_COUNT: int = 4
const ALLY_SEND_FRACTION: float = 0.20

# --- XP and progression ------------------------------------------------------
const XP_PER_MATCH_PLAYED: int = 100
const XP_PER_PEAK_LAND_PCT: int = 10
const XP_PER_CROWN_CAPTURED: int = 150
const XP_FOR_WIN: int = 300
const XP_HARD_MATCH_MULT: float = 1.5
const LEVEL_XP_BASE: int = 500
const LEVEL_XP_PER_LEVEL: int = 100
const UNLOCK_COLORS_COUNT: int = 16
const UNLOCK_PATTERNS_COUNT: int = 6
const UNLOCK_CROWN_ICONS_COUNT: int = 8

# --- UI / mobile -------------------------------------------------------------
const MIN_BUTTON_PX: int = 56

# --- Player colours (first N used) -------------------------------------------
# Index 0 is reserved (unowned); player ids start at 1.
static var PLAYER_COLORS: PackedColorArray = PackedColorArray([
	Color(0.00, 0.00, 0.00),      # 0: unowned sentinel
	Color(0.25, 0.55, 1.00),      # 1: blue (you)
	Color(0.95, 0.30, 0.30),      # 2: red
	Color(0.35, 0.80, 0.40),      # 3: green
	Color(1.00, 0.80, 0.20),      # 4: yellow
	Color(0.80, 0.40, 0.90),      # 5: purple
	Color(1.00, 0.55, 0.20),      # 6: orange
	Color(0.30, 0.80, 0.80),      # 7: cyan
	Color(0.95, 0.55, 0.75),      # 8: pink
	Color(0.55, 0.75, 0.30),      # 9: lime
	Color(0.60, 0.45, 0.25),      # 10: brown
	Color(0.90, 0.90, 0.95),      # 11: white
	Color(0.35, 0.35, 0.55),      # 12: slate
])


func color_for_player(player_id: int) -> Color:
	if player_id <= 0 or player_id >= PLAYER_COLORS.size():
		return Color.BLACK
	return PLAYER_COLORS[player_id]
