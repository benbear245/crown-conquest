class_name MatchConfig
extends RefCounted

# What kind of match to start: mode, map, bots and difficulty. Built by the
# menus, read by Simulation.start_with(). Pure data.

enum Mode { SKIRMISH, TEAMS, DAILY, TUTORIAL }

const DIFFICULTY_MIXED: int = 3
const DIFFICULTY_NAMES: Array[String] = ["Easy", "Normal", "Hard", "Mixed"]
const SIZE_NAMES: Array[String] = ["Small", "Medium", "Large"]
const TYPE_NAMES: Array[String] = ["Continent", "Archipelago", "Highlands", "Random"]
const MODE_NAMES: Array[String] = ["Skirmish", "Teams", "Daily Challenge", "Tutorial"]

var mode: int = Mode.SKIRMISH
var size_preset: int = Balance.MAP_SIZE_MEDIUM
var map_type: int = Balance.MAP_TYPE_CONTINENT
var num_bots: int = 7
var difficulty: int = DIFFICULTY_MIXED
# A fixed seed replays the same map every time (Daily Challenge, or a seed
# typed into Skirmish setup). Otherwise every match gets a fresh one.
var fixed_seed: bool = false
var seed_value: int = 0
var daily_date: String = ""          # "2026-10-06" for the Daily Challenge


static func skirmish(size: int, mt: int, bots: int, diff: int, seed_text: String = "") -> MatchConfig:
	var c := MatchConfig.new()
	c.mode = Mode.SKIRMISH
	c.size_preset = size
	c.map_type = mt
	c.num_bots = clampi(bots, 1, max_bots_for(size))
	c.difficulty = diff
	if seed_text.strip_edges() != "":
		c.fixed_seed = true
		c.seed_value = seed_from_text(seed_text)
	return c


# 4 teams of 2 on a Medium map: you and a bot ally vs 3 bot pairs.
static func teams(mt: int, diff: int) -> MatchConfig:
	var c := MatchConfig.new()
	c.mode = Mode.TEAMS
	c.size_preset = Balance.MAP_SIZE_MEDIUM
	c.map_type = mt
	c.num_bots = Balance.TEAM_COUNT * Balance.TEAM_SIZE - 1
	c.difficulty = diff
	return c


# Same map and settings for everyone on a given day. `date` is
# Time.get_date_dict_from_system() (or any dict with year/month/day).
static func daily(date: Dictionary) -> MatchConfig:
	var c := MatchConfig.new()
	c.mode = Mode.DAILY
	c.daily_date = "%04d-%02d-%02d" % [int(date.year), int(date.month), int(date.day)]
	c.size_preset = Balance.DAILY_MAP_SIZE
	c.num_bots = Balance.DAILY_BOTS
	c.difficulty = Balance.DAILY_DIFFICULTY
	c.fixed_seed = true
	c.seed_value = seed_from_text("crown-daily-" + c.daily_date)
	# The map type also comes from the date (Continent, Archipelago or Highlands).
	c.map_type = posmod(c.seed_value, 3)
	return c


static func tutorial() -> MatchConfig:
	var c := MatchConfig.new()
	c.mode = Mode.TUTORIAL
	c.size_preset = Balance.MAP_SIZE_SMALL
	c.map_type = Balance.MAP_TYPE_CONTINENT
	c.num_bots = 1
	c.difficulty = Balance.BOT_DIFFICULTY_EASY
	c.fixed_seed = true
	c.seed_value = Balance.TUTORIAL_SEED
	return c


static func max_bots_for(size: int) -> int:
	return MapGen.players_for_size(size) - 1


# A typed seed: numbers are used as-is, any other text is hashed.
static func seed_from_text(text: String) -> int:
	var t: String = text.strip_edges()
	if t.is_valid_int():
		return absi(t.to_int())
	return absi(hash(t))


# The seed for the next match: the fixed one, or a fresh random one.
func next_seed() -> int:
	if fixed_seed:
		return seed_value
	return absi(int(Time.get_unix_time_from_system() * 1000.0) ^ randi())


func copy() -> MatchConfig:
	var c := MatchConfig.new()
	c.mode = mode
	c.size_preset = size_preset
	c.map_type = map_type
	c.num_bots = num_bots
	c.difficulty = difficulty
	c.fixed_seed = fixed_seed
	c.seed_value = seed_value
	c.daily_date = daily_date
	return c


# Short description, e.g. "Medium Continent · 7 bots · Mixed".
func describe() -> String:
	return "%s %s · %d bots · %s" % [SIZE_NAMES[size_preset], TYPE_NAMES[map_type], num_bots, DIFFICULTY_NAMES[difficulty]]


# Difficulty for each of `n` bots. Mixed: about 3 in 8 Easy, 1 in 8 Hard
# (at least one), the rest Normal, shuffled.
static func difficulty_list(diff: int, n: int, rng: RandomNumberGenerator) -> Array[int]:
	var out: Array[int] = []
	if diff != DIFFICULTY_MIXED:
		for i in range(n):
			out.append(diff)
		return out
	if n == 1:
		out.append(Balance.BOT_DIFFICULTY_NORMAL)
		return out
	var hard: int = maxi(1, roundi(n / 8.0))
	var easy: int = mini(n - hard, roundi(n * 3.0 / 8.0))
	for i in range(n):
		if i < hard:
			out.append(Balance.BOT_DIFFICULTY_HARD)
		elif i < hard + easy:
			out.append(Balance.BOT_DIFFICULTY_EASY)
		else:
			out.append(Balance.BOT_DIFFICULTY_NORMAL)
	for i in range(out.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: int = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out
