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
#   --mix mixed|easy|normal|hard|hard1   (hard1 = 1 Hard bot vs 7 Easy)

const DEFAULT_MATCHES: int = 20
const SAMPLE_LEADER_AT_SEC: float = 180.0


func _ready() -> void:
	var opts := _parse_args(OS.get_cmdline_args())
	print("[balance] Running %d matches on %s %s, %s difficulty..." % [
		opts.matches, BalanceReport.size_label(opts.size), BalanceReport.map_type_label(opts.map_type), opts.mix_label,
	])
	var results := _run_matches(opts)
	var report := BalanceReport.build(results, opts)
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
		"hard1":
			var mix: Array[int] = [Balance.BOT_DIFFICULTY_HARD]
			for _i in range(7):
				mix.append(Balance.BOT_DIFFICULTY_EASY)
			return [mix, "1 Hard vs 7 Easy"]
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
		"usage": state.usage.duplicate(),
		"ended_at_time_limit": state.phase == Balance.PHASE_ENDED and state.match_time >= Balance.MATCH_TIME_LIMIT_SEC - 1.0,
	}


func _match_summary(r: Dictionary) -> String:
	return "%s wins at %s  (%s)" % [r.winner_name, BalanceReport.format_time(r.duration_sec), r.win_reason]


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
