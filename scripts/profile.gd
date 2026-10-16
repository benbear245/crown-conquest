extends Node

# The player's progress (autoload "Profile"): XP, achievements, daily
# challenges, Daily Challenge scores, lifetime stats, chosen looks and the
# last match setup. Saved to user://profile.json by writing a temp file and
# renaming it, so a crash can't wipe progress.

signal changed

const PATH: String = "user://profile.json"
const TMP_PATH: String = "user://profile.json.tmp"
const SAVE_VERSION: int = 1

var data: Dictionary = {}


func _ready() -> void:
	load_profile()


func _defaults() -> Dictionary:
	return {
		"version": SAVE_VERSION, "xp": 0, "tutorial_done": false,
		"stats": {"matches": 0, "wins": 0, "crowns": 0, "best_peak_pct": 0.0, "fastest_win": 0.0, "online_matches": 0},
		"achievements": {},
		"look": {"color": 0, "pattern": 0, "crown": 0, "title": 0, "victory": 0},
		"last_setup": MatchSetup.new().to_dict(),
		"daily": {"date": "", "progress": {}, "claimed": []},
		"daily_best": {},
	}


func load_profile() -> void:
	data = _defaults()
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Profile file was unreadable; starting fresh.")
		return
	# Merge onto defaults so saves from older versions keep working.
	for k: String in (parsed as Dictionary).keys():
		if data.has(k) and typeof(data[k]) == TYPE_DICTIONARY and typeof(parsed[k]) == TYPE_DICTIONARY:
			(data[k] as Dictionary).merge(parsed[k], true)
		else:
			data[k] = parsed[k]
	_refresh_daily()


func save() -> void:
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Profile could not be saved.")
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.rename(TMP_PATH.get_file(), PATH.get_file())
	changed.emit()


# --- Reading ------------------------------------------------------------------------

func level_info() -> Dictionary:
	return Progression.level_info(int(data["xp"]))


func stats() -> Dictionary:
	return data["stats"]


func has_achievement(id: String) -> bool:
	return (data["achievements"] as Dictionary).has(id)


func is_unlocked(cat: String, idx: int) -> bool:
	var lvl: int = Cosmetics.unlock_level(cat, idx)
	if lvl > 0:
		return int(level_info()["level"]) >= lvl
	# Titles not on the level table come from achievements.
	if cat == Cosmetics.CAT_TITLE:
		for id: String in Progression.ACHIEVEMENTS.keys():
			if int(Progression.ACHIEVEMENTS[id][2]) == idx and has_achievement(id):
				return true
	return false


func look() -> Dictionary:
	var out: Dictionary = {}
	for cat in Cosmetics.CATEGORIES:
		var idx: int = int((data["look"] as Dictionary).get(cat, 0))
		out[cat] = idx if is_unlocked(cat, idx) else 0
	return out


func set_look(cat: String, idx: int) -> void:
	if is_unlocked(cat, idx):
		(data["look"] as Dictionary)[cat] = idx
		save()


func last_setup() -> MatchSetup:
	return MatchSetup.from_dict(data["last_setup"]).clamped()


func remember_setup(s: MatchSetup) -> void:
	data["last_setup"] = s.to_dict()
	save()


func daily_challenges() -> Array:
	_refresh_daily()
	var out: Array = []
	var d: Dictionary = data["daily"]
	for id: String in Progression.challenges_for(String(d["date"])):
		out.append({
			"id": id, "text": Progression.CHALLENGES[id][0],
			"progress": float((d["progress"] as Dictionary).get(id, 0.0)),
			"target": Progression.challenge_target(id),
			"done": (d["claimed"] as Array).has(id),
		})
	return out


func daily_best(date: String) -> int:
	return int((data["daily_best"] as Dictionary).get(date, -1))


func _refresh_daily() -> void:
	var today: String = Progression.today()
	if String((data["daily"] as Dictionary).get("date", "")) != today:
		data["daily"] = {"date": today, "progress": {}, "claimed": []}


# --- Recording a match ----------------------------------------------------------------

# Applies one finished match and returns what to show on the recap:
# {xp_lines, xp_total, old_level, new_level, unlocks, achievements, challenges,
#  daily_score, daily_best}.
func record_match(summary: Dictionary) -> Dictionary:
	_refresh_daily()
	var st: Dictionary = data["stats"]
	var won: bool = bool(summary.get("won", false))
	st["matches"] = int(st["matches"]) + 1
	st["crowns"] = int(st["crowns"]) + int(summary.get("crowns", 0))
	st["best_peak_pct"] = maxf(float(st["best_peak_pct"]), float(summary.get("peak_land_pct", 0.0)))
	if bool(summary.get("online", false)):
		st["online_matches"] = int(st["online_matches"]) + 1
	if won:
		st["wins"] = int(st["wins"]) + 1
		var t: float = float(summary.get("time", 0.0))
		if float(st["fastest_win"]) <= 0.0 or t < float(st["fastest_win"]):
			st["fastest_win"] = t
	var xp_lines: Array = Progression.match_xp(summary)
	# Daily challenges.
	var done_now: Array = []
	var d: Dictionary = data["daily"]
	for id: String in Progression.challenges_for(String(d["date"])):
		if (d["claimed"] as Array).has(id):
			continue
		var p: float = Progression.challenge_progress(id, float((d["progress"] as Dictionary).get(id, 0.0)), summary)
		(d["progress"] as Dictionary)[id] = p
		if p >= Progression.challenge_target(id):
			(d["claimed"] as Array).append(id)
			done_now.append(Progression.CHALLENGES[id][0])
			xp_lines.append(["Daily challenge: %s" % Progression.CHALLENGES[id][0], Balance.XP_PER_DAILY_CHALLENGE])
	# Achievements.
	var new_ach: Array = []
	for id: String in Progression.earned_achievements(summary, st):
		if not has_achievement(id):
			new_ach.append(id)
	for id: String in new_ach:
		_grant_achievement(id, xp_lines)
	# Daily Challenge map score.
	var dscore: int = -1
	var dbest: int = -1
	if String(summary.get("mode", "")) == MatchSetup.MODE_DAILY:
		dscore = Progression.daily_score(summary)
		dbest = maxi(daily_best(String(d["date"])), dscore)
		(data["daily_best"] as Dictionary)[String(d["date"])] = dbest
	return _apply_xp(xp_lines, {"achievements": new_ach, "challenges": done_now,
		"daily_score": dscore, "daily_best": dbest})


func skip_tutorial() -> void:
	data["tutorial_done"] = true
	save()


# The tutorial gives a one-time XP reward and the Graduate achievement.
func complete_tutorial() -> Dictionary:
	var lines: Array = []
	if not bool(data["tutorial_done"]):
		data["tutorial_done"] = true
		lines.append(["Finished the tutorial", Balance.XP_TUTORIAL])
	var new_ach: Array = []
	if not has_achievement("graduate"):
		new_ach.append("graduate")
		_grant_achievement("graduate", lines)
	return _apply_xp(lines, {"achievements": new_ach, "challenges": [], "daily_score": -1, "daily_best": -1})


func _grant_achievement(id: String, xp_lines: Array) -> void:
	(data["achievements"] as Dictionary)[id] = Progression.today()
	xp_lines.append(["Achievement: %s" % Progression.ACHIEVEMENTS[id][0], Balance.XP_PER_ACHIEVEMENT])


func _apply_xp(xp_lines: Array, result: Dictionary) -> Dictionary:
	var total: int = 0
	for l: Array in xp_lines:
		total += int(l[1])
	var before: Dictionary = level_info()
	data["xp"] = int(data["xp"]) + total
	var after: Dictionary = level_info()
	var unlocks: Array = []
	for lvl in range(int(before["level"]) + 1, int(after["level"]) + 1):
		for pair: Array in Cosmetics.LEVEL_UNLOCKS.get(lvl, []):
			unlocks.append("%s: %s" % [Cosmetics.category_label(pair[0]), Cosmetics.label(pair[0], int(pair[1]))])
	for id: String in result["achievements"]:
		var title: int = int(Progression.ACHIEVEMENTS[id][2])
		if title > 0:
			unlocks.append("Title: %s" % Cosmetics.label(Cosmetics.CAT_TITLE, title))
	save()
	result.merge({"xp_lines": xp_lines, "xp_total": total, "old_level": before, "new_level": after,
		"unlocks": unlocks, "xp_before": int(data["xp"]) - total})
	return result
