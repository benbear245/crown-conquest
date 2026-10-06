class_name BalanceReport
extends RefCounted

# Turns balance-simulator results into the Markdown report: the design's
# targets table with PASS / FAIL, wins by personality and difficulty,
# building/ability usage, suggestions and a per-match log.

const PERSONALITIES: Array[String] = ["Expander", "Raider", "Turtle", "Opportunist"]
const DIFFICULTIES: Array[String] = ["Easy", "Normal", "Hard"]
# Usage keys recorded by the simulator: "b<building type>", "a<ability id>".
const USAGE_ITEMS: Array[Array] = [
	["b0", "Fort"], ["b100", "Wall"], ["b2", "Barracks"], ["b3", "Port"],
	["a0", "Swift March"], ["a1", "Crown Shield"], ["a2", "Rally"], ["a3", "Bombard"],
]
const USAGE_INFO_ITEMS: Array[Array] = [["b1", "Fort II upgrade"], ["boat", "Boat launched"], ["keep", "Keep upgrade"]]
const USAGE_TARGET: float = 0.30


static func build(results: Array, hard_results: Array, opts: Dictionary) -> String:
	var n: int = results.size()
	var durations: Array[float] = []
	var personality_wins: Array[int] = [0, 0, 0, 0]
	var difficulty_wins: Array[int] = [0, 0, 0]
	var leader_wins: int = 0
	var leader_samples: int = 0
	var time_limit: int = 0
	var crowns: int = 0
	var wall_ms: float = 0.0
	var truces: int = 0
	var truces_broken: int = 0
	var usage: Dictionary = {}
	for r: Dictionary in results:
		durations.append(float(r.duration_sec))
		var wp: int = int(r.winner_personality)
		if wp >= 0 and wp < 4:
			personality_wins[wp] += 1
		var wd: int = int(r.winner_difficulty)
		if wd >= 0 and wd < 3:
			difficulty_wins[wd] += 1
		if int(r.leader_at_3min_id) > 0:
			leader_samples += 1
			if bool(r.leader_at_3min_won):
				leader_wins += 1
		if bool(r.ended_at_time_limit):
			time_limit += 1
		crowns += int(r.crowns_captured)
		wall_ms += float(r.get("wall_ms", 0))
		truces += int(r.get("truces", 0))
		truces_broken += int(r.get("truces_broken", 0))
		for k: Variant in r.get("used", []):
			usage[str(k)] = int(usage.get(str(k), 0)) + 1
	var nf: float = float(maxi(n, 1))
	var median_sec: float = _median(durations)
	var avg_crowns: float = float(crowns) / nf
	var leader_ratio: float = float(leader_wins) / float(leader_samples) if leader_samples > 0 else 0.0
	var time_ratio: float = float(time_limit) / nf
	var max_p: int = 0
	for i in range(4):
		if personality_wins[i] > personality_wins[max_p]:
			max_p = i
	var max_p_ratio: float = float(personality_wins[max_p]) / nf
	var least_used: String = ""
	var least_ratio: float = 1.0
	for item: Array in USAGE_ITEMS:
		var ratio: float = float(usage.get(item[0], 0)) / nf
		if ratio < least_ratio:
			least_ratio = ratio
			least_used = item[1]
	var hard_wins: int = 0
	for r: Dictionary in hard_results:
		if int(r.winner_difficulty) == Balance.BOT_DIFFICULTY_HARD:
			hard_wins += 1
	var hard_ratio: float = float(hard_wins) / float(maxi(hard_results.size(), 1))

	var L: Array[String] = []
	L.append("# Balance report - %s" % Time.get_date_string_from_system())
	L.append("")
	L.append("- Matches: %d (seeds %s)" % [n, _seed_range(results)])
	L.append("- Map: %s %s, %d bots" % [size_label(opts.size), map_type_label(opts.map_type), MapGen.players_for_size(opts.size)])
	L.append("- Difficulty mix: %s" % opts.mix_label)
	L.append("- Simulator speed: %.1f s of wall time per match on average" % (wall_ms / nf / 1000.0))
	L.append("")
	L.append("## Targets")
	L.append("")
	L.append("| Check | Target | Actual | Verdict |")
	L.append("| --- | --- | --- | --- |")
	L.append("| Median match length | 7-11 min | %s | %s |" % [GameState.format_time(median_sec), _v(median_sec >= 420.0 and median_sec <= 660.0)])
	L.append("| Wins per personality | No personality above 35%% | %s %.0f%% | %s |" % [PERSONALITIES[max_p], max_p_ratio * 100.0, _v(max_p_ratio <= 0.35)])
	L.append("| Land leader at 3:00 goes on to win | Under 55%% | %.0f%% | %s |" % [leader_ratio * 100.0, _v(leader_ratio < 0.55)])
	L.append("| Matches decided by the 15:00 time limit | Under 5%% | %.0f%% | %s |" % [time_ratio * 100.0, _v(time_ratio < 0.05)])
	L.append("| Crowns captured per match | At least 5 of 7 | %.1f | %s |" % [avg_crowns, _v(avg_crowns >= 5.0)])
	L.append("| Each building and ability used | In at least 30%% of matches | lowest: %s %.0f%% | %s |" % [least_used, least_ratio * 100.0, _v(least_ratio >= USAGE_TARGET)])
	if hard_results.is_empty():
		L.append("| 1 Hard bot vs 7 Easy bots | Hard wins at least 40%% | not run (use --hard-check N) | N/A |")
	else:
		L.append("| 1 Hard bot vs 7 Easy bots | Hard wins at least 40%% | %.0f%% of %d | %s |" % [hard_ratio * 100.0, hard_results.size(), _v(hard_ratio >= 0.40)])
	L.append("")
	L.append("## Wins by personality")
	L.append("")
	L.append("| Personality | Wins | Share |")
	L.append("| --- | --- | --- |")
	for i in range(4):
		L.append("| %s | %d | %.0f%% |" % [PERSONALITIES[i], personality_wins[i], 100.0 * float(personality_wins[i]) / nf])
	L.append("")
	L.append("## Wins by difficulty")
	L.append("")
	L.append("| Difficulty | Wins | Share |")
	L.append("| --- | --- | --- |")
	for i in range(3):
		L.append("| %s | %d | %.0f%% |" % [DIFFICULTIES[i], difficulty_wins[i], 100.0 * float(difficulty_wins[i]) / nf])
	L.append("")
	L.append("## Building and ability use (share of matches where any bot used it)")
	L.append("")
	L.append("| Item | Matches | Share | Target 30% |")
	L.append("| --- | --- | --- | --- |")
	for item: Array in USAGE_ITEMS:
		var c: int = int(usage.get(item[0], 0))
		L.append("| %s | %d | %.0f%% | %s |" % [item[1], c, 100.0 * float(c) / nf, _v(float(c) / nf >= USAGE_TARGET)])
	for item: Array in USAGE_INFO_ITEMS:
		var c2: int = int(usage.get(item[0], 0))
		L.append("| %s | %d | %.0f%% | (info) |" % [item[1], c2, 100.0 * float(c2) / nf])
	L.append("")
	L.append("Truces per match: %.1f made, %.1f broken." % [float(truces) / nf, float(truces_broken) / nf])
	L.append("")
	L.append("## Suggested next changes")
	L.append("")
	for s: String in _suggest(median_sec, max_p, max_p_ratio, leader_ratio, time_ratio, avg_crowns, least_used, least_ratio):
		L.append("- %s" % s)
	L.append("")
	L.append("## Match log")
	L.append("")
	L.append("| # | Seed | Length | Winner | Diff | Personality | How it ended | Leader@3:00 won? | Crowns |")
	L.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for r: Dictionary in results:
		L.append("| %d | %d | %s | %s | %s | %s | %s | %s | %d |" % [
			int(r.match), int(r.seed), GameState.format_time(float(r.duration_sec)), r.winner_name,
			_label(DIFFICULTIES, int(r.winner_difficulty)), _label(PERSONALITIES, int(r.winner_personality)),
			r.win_reason, ("yes" if bool(r.leader_at_3min_won) else "no"), int(r.crowns_captured)])
	return "\n".join(L)


static func _suggest(median_sec: float, max_p: int, max_p_ratio: float, leader_ratio: float,
		time_ratio: float, avg_crowns: float, least_used: String, least_ratio: float) -> Array[String]:
	var out: Array[String] = []
	if median_sec > 660.0:
		out.append("Median length %s is over 11 min: lower Crown defense (`CROWN_TILE_DEFENSE` / `KEEP_CROWN_TILE_DEF`) or start Final Siege earlier (`FINAL_SIEGE_START_SEC`)." % GameState.format_time(median_sec))
	elif median_sec < 420.0:
		out.append("Median length %s is under 7 min: raise Crown defense." % GameState.format_time(median_sec))
	if max_p_ratio > 0.35:
		out.append("%s wins %.0f%%: make its favourite strategy cost more." % [PERSONALITIES[max_p], max_p_ratio * 100.0])
	if leader_ratio >= 0.55:
		out.append("The 3:00 land leader wins %.0f%%: strengthen Underdog / Rising Empire." % (leader_ratio * 100.0))
	if time_ratio >= 0.05:
		out.append("%.0f%% of matches hit 15:00: weaken Crowns in Final Siege (`FINAL_SIEGE_CROWN_TILE_DEFENSE`)." % (time_ratio * 100.0))
	if avg_crowns < 5.0:
		out.append("Only %.1f Crowns fall per match: lower Crown or Fort defense." % avg_crowns)
	if least_ratio < USAGE_TARGET:
		out.append("%s is used in only %.0f%% of matches: make it cheaper or stronger (or teach the bots to use it)." % [least_used, least_ratio * 100.0])
	if out.is_empty():
		out.append("All measured targets pass.")
	return out


static func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	@warning_ignore("integer_division")
	var mid: int = n / 2
	if n % 2 == 0:
		return (sorted[mid - 1] + sorted[mid]) * 0.5
	return sorted[mid]


static func _seed_range(results: Array) -> String:
	if results.is_empty():
		return "-"
	return "%d-%d" % [int(results[0].seed), int(results[results.size() - 1].seed)]


static func _label(labels: Array[String], i: int) -> String:
	return labels[i] if i >= 0 and i < labels.size() else "-"


static func _v(ok: bool) -> String:
	return "PASS" if ok else "FAIL"


static func size_label(s: int) -> String:
	match s:
		Balance.MAP_SIZE_SMALL:
			return "Small"
		Balance.MAP_SIZE_LARGE:
			return "Large"
	return "Medium"


static func map_type_label(mt: int) -> String:
	match mt:
		Balance.MAP_TYPE_ARCHIPELAGO:
			return "Archipelago"
		Balance.MAP_TYPE_HIGHLANDS:
			return "Highlands"
		Balance.MAP_TYPE_RANDOM:
			return "Random"
	return "Continent"
