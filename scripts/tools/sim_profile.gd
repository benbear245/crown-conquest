extends Node

# Times each part of Simulation.advance_tick over full bot-only matches, using
# the same calls in the same order, so we can see where simulator time goes.
#   godot --headless --path . res://scenes/tools/sim_profile.tscn -- --matches 2 --map medium

var _totals: Dictionary = {}
var _counts: Dictionary = {}


func _ready() -> void:
	var matches: int = 1
	var size: int = Balance.MAP_SIZE_MEDIUM
	var bots_override: int = -1
	var first_seed: int = 1
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		var nxt: String = args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--matches":
				matches = nxt.to_int()
			"--map":
				size = Balance.MAP_SIZE_LARGE if nxt == "large" else (Balance.MAP_SIZE_SMALL if nxt == "small" else Balance.MAP_SIZE_MEDIUM)
			"--bots":
				bots_override = nxt.to_int()
			"--seed":
				first_seed = nxt.to_int()
	var mix: Array[int] = [0, 0, 0, 1, 1, 1, 2, 1]
	var worst_tick_us: int = 0
	var worst_at: float = 0.0
	var started: int = Time.get_ticks_msec()
	for m in range(matches):
		var sim := Simulation.new()
		sim.headless = true
		sim.start_match(size, Balance.MAP_TYPE_CONTINENT, first_seed + m, bots_override)
		for i in range(sim.state.players.size()):
			var p: Player = sim.state.players[i]
			p.is_bot = true
			p.difficulty = mix[i % mix.size()]
			p.personality = sim.state.rng.randi() % 4
			p.think_timer = sim.state.rng.randf_range(0.2, 1.5)
		var ticks: int = 0
		while sim.state.phase != Balance.PHASE_ENDED and ticks < 9600:
			var t0: int = Time.get_ticks_usec()
			_profiled_tick(sim)
			var dt: int = Time.get_ticks_usec() - t0
			if dt > worst_tick_us:
				worst_tick_us = dt
				worst_at = sim.state.match_time
			ticks += 1
		print("[profile] match %d: %s at %s, %d ticks" % [m + 1, sim.state.win_reason, GameState.format_time(sim.state.match_time), ticks])
	var total_ms: float = float(Time.get_ticks_msec() - started)
	print("[profile] %.1f s total, %.1f s per match, worst tick %.2f ms at %s" % [total_ms / 1000.0, total_ms / 1000.0 / float(matches), float(worst_tick_us) / 1000.0, GameState.format_time(worst_at)])
	var keys: Array = _totals.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return _totals[a] > _totals[b])
	for k: String in keys:
		print("[profile] %-28s %8.1f ms total  %7.3f ms/call  %6.1f%%" % [k, float(_totals[k]) / 1000.0, float(_totals[k]) / 1000.0 / float(maxi(_counts[k], 1)), 100.0 * float(_totals[k]) / 1000.0 / total_ms])
	get_tree().quit()


func _time(label: String, t0: int) -> int:
	var now: int = Time.get_ticks_usec()
	_totals[label] = int(_totals.get(label, 0)) + (now - t0)
	_counts[label] = int(_counts.get(label, 0)) + 1
	return now


# Mirrors Simulation.advance_tick (headless path) with a timer around each step.
func _profiled_tick(sim: Simulation) -> void:
	var st: GameState = sim.state
	if st.phase != Balance.PHASE_MATCH:
		sim.advance_tick()
		return
	var t: int = Time.get_ticks_usec()
	st.match_time += Balance.TICK_DELTA
	sim.call("_announce_final_siege_once")
	FairPlayOps.recompute_once_per_second(st)
	t = _time("fair_play_recompute", t)
	FairPlayOps.apply_growth(st)
	t = _time("growth", t)
	TerritoryOps.apply_expansions(sim)
	t = _time("expansions", t)
	AbilitiesOps.tick(sim)
	t = _time("abilities", t)
	TrucesOps.tick(sim)
	t = _time("truces", t)
	CombatOps.tick_attacks(sim)
	t = _time("attacks", t)
	sim.call("_tick_boats")
	t = _time("boats", t)
	CombatOps.check_crown_alerts(st)
	t = _time("crown_alerts", t)
	for p: Player in st.players:
		if p.is_alive and p.is_bot:
			Bots.tick(sim, p)
	t = _time("bots", t)
	sim.call("_check_win_conditions")
	t = _time("win_check", t)
	st.events.clear()
	st.tick_count += 1
