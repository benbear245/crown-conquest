class_name Progression
extends RefCounted

# Progression rules: XP per match, levels, what each level unlocks, and the
# achievements. Pure functions; SaveData stores the results. Nothing here
# makes you stronger in a match — every unlock is cosmetic.

# 16 territory colours. The first 4 are free; one more unlocks per level.
const COLOR_NAMES: Array[String] = [
	"Royal Blue", "Crimson", "Emerald", "Gold", "Violet", "Tangerine", "Teal", "Rose",
	"Lime", "Copper", "Ivory", "Navy", "Magenta", "Sky", "Forest", "Obsidian",
]
static var COLORS: PackedColorArray = PackedColorArray([
	Color(0.25, 0.55, 1.00), Color(0.86, 0.20, 0.27), Color(0.20, 0.75, 0.45), Color(1.00, 0.80, 0.20),
	Color(0.60, 0.40, 0.95), Color(1.00, 0.55, 0.15), Color(0.15, 0.70, 0.70), Color(0.95, 0.50, 0.70),
	Color(0.65, 0.85, 0.25), Color(0.75, 0.45, 0.25), Color(0.93, 0.92, 0.85), Color(0.18, 0.25, 0.55),
	Color(0.85, 0.25, 0.75), Color(0.45, 0.80, 1.00), Color(0.15, 0.45, 0.25), Color(0.22, 0.22, 0.28),
])
const FREE_COLORS: int = 4
const PATTERN_NAMES: Array[String] = ["None", "Stripes", "Dots", "Checks", "Waves", "Scales", "Bricks"]
const CROWN_NAMES: Array[String] = ["Classic", "Tiara", "Laurel", "Star", "Horned", "Jewel", "Circlet", "Imperial"]
const PATTERN_LEVELS: Array[int] = [1, 2, 4, 6, 8, 10, 14]
const CROWN_LEVELS: Array[int] = [1, 3, 5, 7, 9, 11, 13, 15]
const EFFECT_NAMES: Array[String] = ["None", "Fireworks", "Confetti", "Golden rain"]
const EFFECT_LEVELS: Array[int] = [1, 1, 5, 10]   # Fireworks are free
# Titles earned by level ([level, title]); achievements add their own titles.
const LEVEL_TITLES: Array = [[1, "Squire"], [3, "Knight"], [6, "Baron"], [9, "Count"], [12, "Duke"], [15, "Monarch"], [20, "Emperor"]]

# Achievements: id -> name, how to earn it, and the title it unlocks.
const ACHIEVEMENTS: Array = [
	{"id": "kingslayer", "name": "Kingslayer", "desc": "Take 3 Crowns in one match", "title": "Kingslayer"},
	{"id": "underdog", "name": "Underdog", "desc": "Win after being the smallest player at 3:00", "title": "Underdog"},
	{"id": "island_king", "name": "Island King", "desc": "Win on Archipelago after building 3 Ports", "title": "Island King"},
	{"id": "speedrun", "name": "Speedrun", "desc": "Win in under 6 minutes", "title": "Swift"},
	{"id": "dominion", "name": "Dominion", "desc": "Win by owning 60% of the land", "title": "Dominator"},
	{"id": "first_victory", "name": "First Victory", "desc": "Win your first match", "title": "Victor"},
	{"id": "hard_won", "name": "Hard Won", "desc": "Win a match against Hard bots", "title": "Champion"},
	{"id": "untouchable", "name": "Untouchable", "desc": "Win without your Crown ever coming under attack", "title": "Untouchable"},
	{"id": "master_builder", "name": "Master Builder", "desc": "Build 8 buildings in one match", "title": "Architect"},
	{"id": "peacemaker", "name": "Peacemaker", "desc": "Make 3 truces in one match", "title": "Diplomat"},
	{"id": "team_player", "name": "Team Player", "desc": "Win a Teams match after sending your ally 1,000+ troops", "title": "Loyal"},
	{"id": "siege_lord", "name": "Siege Lord", "desc": "Take a Crown during the Final Siege", "title": "Siege Lord"},
]


# --- Levels --------------------------------------------------------------------

# XP needed to go from level n to n + 1 (the design's 500 + 100 × n).
static func xp_needed(level: int) -> int:
	return Balance.LEVEL_XP_BASE + Balance.LEVEL_XP_PER_LEVEL * level


# {level, into (XP into this level), need (XP for the next level)}.
static func level_info(total_xp: int) -> Dictionary:
	var level: int = 1
	var left: int = maxi(total_xp, 0)
	while left >= xp_needed(level):
		left -= xp_needed(level)
		level += 1
	return {"level": level, "into": left, "need": xp_needed(level)}


static func color_level(i: int) -> int:
	return 1 if i < FREE_COLORS else i - FREE_COLORS + 2       # levels 2..13


static func pattern_level(i: int) -> int:
	return PATTERN_LEVELS[i]


static func crown_level(i: int) -> int:
	return CROWN_LEVELS[i]


static func effect_level(i: int) -> int:
	return EFFECT_LEVELS[i]


# Everything that unlocks when reaching `level` (for the level-up message).
static func unlocks_at(level: int) -> Array[String]:
	var out: Array[String] = []
	for i in range(COLOR_NAMES.size()):
		if color_level(i) == level and level > 1:
			out.append("%s colour" % COLOR_NAMES[i])
	for i in range(1, PATTERN_NAMES.size()):
		if pattern_level(i) == level:
			out.append("%s pattern" % PATTERN_NAMES[i])
	for i in range(1, CROWN_NAMES.size()):
		if crown_level(i) == level:
			out.append("%s Crown" % CROWN_NAMES[i])
	for i in range(1, EFFECT_NAMES.size()):
		if effect_level(i) == level:
			out.append("%s victory effect" % EFFECT_NAMES[i])
	for t: Array in LEVEL_TITLES:
		if int(t[0]) == level and level > 1:
			out.append("title \"%s\"" % t[1])
	return out


# --- XP for a match ------------------------------------------------------------

# `result` comes from MatchTracker.result(). Returns {total, lines}.
static func match_xp(result: Dictionary) -> Dictionary:
	var lines: Array[String] = []
	var xp: int = Balance.XP_PER_MATCH_PLAYED
	lines.append("Played  +%d" % Balance.XP_PER_MATCH_PLAYED)
	var pct: int = int(floorf(float(result.peak_pct)))
	if pct > 0:
		xp += pct * Balance.XP_PER_PEAK_LAND_PCT
		lines.append("Peak land %d%%  +%d" % [pct, pct * Balance.XP_PER_PEAK_LAND_PCT])
	var crowns: int = int(result.crowns)
	if crowns > 0:
		xp += crowns * Balance.XP_PER_CROWN_CAPTURED
		lines.append("Crowns taken %d  +%d" % [crowns, crowns * Balance.XP_PER_CROWN_CAPTURED])
	if bool(result.won):
		xp += Balance.XP_FOR_WIN
		lines.append("Win  +%d" % Balance.XP_FOR_WIN)
	if bool(result.hard):
		var bonus: int = roundi(xp * (Balance.XP_HARD_MATCH_MULT - 1.0))
		xp += bonus
		lines.append("Hard bots ×%.1f  +%d" % [Balance.XP_HARD_MATCH_MULT, bonus])
	return {"total": xp, "lines": lines}


# --- Achievements ----------------------------------------------------------------

static func achievement(id: String) -> Dictionary:
	for a: Dictionary in ACHIEVEMENTS:
		if a.id == id:
			return a
	return {}


# Achievements this match earned (whether or not they're new).
static func earned(result: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var won: bool = bool(result.won)
	if int(result.crowns) >= 3:
		out.append("kingslayer")
	if won and bool(result.smallest_at_3min):
		out.append("underdog")
	if won and int(result.map_type) == Balance.MAP_TYPE_ARCHIPELAGO and int(result.ports_built) >= 3:
		out.append("island_king")
	if won and float(result.duration_sec) < 360.0:
		out.append("speedrun")
	if won and str(result.win_reason).begins_with("Dominion"):
		out.append("dominion")
	if won:
		out.append("first_victory")
	if won and bool(result.hard):
		out.append("hard_won")
	if won and not bool(result.crown_attacked):
		out.append("untouchable")
	if int(result.buildings_built) >= 8:
		out.append("master_builder")
	if int(result.truces_made) >= 3:
		out.append("peacemaker")
	if won and int(result.mode) == MatchConfig.Mode.TEAMS and float(result.sent_to_ally) >= 1000.0:
		out.append("team_player")
	if int(result.siege_crowns) > 0:
		out.append("siege_lord")
	return out


# --- Cosmetics on the map ----------------------------------------------------------

# How much to darken tile (x, y) of your territory for a pattern (0 = none).
static func pattern_shade(pattern: int, x: int, y: int) -> float:
	match pattern:
		1:   # stripes
			return 0.20 if posmod(x + y, 6) < 2 else 0.0
		2:   # dots
			return 0.28 if posmod(x, 4) == 1 and posmod(y, 4) == 1 else 0.0
		3:   # checks
			@warning_ignore("integer_division")
			return 0.14 if posmod(x / 3 + y / 3, 2) == 0 else 0.0
		4:   # waves
			return 0.22 if posmod(y + roundi(1.6 * sin(float(x) * 0.7)), 5) == 0 else 0.0
		5:   # scales
			@warning_ignore("integer_division")
			var row: int = y / 3
			var dx: int = posmod(x + (row % 2) * 3, 6) - 3
			var dy: int = posmod(y, 3)
			var d2: int = dx * dx + dy * dy * 2
			return 0.22 if d2 >= 6 and d2 <= 9 else 0.0
		6:   # bricks
			@warning_ignore("integer_division")
			var offset: int = (y / 3 % 2) * 3
			return 0.24 if posmod(y, 3) == 0 or posmod(x + offset, 6) == 0 else 0.0
	return 0.0
