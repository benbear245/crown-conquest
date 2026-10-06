extends Node

# Everything the game remembers between sessions (autoload "SaveData"): XP,
# stats, achievements, cosmetics and Daily Challenge scores. Saved to user://save.json
# safely: written to a temp file, read back to check it, then renamed over
# the old save, so a crash mid-write can't wipe progress.

signal saved

const PATH: String = "user://save.json"
const TMP_PATH: String = "user://save.json.tmp"
const VERSION: int = 1

var data: Dictionary = {}


func _ready() -> void:
	load_save()


func defaults() -> Dictionary:
	return {
		"version": VERSION,
		"profile": {"xp": 0},
		"stats": {
			"matches": 0, "wins": 0, "crowns": 0, "fastest_win_sec": -1.0, "best_peak_pct": 0.0,
			"by_mode": {"skirmish": [0, 0], "teams": [0, 0], "daily": [0, 0]},   # [played, wins]
		},
		"achievements": {},        # id -> unix time earned
		"cosmetics": {"color": 0, "pattern": 0, "crown": 0, "title": "Squire", "effect": 1},
		"daily": {"best_by_date": {}, "best_ever": 0, "played": 0},
	}


func load_save() -> void:
	var loaded: Variant = _read_json(PATH)
	if loaded == null:
		loaded = _read_json(TMP_PATH)   # crashed between write and rename
	data = defaults()
	if loaded is Dictionary:
		_merge(data, loaded)


func save() -> bool:
	var text: String = JSON.stringify(data, "\t")
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveData: can't write %s" % TMP_PATH)
		return false
	f.store_string(text)
	f.close()
	if not (_read_json(TMP_PATH) is Dictionary):
		push_warning("SaveData: temp save didn't read back; keeping the old save")
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.file_exists(PATH.get_file()):
		dir.remove(PATH.get_file())
	if dir.rename(TMP_PATH.get_file(), PATH.get_file()) != OK:
		push_warning("SaveData: rename failed; the temp save is kept")
		return false
	saved.emit()
	return true


# --- Daily Challenge -----------------------------------------------------------

func daily_best(date: String) -> int:
	return int((data.daily.best_by_date as Dictionary).get(date, -1))


func daily_best_ever() -> int:
	return int(data.daily.best_ever)


# Records a Daily score. Returns true if it's a new best for that day.
func submit_daily(date: String, score: int) -> bool:
	var by_date: Dictionary = data.daily.best_by_date
	var is_best: bool = score > int(by_date.get(date, -1))
	if is_best:
		by_date[date] = score
	data.daily.best_ever = maxi(int(data.daily.best_ever), score)
	data.daily.played = int(data.daily.played) + 1
	save()
	return is_best


# --- Progression -----------------------------------------------------------------

func xp() -> int:
	return int(data.profile.xp)


func level() -> int:
	return int(Progression.level_info(xp()).level)


func has_achievement(id: String) -> bool:
	return (data.achievements as Dictionary).has(id)


# Records an achievement. Returns true if it's new.
func unlock_achievement(id: String) -> bool:
	if has_achievement(id) or Progression.achievement(id).is_empty():
		return false
	data.achievements[id] = int(Time.get_unix_time_from_system())
	save()
	return true


# Adds a finished match: XP, stats, achievements. Returns a summary for the
# end screen: {xp, lines, old_xp, new_xp, old_level, new_level, unlocks,
# new_achievements}.
func record_match(result: Dictionary) -> Dictionary:
	var gained: Dictionary = Progression.match_xp(result)
	var old_xp: int = xp()
	var old_level: int = level()
	data.profile.xp = old_xp + int(gained.total)
	var new_level: int = level()
	var st: Dictionary = data.stats
	var won: bool = bool(result.won)
	st.matches = int(st.matches) + 1
	st.wins = int(st.wins) + (1 if won else 0)
	st.crowns = int(st.crowns) + int(result.crowns)
	st.best_peak_pct = maxf(float(st.best_peak_pct), float(result.peak_pct))
	if won and (float(st.fastest_win_sec) < 0.0 or float(result.duration_sec) < float(st.fastest_win_sec)):
		st.fastest_win_sec = float(result.duration_sec)
	var mode_key: String = ["skirmish", "teams", "daily", "skirmish"][int(result.mode)]
	var pair: Array = st.by_mode.get(mode_key, [0, 0])
	st.by_mode[mode_key] = [int(pair[0]) + 1, int(pair[1]) + (1 if won else 0)]
	var fresh: Array[String] = []
	for id: String in Progression.earned(result):
		if not has_achievement(id):
			data.achievements[id] = int(Time.get_unix_time_from_system())
			fresh.append(id)
	var unlocks: Array[String] = []
	for lvl in range(old_level + 1, new_level + 1):
		unlocks.append_array(Progression.unlocks_at(lvl))
	save()
	return {
		"xp": int(gained.total), "lines": gained.lines, "old_xp": old_xp, "new_xp": xp(),
		"old_level": old_level, "new_level": new_level, "unlocks": unlocks, "new_achievements": fresh,
	}


# --- Cosmetics -------------------------------------------------------------------

func cosmetic(key: String) -> Variant:
	return data.cosmetics.get(key)


func set_cosmetic(key: String, value: Variant) -> void:
	data.cosmetics[key] = value
	save()


func color_unlocked(i: int) -> bool:
	return level() >= Progression.color_level(i)


func pattern_unlocked(i: int) -> bool:
	return level() >= Progression.pattern_level(i)


func crown_unlocked(i: int) -> bool:
	return level() >= Progression.crown_level(i)


func effect_unlocked(i: int) -> bool:
	return level() >= Progression.effect_level(i)


# Every title you can pick: by level, then from achievements.
func titles() -> Array[String]:
	var out: Array[String] = []
	for t: Array in Progression.LEVEL_TITLES:
		if level() >= int(t[0]):
			out.append(str(t[1]))
	for a: Dictionary in Progression.ACHIEVEMENTS:
		if has_achievement(a.id):
			out.append(str(a.title))
	return out


# The territory colour you picked, or null for the normal one.
func custom_color() -> Variant:
	var i: int = int(cosmetic("color"))
	if i <= 0 or i >= Progression.COLORS.size() or not color_unlocked(i):
		return null
	return Progression.COLORS[i]


# --- Helpers -------------------------------------------------------------------

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		return null   # corrupt: treated as missing (no error spam)
	return json.data if json.data is Dictionary else null


# Copies saved values over the defaults, keeping new default keys that an
# older save doesn't have yet.
static func _merge(into: Dictionary, from: Dictionary) -> void:
	for k: Variant in from.keys():
		if into.has(k) and into[k] is Dictionary and from[k] is Dictionary:
			_merge(into[k], from[k])
		else:
			into[k] = from[k]
