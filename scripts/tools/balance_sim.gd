extends Node

# Headless balance simulator. Plays N bot-only matches on the same sim code
# the real game uses, compares the results with the design's targets table,
# and writes a Markdown report to reports/balance_<date>.md.
#
# Run with:
#   godot --headless --path <project_dir> res://scenes/balance_sim.tscn
# Optional overrides (anywhere on the CLI):
#   --matches 50     --map medium|small|large
#   --type continent|archipelago|highlands|random
#   --mix mixed|easy|normal|hard|hard1   (hard1 = 1 Hard bot vs 7 Easy)
#   --seed N         first match seed (default 1; match i uses seed N + i)
#   --hard-check N   also play N "1 Hard vs 7 Easy" matches for that target row
#   --tag NAME       save reports/balance_<date>_<NAME>.md instead
#   --json PATH      also save the raw per-match results as JSON
#   --merge A,B,...  build one report from several --json files (no matches run)
#   --jobs N         split the matches over N Godot processes (one per CPU
#                    core is a good choice); results are identical, just faster

const DEFAULT_MATCHES: int = 20
const SAMPLE_LEADER_AT_SEC: float = 180.0


func _ready() -> void:
	var opts: Dictionary = _parse_args(OS.get_cmdline_args())
	var results: Array = []
	var hard_results: Array = []
	if opts.jobs > 1 and opts.merge == "":
		opts.merge = await _run_jobs(opts)
	if opts.merge != "":
		for path: String in opts.merge.split(","):
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path.strip_edges()))
			results.append_array(data.get("results", []))
			hard_results.append_array(data.get("hard_results", []))
		results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.seed) < int(b.seed))
		for i in range(results.size()):
			results[i]["match"] = i + 1
	else:
		print("[balance] Running %d matches on %s %s, %s..." % [
			opts.matches, BalanceReport.size_label(opts.size), BalanceReport.map_type_label(opts.map_type), opts.mix_label])
		results = _run_matches(opts, opts.matches, opts.first_seed, opts.mix)
		if opts.hard_check > 0:
			print("[balance] Running %d '1 Hard vs 7 Easy' matches..." % opts.hard_check)
			var hard_seed: int = opts.hard_seed if opts.hard_seed >= 0 else opts.first_seed + 100000
			hard_results = _run_matches(opts, opts.hard_check, hard_seed, _mix_hard1())
	if opts.json != "":
		var f: FileAccess = FileAccess.open(opts.json, FileAccess.WRITE)
		f.store_string(JSON.stringify({"results": results, "hard_results": hard_results}))
		f.close()
	if opts.no_report:
		get_tree().quit()
		return
	var report: String = BalanceReport.build(results, hard_results, opts)
	var report_path: String = _save_report(report, opts.tag)
	print(report)
	print("[balance] Report saved to %s" % report_path if report_path != "" else "[balance] Report could not be saved.")
	get_tree().quit()


# --- CLI parsing -------------------------------------------------------------

func _parse_args(args: PackedStringArray) -> Dictionary:
	var opts: Dictionary = {
		"matches": DEFAULT_MATCHES,
		"size": Balance.MAP_SIZE_MEDIUM,
		"map_type": Balance.MAP_TYPE_CONTINENT,
		"mix": _mix_mixed(),
		"mix_label": "Mixed (3 Easy / 3 Normal / 1 Hard + 1 Normal)",
		"first_seed": 1,
		"hard_check": 0,
		"tag": "",
		"json": "",
		"merge": "",
		"jobs": 1,
		"mix_name": "mixed",
		"hard_seed": -1,
		"no_report": false,
	}
	for i in range(args.size()):
		var nxt: String = args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--matches":
				opts.matches = maxi(1, nxt.to_int())
			"--map":
				opts.size = _size_from_name(nxt)
			"--type":
				opts.map_type = _map_type_from_name(nxt)
			"--mix":
				var pair: Array = _mix_from_name(nxt)
				opts.mix = pair[0]
				opts.mix_label = pair[1]
				opts.mix_name = nxt.to_lower()
			"--seed":
				opts.first_seed = nxt.to_int()
			"--hard-seed":
				opts.hard_seed = nxt.to_int()
			"--no-report":
				opts.no_report = true
			"--hard-check":
				opts.hard_check = maxi(0, nxt.to_int())
			"--tag":
				opts.tag = nxt
			"--json":
				opts.json = nxt
			"--merge":
				opts.merge = nxt
			"--jobs":
				opts.jobs = clampi(nxt.to_int(), 1, 32)
	return opts


func _size_from_name(label: String) -> int:
	match label.to_lower():
		"small":
			return Balance.MAP_SIZE_SMALL
		"large":
			return Balance.MAP_SIZE_LARGE
	return Balance.MAP_SIZE_MEDIUM


func _map_type_from_name(label: String) -> int:
	match label.to_lower():
		"archipelago":
			return Balance.MAP_TYPE_ARCHIPELAGO
		"highlands":
			return Balance.MAP_TYPE_HIGHLANDS
		"random":
			return Balance.MAP_TYPE_RANDOM
	return Balance.MAP_TYPE_CONTINENT


func _mix_from_name(label: String) -> Array:
	var single: Array[int] = []
	match label.to_lower():
		"easy":
			single.append(Balance.BOT_DIFFICULTY_EASY)
			return [single, "Easy only"]
		"normal":
			single.append(Balance.BOT_DIFFICULTY_NORMAL)
			return [single, "Normal only"]
		"hard":
			single.append(Balance.BOT_DIFFICULTY_HARD)
			return [single, "Hard only"]
		"hard1":
			return [_mix_hard1(), "1 Hard vs 7 Easy"]
	return [_mix_mixed(), "Mixed (3 Easy / 3 Normal / 1 Hard + 1 Normal)"]


func _mix_mixed() -> Array[int]:
	# Design: Mixed is "3 Easy, 3 Normal, 1 Hard" for 7 bots; the 8th slot
	# gets another Normal so 8-bot matches stay close to that mix.
	return [
		Balance.BOT_DIFFICULTY_EASY, Balance.BOT_DIFFICULTY_EASY, Balance.BOT_DIFFICULTY_EASY,
		Balance.BOT_DIFFICULTY_NORMAL, Balance.BOT_DIFFICULTY_NORMAL, Balance.BOT_DIFFICULTY_NORMAL,
		Balance.BOT_DIFFICULTY_HARD, Balance.BOT_DIFFICULTY_NORMAL,
	]


func _mix_hard1() -> Array[int]:
	var arr: Array[int] = [Balance.BOT_DIFFICULTY_HARD]
	for _i in range(7):
		arr.append(Balance.BOT_DIFFICULTY_EASY)
	return arr


# --- Parallel jobs -------------------------------------------------------------

# Starts N child simulators on consecutive seed ranges, waits for them, and
# returns their JSON result files (comma separated) for merging.
func _run_jobs(opts: Dictionary) -> String:
	var jobs: int = mini(opts.jobs, opts.matches)
	var tmp_dir: String = OS.get_user_data_dir()
	var files: PackedStringArray = PackedStringArray()
	var pids: Array[int] = []
	var next_seed: int = opts.first_seed
	var left: int = opts.matches
	var hard_left: int = opts.hard_check
	print("[balance] Splitting %d matches over %d processes..." % [opts.matches, jobs])
	for j in range(jobs):
		@warning_ignore("integer_division")
		var count: int = left / (jobs - j)
		@warning_ignore("integer_division")
		var hard_count: int = hard_left / (jobs - j)
		var path: String = tmp_dir.path_join("balance_part_%d_%d.json" % [OS.get_process_id(), j])
		var args: PackedStringArray = PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"res://scenes/balance_sim.tscn", "--matches", str(count), "--seed", str(next_seed),
			"--map", BalanceReport.size_label(opts.size).to_lower(), "--type", BalanceReport.map_type_label(opts.map_type).to_lower(),
			"--mix", opts.mix_name, "--json", path, "--no-report"])
		if hard_count > 0:
			args.append_array(PackedStringArray(["--hard-check", str(hard_count), "--hard-seed", str(opts.first_seed + 100000 + opts.hard_check - hard_left)]))
		pids.append(OS.create_process(OS.get_executable_path(), args))
		files.append(path)
		next_seed += count
		left -= count
		hard_left -= hard_count
	for pid: int in pids:
		while OS.is_process_running(pid):
			await get_tree().create_timer(0.5).timeout
	return ",".join(files)


# --- Match loop --------------------------------------------------------------

func _run_matches(opts: Dictionary, count: int, first_seed: int, mix: Array[int]) -> Array:
	var results: Array = []
	for i in range(count):
		var match_seed: int = first_seed + i
		var started_ms: int = Time.get_ticks_msec()
		var sim := Simulation.new()
		sim.headless = true
		sim.start_match(opts.size, opts.map_type, match_seed)
		_convert_all_to_bots(sim, mix)
		var leader_at_3min_id: int = -1
		var max_ticks: int = int((Balance.MATCH_TIME_LIMIT_SEC + 60.0) * Balance.TICKS_PER_SECOND)
		var ticks: int = 0
		while sim.state.phase != Balance.PHASE_ENDED and ticks < max_ticks:
			sim.advance_tick()
			sim.state.events.clear()
			ticks += 1
			if leader_at_3min_id < 0 and sim.state.match_time >= SAMPLE_LEADER_AT_SEC:
				leader_at_3min_id = _leader_id(sim.state)
		var stats: Dictionary = _collect_match_stats(sim, leader_at_3min_id, i + 1, match_seed)
		stats["wall_ms"] = Time.get_ticks_msec() - started_ms
		results.append(stats)
		print("[balance]  Match %d/%d  %s wins at %s (%s)  [%.1fs]" % [
			i + 1, count, stats.winner_name, GameState.format_time(stats.duration_sec), stats.win_reason, float(stats.wall_ms) / 1000.0])
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
	var truces: int = 0
	var truces_broken: int = 0
	var used: Dictionary = {}
	for p: Player in state.players:
		total_crowns += p.crowns_captured
		truces += p.truces_made
		truces_broken += p.truces_broken
		for k: int in p.buildings_built.keys():
			used["b%d" % k] = true
		for k: int in p.abilities_used.keys():
			used["a%d" % k] = true
		if p.boats_launched > 0:
			used["boat"] = true
		if p.keep_level > 0:
			used["keep"] = true
	return {
		"match": match_number,
		"seed": match_seed,
		"duration_sec": state.match_time,
		"winner_id": state.winner_id,
		"winner_name": winner.display_name if winner != null else "-",
		"winner_personality": winner.personality if winner != null else -1,
		"winner_difficulty": winner.difficulty if winner != null else -1,
		"win_reason": state.win_reason if state.win_reason != "" else "incomplete",
		"leader_at_3min_id": leader_at_3min_id,
		"leader_at_3min_won": leader_at_3min_id > 0 and leader_at_3min_id == state.winner_id,
		"crowns_captured": total_crowns,
		"truces": truces >> 1,   # each truce is counted by both partners
		"truces_broken": truces_broken,
		"ended_at_time_limit": state.phase == Balance.PHASE_ENDED and state.match_time >= Balance.MATCH_TIME_LIMIT_SEC - 1.0,
		"used": used.keys(),
		"fingerprint": _fingerprint(state),
	}


# Exact end state (every tile's owner, each player's land and troops, the end
# time). Two runs of the same seed must match bit for bit; used to prove that
# performance work changed nothing about the game.
func _fingerprint(state: GameState) -> String:
	var parts: PackedStringArray = PackedStringArray([str(hash(state.owners)), str(state.tick_count), str(state.winner_id)])
	for p: Player in state.players:
		parts.append("%d:%d:%s:%d" % [p.id, p.land, var_to_str(p.troops), p.crowns_captured])
	return ",".join(parts)


func _save_report(content: String, tag: String) -> String:
	var base: String = ProjectSettings.globalize_path("res://")
	var dir: DirAccess = DirAccess.open(base)
	if dir == null:
		return ""
	if not dir.dir_exists("reports"):
		dir.make_dir("reports")
	var date: String = Time.get_date_string_from_system()
	var file_name: String = ("balance_%s.md" % date) if tag == "" else ("balance_%s_%s.md" % [date, tag])
	var f: FileAccess = FileAccess.open(base.path_join("reports").path_join(file_name), FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(content)
	f.close()
	return "res://reports/" + file_name
