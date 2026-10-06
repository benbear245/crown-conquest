extends Node

# Headless balance simulator. Plays N bot-only matches on the same sim code
# the real game uses, aggregates results against the design's targets table,
# and writes a Markdown report to reports/balance_<date>.md.
#
# Run with:
#   godot --headless --path <project_dir> res://scenes/balance_sim.tscn
# Optional overrides (anywhere on the CLI):
#   --matches 50     --map medium|small|large
#   --type continent|archipelago|highlands|random
#   --mix mixed|easy|normal|hard

const DEFAULT_MATCHES: int = 20
const SAMPLE_LEADER_AT_SEC: float = 180.0


func _ready() -> void:
	var opts := _parse_args(OS.get_cmdline_args())
	print("[balance] Running %d matches on %s %s, %s difficulty..." % [
		opts.matches, _size_label(opts.size), _map_type_label(opts.map_type), opts.mix_label,
	])
	var results := _run_matches(opts)
	var report := _build_report(results, opts)
	var report_path := _save_report(report)
	print(report)
	if report_path != "":
		print("[balance] Report saved to %s" % report_path)
	else:
		push_warning("[balance] Report could not be saved to disk.")
	get_tree().quit()


# --- CLI parsing -------------------------------------------------------------

func _parse_args(args: PackedStringArray) -> Dictionary:
	var opts: Dictionary = {
		"matches": DEFAULT_MATCHES,
		"size": Balance.MAP_SIZE_MEDIUM,
		"map_type": Balance.MAP_TYPE_CONTINENT,
		"mix": _mix_mixed(),
		"mix_label": "Mixed (3E / 3N / 2H pad)",
	}
	for i in range(args.size()):
		var a: String = args[i]
		var nxt: String = args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--matches":
				opts.matches = maxi(1, nxt.to_int())
			"--map":
				opts.size = _size_from_name(nxt)
			"--type":
				opts.map_type = _map_type_from_name(nxt)
			"--mix":
				var pair := _mix_from_name(nxt)
				opts.mix = pair[0]
				opts.mix_label = pair[1]
	return opts


func _size_from_name(label: String) -> int:
	match label.to_lower():
		"small":
			return Balance.MAP_SIZE_SMALL
		"large":
			return Balance.MAP_SIZE_LARGE
		_:
			return Balance.MAP_SIZE_MEDIUM


func _map_type_from_name(label: String) -> int:
	match label.to_lower():
		"archipelago":
			return Balance.MAP_TYPE_ARCHIPELAGO
		"highlands":
			return Balance.MAP_TYPE_HIGHLANDS
		"random":
			return Balance.MAP_TYPE_RANDOM
		_:
			return Balance.MAP_TYPE_CONTINENT


func _mix_from_name(label: String) -> Array:
	match label.to_lower():
		"easy":
			return [[Balance.BOT_DIFFICULTY_EASY], "Easy only"]
		"normal":
			return [[Balance.BOT_DIFFICULTY_NORMAL], "Normal only"]
		"hard":
			return [[Balance.BOT_DIFFICULTY_HARD], "Hard only"]
		_:
			return [_mix_mixed(), "Mixed (3E / 3N / 2H pad)"]


func _mix_mixed() -> Array[int]:
	# Design calls Mixed "3 Easy, 3 Normal, 1 Hard" for 7 bots; the 8th slot
	# gets another Normal so the composition stays close for 8-bot matches.
	return [
		Balance.BOT_DIFFICULTY_EASY, Balance.BOT_DIFFICULTY_EASY, Balance.BOT_DIFFICULTY_EASY,
		Balance.BOT_DIFFICULTY_NORMAL, Balance.BOT_DIFFICULTY_NORMAL, Balance.BOT_DIFFICULTY_NORMAL,
		Balance.BOT_DIFFICULTY_HARD, Balance.BOT_DIFFICULTY_NORMAL,
	]


# --- Match loop --------------------------------------------------------------

func _run_matches(opts: Dictionary) -> Array:
	var results: Array = []
	for i in range(opts.matches):
		var match_seed: int = i + 1
		var sim := Simulation.new()
		sim.headless = true
		sim.start_match(opts.size, opts.map_type, match_seed)
		_convert_all_to_bots(sim, opts.mix)
		var leader_at_3min_id: int = -1
		var sampled: bool = false
		var max_ticks: int = int((Balance.MATCH_TIME_LIMIT_SEC + 60.0) * Balance.TICKS_PER_SECOND)
		var ticks: int = 0
		while sim.state.phase != Balance.PHASE_ENDED and ticks < max_ticks:
			sim.advance_tick()
			ticks += 1
			if not sampled and sim.state.match_time >= SAMPLE_LEADER_AT_SEC:
				sampled = true
				leader_at_3min_id = _leader_id(sim.state)
		var stats := _collect_match_stats(sim, leader_at_3min_id, i + 1, match_seed)
		results.append(stats)
		print("[balance]  Match %d/%d  %s" % [i + 1, opts.matches, _match_summary(stats)])
	return results


func _convert_all_to_bots(sim: Simulation, mix: Array[int]) -> void:
	var state: GameState = sim.state
	for i in range(state.players.size()):
		var p: Player = state.players[i]
		p.is_bot = true
		p.difficulty = mix[i % mix.size()]
		p.personality = state.rng.randi() % 4
		p.think_timer = state.rng.randf_range(0.2, 1.5)


func _leader_id(state: GameState) -> int:
	var best_id: int = -1
	var best_land: int = -1
	for p: Player in state.players:
		if p.land > best_land:
			best_land = p.land
			best_id = p.id
	return best_id


func _collect_match_stats(sim: Simulation, leader_at_3min_id: int, match_number: int, match_seed: int) -> Dictionary:
	var state: GameState = sim.state
	var winner: Player = state.get_player(state.winner_id)
	var total_crowns: int = 0
	for p: Player in state.players:
		total_crowns += p.crowns_captured
	var winner_personality: int = -1
	var winner_difficulty: int = -1
	if winner != null:
		winner_personality = winner.personality
		winner_difficulty = winner.difficulty
	return {
		"match": match_number,
		"seed": match_seed,
		"duration_sec": state.match_time,
		"winner_id": state.winner_id,
		"winner_name": winner.display_name if winner != null else "-",
		"winner_personality": winner_personality,
		"winner_difficulty": winner_difficulty,
		"win_reason": state.win_reason if state.win_reason != "" else "incomplete",
		"leader_at_3min_id": leader_at_3min_id,
		"leader_at_3min_won": leader_at_3min_id > 0 and leader_at_3min_id == state.winner_id,
		"crowns_captured": total_crowns,
		"ended_at_time_limit": state.phase == Balance.PHASE_ENDED and state.match_time >= Balance.MATCH_TIME_LIMIT_SEC - 1.0,
	}


func _match_summary(r: Dictionary) -> String:
	return "%s wins at %s  (%s)" % [r.winner_name, _format_time(r.duration_sec), r.win_reason]


# --- Report ------------------------------------------------------------------

func _build_report(results: Array, opts: Dictionary) -> String:
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
	var median_sec: float = _median(durations)
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
	lines.append("- Map: %s %s" % [_size_label(opts.size), _map_type_label(opts.map_type)])
	lines.append("- Difficulty mix: %s" % opts.mix_label)
	lines.append("")
	lines.append("## Targets")
	lines.append("")
	lines.append("| Check | Target | Actual | Verdict |")
	lines.append("| --- | --- | --- | --- |")
	lines.append("| Median match length | 7-11 min | %s | %s |" % [_format_time(median_sec), _verdict(median_sec >= 420.0 and median_sec <= 660.0)])
	lines.append("| Wins per personality | ≤ 35%% | %.0f%% | %s |" % [max_personality_ratio * 100.0, _verdict(max_personality_ratio <= 0.35)])
	lines.append("| Land leader at 3:00 goes on to win | < 55%% | %.0f%% | %s |" % [leader_ratio * 100.0, _verdict(leader_ratio < 0.55)])
	lines.append("| Matches decided by the 15:00 time limit | < 5%% | %.0f%% | %s |" % [time_limit_ratio * 100.0, _verdict(time_limit_ratio < 0.05)])
	lines.append("| Crowns captured per match | ≥ 5 of 7 | %.1f | %s |" % [avg_crowns, _verdict(avg_crowns >= 5.0)])
	lines.append("| Each building and ability used ≥ 30%% | ≥ 30%% | N/A (Prompts 8-9) | N/A |" % [])
	lines.append("| 1 Hard bot vs 7 Easy bots: Hard wins ≥ 40%% | ≥ 40%% | not run | N/A |" % [])
	lines.append("")
	lines.append("## Per-personality wins")
	lines.append("")
	lines.append("| Personality | Wins | Share |")
	lines.append("| --- | --- | --- |")
	for i in range(personality_wins.size()):
		lines.append("| %s | %d | %.0f%% |" % [_personality_label(i), personality_wins[i], 100.0 * float(personality_wins[i]) / float(maxi(n, 1))])
	lines.append("")
	lines.append("## Per-difficulty wins")
	lines.append("")
	lines.append("| Difficulty | Wins | Share |")
	lines.append("| --- | --- | --- |")
	for i in range(difficulty_wins.size()):
		lines.append("| %s | %d | %.0f%% |" % [_difficulty_label(i), difficulty_wins[i], 100.0 * float(difficulty_wins[i]) / float(maxi(n, 1))])
	lines.append("")
	lines.append("## Suggested next changes")
	lines.append("")
	for s in _suggest(median_sec, personality_wins, leader_ratio, time_limit_ratio, avg_crowns, n):
		lines.append("- %s" % s)
	lines.append("")
	lines.append("## Match log")
	lines.append("")
	lines.append("| # | Seed | Length | Winner | Diff | Personality | How it ended | Leader@3:00 won? | Crowns |")
	lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for r_v in results:
		var r: Dictionary = r_v
		lines.append("| %d | %d | %s | %s | %s | %s | %s | %s | %d |" % [
			r.match, r.seed, _format_time(r.duration_sec), r.winner_name,
			_difficulty_label(r.winner_difficulty), _personality_label(r.winner_personality),
			r.win_reason, ("yes" if r.leader_at_3min_won else "no"), r.crowns_captured,
		])
	return "\n".join(lines)


func _median(values: Array[float]) -> float:
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


func _suggest(median_sec: float, personality_wins: Array[int], leader_ratio: float, time_limit_ratio: float, avg_crowns: float, n: int) -> Array[String]:
	var out: Array[String] = []
	if median_sec > 660.0:
		out.append("Match length median is %s (target 7–11 min). Consider lowering `CROWN_TILE_DEFENSE` or moving `FINAL_SIEGE_START_SEC` earlier." % _format_time(median_sec))
	elif median_sec > 0 and median_sec < 420.0:
		out.append("Match length median is %s (target 7–11 min). Consider raising `CROWN_TILE_DEFENSE` so Crowns don't fall quite so fast." % _format_time(median_sec))
	var max_p: int = 0
	for i in range(1, personality_wins.size()):
		if personality_wins[i] > personality_wins[max_p]:
			max_p = i
	if n > 0 and float(personality_wins[max_p]) / float(n) > 0.35:
		out.append("The %s personality is winning %.0f%% of matches. Raise the cost of its favoured strategy (`FORT_COST_BASE` for Turtle, attack bonuses for Raider, etc.)." % [_personality_label(max_p), 100.0 * float(personality_wins[max_p]) / float(n)])
	if leader_ratio >= 0.55:
		out.append("Land leader at 3:00 wins %.0f%% of matches (target < 55%%). Strengthen `UNDERDOG_GROWTH_BONUS` / `RISING_EMPIRE_ATTACK_DISCOUNT` once Prompt 10 lands." % (leader_ratio * 100.0))
	if time_limit_ratio >= 0.05:
		out.append("%.0f%% of matches hit the 15:00 limit (target < 5%%). Lower `FINAL_SIEGE_CROWN_TILE_DEFENSE` further or drop `FINAL_SIEGE_START_SEC` to force endings." % (time_limit_ratio * 100.0))
	if avg_crowns < 5.0 and n > 0:
		out.append("Average %.1f Crowns captured per match (target ≥ 5). Lower `CROWN_TILE_DEFENSE` or Crown-zone defense so pushes land." % avg_crowns)
	if out.is_empty():
		out.append("All measured targets passed. Re-run with --matches 50 for more stable numbers before committing changes.")
	return out


func _save_report(content: String) -> String:
	var base: String = ProjectSettings.globalize_path("res://")
	var dir: DirAccess = DirAccess.open(base)
	if dir == null:
		return ""
	if not dir.dir_exists("reports"):
		dir.make_dir("reports")
	var date: String = Time.get_date_string_from_system()
	var abs_path: String = base.path_join("reports").path_join("balance_%s.md" % date)
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(content)
	f.close()
	return "res://reports/balance_%s.md" % date


# --- Labels ------------------------------------------------------------------

func _personality_label(p: int) -> String:
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


func _difficulty_label(d: int) -> String:
	match d:
		Balance.BOT_DIFFICULTY_EASY:
			return "Easy"
		Balance.BOT_DIFFICULTY_NORMAL:
			return "Normal"
		Balance.BOT_DIFFICULTY_HARD:
			return "Hard"
		_:
			return "-"


func _size_label(s: int) -> String:
	match s:
		Balance.MAP_SIZE_SMALL:
			return "Small"
		Balance.MAP_SIZE_LARGE:
			return "Large"
		_:
			return "Medium"


func _map_type_label(mt: int) -> String:
	match mt:
		Balance.MAP_TYPE_ARCHIPELAGO:
			return "Archipelago"
		Balance.MAP_TYPE_HIGHLANDS:
			return "Highlands"
		Balance.MAP_TYPE_RANDOM:
			return "Random"
		_:
			return "Continent"


func _verdict(ok: bool) -> String:
	return "PASS" if ok else "FAIL"


func _format_time(seconds: float) -> String:
	var total: int = int(seconds)
	@warning_ignore("integer_division")
	var mm: int = total / 60
	var ss: int = total % 60
	return "%d:%02d" % [mm, ss]
