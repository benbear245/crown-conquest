extends Node

# All balance numbers for Crown Conquest. One source of truth.
# Per docs/DESIGN.md. Per-second numbers are divided by TICKS_PER_SECOND each tick.

# --- Simulation ---------------------------------------------------------------
const TICKS_PER_SECOND: int = 10
const TICK_DELTA: float = 1.0 / float(TICKS_PER_SECOND)

# Match phases.
const PHASE_PLACEMENT: int = 0
const PHASE_MATCH: int = 1
const PHASE_ENDED: int = 2

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

# Building type ids. Stored on each Building record. Walls live separately.
const BUILDING_FORT: int = 0
const BUILDING_FORT2: int = 1
const BUILDING_BARRACKS: int = 2
const BUILDING_PORT: int = 3

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
const TRUCE_OFFER_EXPIRE_SEC: float = 10.0          # a human has this long to answer a bot's offer
# Bot answers: base chance, plus bonuses if busy fighting someone else or if
# the offerer is clearly bigger (land x TRUCE_ACCEPT_BIGGER_RATIO).
const TRUCE_ACCEPT_BASE_CHANCE: float = 0.45
const TRUCE_ACCEPT_BUSY_BONUS: float = 0.25
const TRUCE_ACCEPT_BIGGER_BONUS: float = 0.25
const TRUCE_ACCEPT_BIGGER_RATIO: float = 1.3
# Bots offer a truce when two or more players are attacking them at once.
const BOT_TRUCE_OFFER_COOLDOWN_SEC: float = 30.0
# An Opportunist that plans to break a truce attacks this long after it starts.
const OPPORTUNIST_BREAK_DELAY_MIN_SEC: float = 15.0
const OPPORTUNIST_BREAK_DELAY_MAX_SEC: float = 70.0

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

# --- Bot AI (how bots score their moves; see scripts/sim/bots.gd) -------------
# Difficulty only changes how fast and how well bots think, never their numbers.
const BOT_NORMAL_WORSE_MOVE_CHANCE: float = 0.10   # Normal sometimes takes its 2nd-best move
const BOT_HARD_WORSE_MOVE_CHANCE: float = 0.0
const BOT_EASY_FORT_CHANCE: float = 0.15           # Easy: "Forts, rarely"
# Bots only expand / attack once troops reach this share of their cap, so they
# keep a defense instead of spending to zero (index = difficulty). Free land
# pays back fast, so the bar for expanding is lower than for attacking.
static var BOT_EXPAND_THRESHOLD: PackedFloat32Array = PackedFloat32Array([0.10, 0.20, 0.25])
static var BOT_ATTACK_THRESHOLD: PackedFloat32Array = PackedFloat32Array([0.25, 0.35, 0.40])
# ...adjusted by personality (Expander, Raider, Turtle, Opportunist).
static var BOT_ACT_THRESHOLD_PERSONALITY: PackedFloat32Array = PackedFloat32Array([-0.05, -0.05, 0.10, 0.0])
const BOT_RUSH_ACT_THRESHOLD: float = 0.05         # during the opening land rush...
const BOT_RUSH_END_SEC: float = 45.0               # ...which ends here, so troops recover before peace ends
const BOT_SWEET_SPOT_TARGET: float = 0.25          # Hard sends troops down to this share of its cap
const BOT_HARD_RETREAT_STALLED_RINGS: int = 2      # Hard retreats after this many rings with no progress
const BOT_THREAT_RADIUS: int = 14                  # enemy land this close to the Crown = threatened
const BOT_WALL_LENGTH: int = 7
const BOT_BUILD_TROOP_MARGIN: float = 1.3          # build only with cost x this in troops...
const BOT_TURTLE_BUILD_TROOP_MARGIN: float = 1.05  # ...Turtles build sooner
const BOT_BARRACKS_AT_CAP: float = 0.70            # Barracks only once troops press the cap
const BOT_MIN_ATTACK_TILES: float = 8.0            # don't attack unless the send buys this many tiles
const BOT_OPPORTUNIST_DISTRUST: float = 0.15       # bots accept an Opportunist's truce less often
const BOT_SCAN_SAMPLES: int = 300                  # border tiles a bot looks at per think
# Move scores. A move's score is its base plus personality / situation bonuses;
# the bot takes the highest (or, by difficulty, sometimes a worse one).
const BOT_SCORES: Dictionary = {
	"expand": 50.0, "expand_rush": 25.0, "expand_expander": 25.0, "expand_turtle": -10.0, "ruins_raider": 20.0,
	"attack": 30.0, "attack_per_tile": 0.25, "attack_tile_cap": 30.0, "attack_weakest": 15.0,
	"attack_raider": 20.0, "attack_busy_opportunist": 30.0, "attack_counter_turtle": 30.0,
	"attack_turtle_idle": -15.0, "attack_expander_free_land": -25.0, "attack_rising": 15.0,
	"attack_crown": 12.0, "attack_again": -10.0,
	"fort": 30.0, "fort_threat": 20.0, "fort_turtle": 25.0, "fort_expander": -15.0, "fort2": 25.0,
	"barracks": 30.0, "barracks_full": 20.0, "keep": 30.0, "keep_threat": 15.0, "keep_turtle": 20.0, "keep_crown_hit": 40.0,
	"wall": 55.0, "wall_turtle": 15.0, "ruins_hard": 20.0, "crown_kill_hard": 15.0, "port": 35.0, "boat": 40.0, "crown_move": 55.0,
	"truce_pressed": 70.0, "truce_opportunist_setup": 25.0, "truce_hard_flank": 35.0, "truce_hard_peace": 45.0, "attack_busy_hard": 12.0,
}

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


# Colour-blind friendly alternative (Okabe-Ito based; no pure blue, which is
# too close to water). Used when Settings.colorblind is on.
static var PLAYER_COLORS_COLORBLIND: PackedColorArray = PackedColorArray([
	Color(0.00, 0.00, 0.00),      # 0: unowned sentinel
	Color(0.95, 0.90, 0.25),      # 1: yellow (you)
	Color(0.90, 0.60, 0.00),      # 2: orange
	Color(0.35, 0.71, 0.91),      # 3: sky blue
	Color(0.00, 0.62, 0.45),      # 4: bluish green
	Color(0.84, 0.37, 0.00),      # 5: vermillion
	Color(0.80, 0.47, 0.65),      # 6: reddish purple
	Color(0.95, 0.95, 0.95),      # 7: white
	Color(0.20, 0.20, 0.22),      # 8: near black
	Color(0.55, 0.40, 0.85),      # 9: violet
	Color(0.60, 0.60, 0.60),      # 10: grey
	Color(0.55, 0.33, 0.10),      # 11: brown
	Color(0.00, 0.35, 0.40),      # 12: dark teal
])
const OWNER_TERRAIN_TINT_COLORBLIND: float = 0.18


func color_for_player(player_id: int) -> Color:
	if player_id <= 0 or player_id >= PLAYER_COLORS.size():
		return Color.BLACK
	return PLAYER_COLORS[player_id]


# --- Modes ---------------------------------------------------------------------
# Teams: 4 teams of 2 (you + a bot ally vs 3 bot pairs) on a Medium map.
# (TEAM_SIZE, TEAM_COUNT and ALLY_SEND_FRACTION are in the Teams section.)
static var TEAM_NAMES: PackedStringArray = PackedStringArray(["Lions", "Wolves", "Eagles", "Stags"])
const ALLY_SEND_COOLDOWN_SEC: float = 10.0
# A team needs this much of the usable land (combined) for a Dominion win.
# Higher than the solo 60%: two allies who never fight each other reach 60%
# together in about 3 minutes, which ended Teams matches far too early.
const TEAM_DOMINION_WIN_FRACTION: float = 0.80
const ALLY_CROWN_MIN_DIST: int = 26           # bot allies place their Crowns this close (or as close as allowed)
const BOT_ALLY_HELP_MIN_RATIO: float = 0.55   # bot helps only with troops >= 55% of its cap
const BOT_ALLY_HELP_BELOW_RATIO: float = 0.25 # ...when the ally is under 25% of its cap or its Crown is attacked

# Daily Challenge: fixed settings; the date picks the seed and map type.
const DAILY_MAP_SIZE: int = MAP_SIZE_MEDIUM
const DAILY_BOTS: int = 7
const DAILY_DIFFICULTY: int = 3               # MatchConfig.DIFFICULTY_MIXED
# Score = peak land % (rounded) + a time bonus for winning:
# DAILY_TIME_BONUS_MAX * (15:00 - win time) / 15:00, so a win at 6:00 adds 60.
const DAILY_TIME_BONUS_MAX: float = 100.0

const TUTORIAL_SEED: int = 4242


# --- Bot names ---------------------------------------------------------------
static var BOT_TITLES: PackedStringArray = PackedStringArray([
	"Duke", "Duchess", "Lord", "Lady", "Baron", "Baroness",
	"King", "Queen", "Count", "Countess", "Earl", "Princess",
])
static var BOT_NAMES: PackedStringArray = PackedStringArray([
	"Ashford", "Vex", "Thorne", "Blackwood", "Ravenhill",
	"Stormhold", "Grimm", "Darkmere", "Fenwick", "Fairfax",
	"Crow", "Vane", "Wulf", "Ironside", "Shade", "Starling",
	"Marrow", "Hollow", "Rook", "Hale", "Drake", "Ember",
])

