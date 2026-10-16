class_name Progression
extends RefCounted

# Pure rules for XP, levels, achievements, daily challenges and the Daily
# Challenge score. Works on a match summary (built by MatchRecorder) and the
# player's lifetime stats; never touches nodes or files.
#
# Summary keys: won, place, players, time, reason, dominion, mode, map_type,
# difficulty, peak_land_pct, crowns, shrines_taken, held_all_shrines,
# spy_ok, truces_made, forts_built, walls_built, ports_built, bombards,
# survived_sec, underdog_at_3, online.

# id: [name, how to earn it, title index unlocked (0 = none)]
const ACHIEVEMENTS: Dictionary = {
	"first_win": ["First Victory", "Win a match", 0],
	"kingslayer": ["Kingslayer", "Take 3 Crowns in one match", 7],
	"dominion": ["Dominion", "Win by owning 60% of the land", 0],
	"underdog": ["Underdog", "Win after being the smallest player at 3:00", 9],
	"speedrun": ["Swift Conqueror", "Win in under 6:00", 0],
	"spymaster": ["Spymaster", "Succeed with 5 spy actions in one match", 8],
	"shrine_keeper": ["High Priest", "Hold every Shrine at the same time", 0],
	"island_king": ["Island King", "Win on Archipelago after building 3 Ports", 10],
	"giant_slayer": ["Giant Slayer", "Win against only Hard bots", 0],
	"peacemaker": ["Peacemaker", "Make 3 truces in one match", 0],
	"great_wall": ["Great Wall", "Build 40 Wall tiles in one match", 0],
	"veteran": ["Veteran", "Play 25 matches", 0],
	"conqueror": ["Conqueror", "Take 50 Crowns in total", 11],
	"daily_ruler": ["Daily Ruler", "Finish a Daily Challenge match", 0],
	"friendly_rivals": ["Friendly Rivals", "Finish an online match", 0],
	"graduate": ["Graduate", "Finish the tutorial", 12],
}

# Daily challenge pool: id -> [text, summary key, target, "sum" or "best"].
const CHALLENGES: Dictionary = {
	"crowns2": ["Take 2 enemy Crowns", "crowns", 2, "sum"],
	"win1": ["Win a match", "won", 1, "sum"],
	"shrines2": ["Capture 2 Shrines", "shrines_taken", 2, "sum"],
	"spy3": ["Succeed with 3 spy actions", "spy_ok", 3, "sum"],
	"forts3": ["Build 3 Forts", "forts_built", 3, "sum"],
	"truces2": ["Make 2 truces", "truces_made", 2, "sum"],
	"bombard2": ["Fire Bombard twice", "bombards", 2, "sum"],
	"play3": ["Play 3 matches", "played", 3, "sum"],
	"land25": ["Own 25% of the map in one match", "peak_land_pct", 25, "best"],
	"survive8": ["Still have your Crown at 8:00", "survived_sec", 480, "best"],
	"walls20": ["Build 20 Wall tiles", "walls_built", 20, "sum"],
}


# --- XP and levels ----------------------------------------------------------------

# XP needed to go from level n to n + 1.
static func xp_to_next(level: int) -> int:
	return Balance.LEVEL_XP_BASE + Balance.LEVEL_XP_PER_LEVEL * level


# {level, into (XP into this level), need (XP for the next one)} for total XP.
static func level_info(total_xp: int) -> Dictionary:
	var level: int = 1
	var left: int = maxi(total_xp, 0)
	while left >= xp_to_next(level):
		left -= xp_to_next(level)
		level += 1
	return {"level": level, "into": left, "need": xp_to_next(level)}


# [[label, amount], ...] for one match, as shown on the recap.
static func match_xp(summary: Dictionary) -> Array:
	var lines: Array = [["Played a match", Balance.XP_PER_MATCH_PLAYED]]
	var land_xp: int = int(round(float(summary.get("peak_land_pct", 0.0)))) * Balance.XP_PER_PEAK_LAND_PCT
	if land_xp > 0:
		lines.append(["Peak land %d%%" % int(round(float(summary["peak_land_pct"]))), land_xp])
	var crowns: int = int(summary.get("crowns", 0))
	if crowns > 0:
		lines.append(["Crowns taken ×%d" % crowns, crowns * Balance.XP_PER_CROWN_CAPTURED])
	if bool(summary.get("won", false)):
		lines.append(["Victory", Balance.XP_FOR_WIN])
	if int(summary.get("difficulty", -1)) == Balance.BOT_DIFFICULTY_HARD:
		var subtotal: int = 0
		for l: Array in lines:
			subtotal += int(l[1])
		lines.append(["Hard bots bonus", int(round(subtotal * (Balance.XP_HARD_MATCH_MULT - 1.0)))])
	return lines


static func daily_score(summary: Dictionary) -> int:
	var score: int = int(round(float(summary.get("peak_land_pct", 0.0)) * Balance.DAILY_SCORE_PER_LAND_PCT))
	if bool(summary.get("won", false)):
		var left: float = maxf(0.0, Balance.MATCH_TIME_LIMIT_SEC - float(summary.get("time", 0.0)))
		score += Balance.DAILY_SCORE_WIN_BONUS + int(left) * Balance.DAILY_SCORE_PER_SEC_UNDER_LIMIT
	return score


# --- Achievements ---------------------------------------------------------------

# Achievement ids this match earns (already-earned ones filtered by the caller).
static func earned_achievements(s: Dictionary, lifetime: Dictionary) -> Array[String]:
	var won: bool = bool(s.get("won", false))
	var out: Array[String] = []
	var checks: Dictionary = {
		"first_win": won,
		"kingslayer": int(s.get("crowns", 0)) >= 3,
		"dominion": won and bool(s.get("dominion", false)),
		"underdog": won and bool(s.get("underdog_at_3", false)),
		"speedrun": won and float(s.get("time", 9999.0)) < 360.0,
		"spymaster": int(s.get("spy_ok", 0)) >= 5,
		"shrine_keeper": bool(s.get("held_all_shrines", false)),
		"island_king": won and int(s.get("map_type", -1)) == Balance.MAP_TYPE_ARCHIPELAGO and int(s.get("ports_built", 0)) >= 3,
		"giant_slayer": won and int(s.get("difficulty", -1)) == Balance.BOT_DIFFICULTY_HARD,
		"peacemaker": int(s.get("truces_made", 0)) >= 3,
		"great_wall": int(s.get("walls_built", 0)) >= 40,
		"veteran": int(lifetime.get("matches", 0)) >= 25,
		"conqueror": int(lifetime.get("crowns", 0)) >= 50,
		"daily_ruler": String(s.get("mode", "")) == MatchSetup.MODE_DAILY,
		"friendly_rivals": bool(s.get("online", false)),
	}
	for id: String in checks.keys():
		if checks[id]:
			out.append(id)
	return out


# --- Daily challenges -----------------------------------------------------------

# The day's challenge ids, the same for everyone on that date.
static func challenges_for(date: String) -> Array[String]:
	var ids: Array = CHALLENGES.keys()
	ids.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash("crown-conquest-challenges-" + date))
	var out: Array[String] = []
	while out.size() < mini(Balance.DAILY_CHALLENGES_PER_DAY, ids.size()):
		var pick: String = ids[rng.randi_range(0, ids.size() - 1)]
		if not out.has(pick):
			out.append(pick)
	return out


# New progress value for one challenge after a match.
static func challenge_progress(id: String, old: float, summary: Dictionary) -> float:
	var c: Array = CHALLENGES[id]
	var key: String = c[1]
	var value: float = 1.0 if key == "played" else float(summary.get(key, 0))
	if key == "won":
		value = 1.0 if bool(summary.get("won", false)) else 0.0
	return maxf(old, value) if c[3] == "best" else old + value


static func challenge_target(id: String) -> float:
	return float(CHALLENGES[id][2])


static func today() -> String:
	return Time.get_date_string_from_system()
