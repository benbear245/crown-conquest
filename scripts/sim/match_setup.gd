class_name MatchSetup
extends RefCounted

# Everything that decides what kind of match is played. Saved as the
# player's "Quick play" choice and sent from an online host to the server.

const MODE_SKIRMISH: String = "skirmish"
const MODE_DAILY: String = "daily"
const MODE_TUTORIAL: String = "tutorial"
const MODE_ONLINE: String = "online"
const DIFFICULTY_MIXED: int = -1

var size: int = Balance.MAP_SIZE_MEDIUM
var map_type: int = Balance.MAP_TYPE_CONTINENT
var bots: int = 7
var difficulty: int = DIFFICULTY_MIXED
var match_seed: int = 0
var mode: String = MODE_SKIRMISH


# Most bots a map size can fit (players are capped by the colour table).
static func max_bots_for(size_preset: int) -> int:
	return 7 if size_preset == Balance.MAP_SIZE_SMALL else Balance.PLAYER_COLORS.size() - 2


func clamped() -> MatchSetup:
	var s := MatchSetup.from_dict(to_dict())
	s.size = clampi(size, Balance.MAP_SIZE_SMALL, Balance.MAP_SIZE_LARGE)
	s.map_type = clampi(map_type, Balance.MAP_TYPE_CONTINENT, Balance.MAP_TYPE_RANDOM)
	s.bots = clampi(bots, 1, max_bots_for(s.size))
	s.difficulty = clampi(difficulty, DIFFICULTY_MIXED, Balance.BOT_DIFFICULTY_HARD)
	return s


func to_dict() -> Dictionary:
	return {"size": size, "map_type": map_type, "bots": bots, "difficulty": difficulty,
		"seed": match_seed, "mode": mode}


static func from_dict(d: Dictionary) -> MatchSetup:
	var s := MatchSetup.new()
	s.size = int(d.get("size", s.size))
	s.map_type = int(d.get("map_type", s.map_type))
	s.bots = int(d.get("bots", s.bots))
	s.difficulty = int(d.get("difficulty", s.difficulty))
	s.match_seed = int(d.get("seed", 0))
	s.mode = String(d.get("mode", MODE_SKIRMISH))
	return s


# Today's Daily Challenge: the same map and settings for everyone, from the date.
static func daily(date: String) -> MatchSetup:
	var s := MatchSetup.new()
	s.mode = MODE_DAILY
	s.match_seed = absi(hash("crown-conquest-daily-" + date))
	s.size = Balance.MAP_SIZE_MEDIUM
	s.map_type = s.match_seed % 3                   # continent, archipelago or highlands
	s.bots = 7
	s.difficulty = DIFFICULTY_MIXED
	return s


static func tutorial() -> MatchSetup:
	var s := MatchSetup.new()
	s.mode = MODE_TUTORIAL
	s.match_seed = 20261016
	s.size = Balance.MAP_SIZE_SMALL
	s.map_type = Balance.MAP_TYPE_CONTINENT
	s.bots = 1
	s.difficulty = Balance.BOT_DIFFICULTY_EASY
	return s


static func label_for_size(v: int) -> String:
	return ["Small", "Medium", "Large"][clampi(v, 0, 2)]


static func label_for_type(v: int) -> String:
	return ["Continent", "Archipelago", "Highlands", "Random"][clampi(v, 0, 3)]


static func label_for_difficulty(v: int) -> String:
	return "Mixed" if v == DIFFICULTY_MIXED else ["Easy", "Normal", "Hard"][clampi(v, 0, 2)]
