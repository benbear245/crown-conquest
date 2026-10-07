class_name BalanceReport
extends RefCounted

# Builds the Markdown report for the balance simulator: targets table, wins
# by personality and difficulty, feature usage, suggestions and a match log.

const FEATURES: Array[String] = [
	"Fort", "Fort II", "Barracks", "Port", "Watchtower", "Wall", "Keep 1", "Keep 2", "Keep 3",
	"Swift March", "Crown Shield", "Rally", "Bombard", "Boat", "Crown move",
	"Scout", "Spy", "Sabotage", "Steal plans", "Disinformation", "Truce offer", "Shrine taken",
]


static func usage_shares(results: Array) -> Dictionary:
	var out: Dictionary = {}
	for f: String in FEATURES:
		var used: int = 0
		for r_v in results:
			if int((r_v as Dictionary)["usage"].get(f, 0)) > 0:
				used += 1
		out[f] = float(used) / float(maxi(results.size(), 1))
	return out


static func build(results: Array, opts: Dictionary) -> String:
	var n: int = results.size()
	var durations: Array[float] = []
	var personality_wins: Array[int] = [0, 0, 0, 0]
	var difficulty_wins: Array[int] = [0, 0, 0]
	var leader_wins: int = 0
	var leader_samples: int = 0
	var time_limit_matches: int = 0
	var total_crowns: int = 0
	for r_v in results:
		var r: Dictionary = r_v
		durations.append(r.duration_sec)
		var wp: int = r.winner_personality
		if wp >= 0 and wp < personality_wins.size():
			personality_wins[wp] += 1
		var wd: int = r.winner_difficulty
		if wd >= 0 and wd < difficulty_wins.size():
			difficulty_wins[wd] += 1
		if r.leader_at_3min_id > 0:
			leader_samples += 1
			if r.leader_at_3min_won:
				leader_wins += 1
		if r.ended_at_time_limit:
			time_limit_matches += 1
		total_crowns += int(r.crowns_captured)
	var median_sec: float = median(durations)
	var avg_crowns: float = float(total_crowns) / float(maxi(n, 1))
	var leader_ratio: float = (float(leader_wins) / float(leader_samples)) if leader_samples > 0 else 0.0
	var time_limit_ratio: float = float(time_limit_matches) / float(maxi(n, 1))
	var max_personality_ratio: float = 0.0
	for v in personality_wins:
		max_personality_ratio = maxf(max_personality_ratio, float(v) / float(maxi(n, 1)))

	var lines: Array[String] = []
	lines.append("# Balance report - %s" % Time.get_date_string_from_system())
	lines.append("")
	lines.append("- Matches: %d" % n)
	lines.append("- Map: %s %s" % [size_label(opts.size), map_type_label(opts.map_type)])
	lines.append("- Difficulty mix: %s" % opts.mix_label)
	lines.append("")
	lines.append("## Targets")
	lines.append("")
	lines.append("| Check | Target | Actual | Verdict |")
	lines.append("| --- | --- | --- | --- |")
	lines.append("| Median match length | 7-11 min | %s | %s |" % [format_time(median_sec), verdict(median_sec >= 420.0 and median_sec <= 660.0)])
	lines.append("| Wins per personality | ≤ 35%% | %.0f%% | %s |" % [max_personality_ratio * 100.0, verdict(max_personality_ratio <= 0.35)])
	lines.append("| Land leader at 3:00 goes on to win | < 55%% | %.0f%% | %s |" % [leader_ratio * 100.0, verdict(leader_ratio < 0.55)])
	lines.append("| Matches decided by the 15:00 time limit | < 5%% | %.0f%% | %s |" % [time_limit_ratio * 100.0, verdict(time_limit_ratio < 0.05)])
	lines.append("| Crowns captured per match | ≥ 5 of 7 | %.1f | %s |" % [avg_crowns, verdict(avg_crowns >= 5.0)])
	var usage_share: Dictionary = usage_shares(results)
	var least: String = ""
	for f: String in FEATURES:
		if least == "" or float(usage_share[f]) < float(usage_share[least]):
			least = f
	lines.append("| Each building and ability used ≥ 30%% | ≥ 30%% | lowest: %s %.0f%% | %s |" % [least, 100.0 * float(usage_share[least]), verdict(float(usage_share[least]) >= 0.30)])
	if String(opts.mix_label).begins_with("1 Hard"):
		var hard_ratio: float = float(difficulty_wins[Balance.BOT_DIFFICULTY_HARD]) / float(maxi(n, 1))
		lines.append("| 1 Hard bot vs 7 Easy bots: Hard wins ≥ 40%% | ≥ 40%% | %.0f%% | %s |" % [hard_ratio * 100.0, verdict(hard_ratio >= 0.40)])
	else:
		lines.append("| 1 Hard bot vs 7 Easy bots: Hard wins ≥ 40%% | ≥ 40%% | run with --mix hard1 | N/A |" % [])
	lines.append("")
	lines.append("## Per-personality wins")
	lines.append("")
	lines.append("| Personality | Wins | Share |")
	lines.append("| --- | --- | --- |")
	for i in range(personality_wins.size()):
		lines.append("| %s | %d | %.0f%% |" % [personality_label(i), personality_wins[i], 100.0 * float(personality_wins[i]) / float(maxi(n, 1))])
	lines.append("")
	lines.append("## Per-difficulty wins")
	lines.append("")
	lines.append("| Difficulty | Wins | Share |")
	lines.append("| --- | --- | --- |")
	for i in range(difficulty_wins.size()):
		lines.append("| %s | %d | %.0f%% |" % [difficulty_label(i), difficulty_wins[i], 100.0 * float(difficulty_wins[i]) / float(maxi(n, 1))])
	lines.append("")
	lines.append("## Feature usage (share of matches where any bot used it)")
	lines.append("")
	lines.append("| Feature | Matches | Share |")
	lines.append("| --- | --- | --- |")
	for f: String in FEATURES:
		lines.append("| %s | %d | %.0f%% |" % [f, int(round(float(usage_share[f]) * n)), 100.0 * float(usage_share[f])])
	lines.append("")
	lines.append("## Suggested next changes")
	lines.append("")
	for s in suggest(median_sec, personality_wins, leader_ratio, time_limit_ratio, avg_crowns, n):
		lines.append("- %s" % s)
	lines.append("")
	lines.append("## Match log")
	lines.append("")
	lines.append("| # | Seed | Length | Winner | Diff | Personality | How it ended | Leader@3:00 won? | Crowns |")
	lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for r_v in results:
		var r: Dictionary = r_v
		lines.append("| %d | %d | %s | %s | %s | %s | %s | %s | %d |" % [
			r.match, r.seed, format_time(r.duration_sec), r.winner_name,
			difficulty_label(r.winner_difficulty), personality_label(r.winner_personality),
			r.win_reason, ("yes" if r.leader_at_3min_won else "no"), r.crowns_captured,
		])
	return "\n".join(lines)


static func median(values: Array[float]) -> float:
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


static func suggest(median_sec: float, personality_wins: Array[int], leader_ratio: float, time_limit_ratio: float, avg_crowns: float, n: int) -> Array[String]:
	var out: Array[String] = []
	if median_sec > 660.0:
		out.append("Match length median is %s (target 7–11 min). Consider lowering `CROWN_TILE_DEFENSE` or moving `FINAL_SIEGE_START_SEC` earlier." % format_time(median_sec))
	elif median_sec > 0 and median_sec < 420.0:
		out.append("Match length median is %s (target 7–11 min). Consider raising `CROWN_TILE_DEFENSE` so Crowns don't fall quite so fast." % format_time(median_sec))
	var max_p: int = 0
	for i in range(1, personality_wins.size()):
		if personality_wins[i] > personality_wins[max_p]:
			max_p = i
	if n > 0 and float(personality_wins[max_p]) / float(n) > 0.35:
		out.append("The %s personality is winning %.0f%% of matches. Raise the cost of its favoured strategy (`FORT_COST_BASE` for Turtle, attack bonuses for Raider, etc.)." % [personality_label(max_p), 100.0 * float(personality_wins[max_p]) / float(n)])
	if leader_ratio >= 0.55:
		out.append("Land leader at 3:00 wins %.0f%% of matches (target < 55%%). Strengthen `UNDERDOG_GROWTH_BONUS` / `RISING_EMPIRE_ATTACK_DISCOUNT` once Prompt 10 lands." % (leader_ratio * 100.0))
	if time_limit_ratio >= 0.05:
		out.append("%.0f%% of matches hit the 15:00 limit (target < 5%%). Lower `FINAL_SIEGE_CROWN_TILE_DEFENSE` further or drop `FINAL_SIEGE_START_SEC` to force endings." % (time_limit_ratio * 100.0))
	if avg_crowns < 5.0 and n > 0:
		out.append("Average %.1f Crowns captured per match (target ≥ 5). Lower `CROWN_TILE_DEFENSE` or Crown-zone defense so pushes land." % avg_crowns)
	if out.is_empty():
		out.append("All measured targets passed. Re-run with --matches 50 for more stable numbers before committing changes.")
	return out




static func personality_label(p: int) -> String:
	match p:
		Balance.BOT_PERSONALITY_EXPANDER:
			return "Expander"
		Balance.BOT_PERSONALITY_RAIDER:
			return "Raider"
		Balance.BOT_PERSONALITY_TURTLE:
			return "Turtle"
		Balance.BOT_PERSONALITY_OPPORTUNIST:
			return "Opportunist"
		_:
			return "-"


static func difficulty_label(d: int) -> String:
	match d:
		Balance.BOT_DIFFICULTY_EASY:
			return "Easy"
		Balance.BOT_DIFFICULTY_NORMAL:
			return "Normal"
		Balance.BOT_DIFFICULTY_HARD:
			return "Hard"
		_:
			return "-"


static func size_label(s: int) -> String:
	match s:
		Balance.MAP_SIZE_SMALL:
			return "Small"
		Balance.MAP_SIZE_LARGE:
			return "Large"
		_:
			return "Medium"


static func map_type_label(mt: int) -> String:
	match mt:
		Balance.MAP_TYPE_ARCHIPELAGO:
			return "Archipelago"
		Balance.MAP_TYPE_HIGHLANDS:
			return "Highlands"
		Balance.MAP_TYPE_RANDOM:
			return "Random"
		_:
			return "Continent"


static func verdict(ok: bool) -> String:
	return "PASS" if ok else "FAIL"


static func format_time(seconds: float) -> String:
	var total: int = int(seconds)
	@warning_ignore("integer_division")
	var mm: int = total / 60
	var ss: int = total % 60
	return "%d:%02d" % [mm, ss]
