extends Node

# Times each part of Simulation.advance_tick over full bot-only matches, using
# the same calls in the same order, so we can see where simulator time goes.
# Also reports tick-time percentiles, how many ticks blew the 10 ms budget,
# and what the slowest ticks spent their time on.
#   godot --headless --path . res://scenes/tools/sim_profile.tscn -- --matches 2 --map large
# Add --real to profile like the game runs (flashes, popups, events, and the
# map texture update every tick) instead of the headless simulator path.

const BUDGET_US: int = 10000

var _totals: Dictionary = {}
var _counts: Dictionary = {}
var _tick_parts: Dictionary = {}       # this tick's time per section
var _tick_times: PackedInt32Array = PackedInt32Array()     # simulation only
var _frame_extra: PackedInt32Array = PackedInt32Array()    # map repaint (--real)
var _worst: Array = []                 # [us, match_time, attacks, parts]
var _real: bool = false
var _map: Map
var _last_events: Array = []


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
			"--real":
				_real = true
	var mix: Array[int] = [0, 0, 0, 1, 1, 1, 2, 1]
	var worst_tick_us: int = 0
	var worst_at: float = 0.0
	var started: int = Time.get_ticks_msec()
	for m in range(matches):
		var sim := Simulation.new()
		sim.headless = not _real
		sim.start_match(size, Balance.MAP_TYPE_CONTINENT, first_seed + m, bots_override)
		if _real:
			if _map == null:
				_map = Map.new()
				add_child(_map)
			_map.setup(sim.state)
		for i in range(sim.state.players.size()):
			var p: Player = sim.state.players[i]
			p.is_bot = true
			p.difficulty = mix[i % mix.size()]
			p.personality = sim.state.rng.randi() % 4
			p.think_timer = sim.state.rng.randf_range(0.2, 1.5)
		var ticks: int = 0
		while sim.state.phase != Balance.PHASE_ENDED and ticks < 9600:
			_tick_parts = {}
			var t0: int = Time.get_ticks_usec()
			_profiled_tick(sim)
			var dt: int = Time.get_ticks_usec() - t0 - int(_tick_parts.get("presentation", 0))
			if sim.state.phase == Balance.PHASE_MATCH:
				_tick_times.append(dt)
				_note_worst(dt, sim)
			if dt > worst_tick_us:
				worst_tick_us = dt
				worst_at = sim.state.match_time
			ticks += 1
		print("[profile] match %d: %s at %s, %d ticks" % [m + 1, sim.state.win_reason, GameState.format_time(sim.state.match_time), ticks])
	var total_ms: float = float(Time.get_ticks_msec() - started)
	print("[profile] %.1f s total, %.1f s per match, worst tick %.2f ms at %s" % [total_ms / 1000.0, total_ms / 1000.0 / float(matches), float(worst_tick_us) / 1000.0, GameState.format_time(worst_at)])
	_print_distribution()
	var keys: Array = _totals.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return _totals[a] > _totals[b])
	for k: String in keys:
		print("[profile] %-28s %8.1f ms total  %7.3f ms/call  %6.1f%%" % [k, float(_totals[k]) / 1000.0, float(_totals[k]) / 1000.0 / float(maxi(_counts[k], 1)), 100.0 * float(_totals[k]) / 1000.0 / total_ms])
	get_tree().quit()


func _time(label: String, t0: int) -> int:
	var now: int = Time.get_ticks_usec()
	_totals[label] = int(_totals.get(label, 0)) + (now - t0)
	_counts[label] = int(_counts.get(label, 0)) + 1
	_tick_parts[label] = int(_tick_parts.get(label, 0)) + (now - t0)
	return now


func _note_worst(dt: int, sim: Simulation) -> void:
	if _worst.size() >= 8 and dt <= int(_worst[-1][0]):
		return
	var tiles: int = 0
	var rings: int = 0
	for e: Dictionary in _last_events:
		if e.type == "attack_ring":
			tiles += int(e.tiles)
			rings += 1
	var parts: Dictionary = _tick_parts.duplicate()
	parts["_tiles"] = tiles
	parts["_rings"] = rings
	_worst.append([dt, sim.state.match_time, sim.state.attacks.size(), parts])
	_worst.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	if _worst.size() > 8:
		_worst.resize(8)


func _print_distribution() -> void:
	var sorted: PackedInt32Array = _tick_times.duplicate()
	sorted.sort()
	var n: int = sorted.size()
	if n == 0:
		return
	var over: int = 0
	for v: int in sorted:
		if v > BUDGET_US:
			over += 1
	print("[profile] %d match ticks (simulation): median %.2f ms, p95 %.2f ms, p99 %.2f ms, max %.2f ms; %d over the 10 ms budget" % [
		n, sorted[n >> 1] / 1000.0, sorted[int(n * 0.95)] / 1000.0, sorted[int(n * 0.99)] / 1000.0, sorted[n - 1] / 1000.0, over])
	if not _frame_extra.is_empty():
		var fr: PackedInt32Array = _frame_extra.duplicate()
		fr.sort()
		var m: int = fr.size()
		print("[profile] map repaint per tick: median %.2f ms, p99 %.2f ms, max %.2f ms (runs once per frame in the game)" % [fr[m >> 1] / 1000.0, fr[int(m * 0.99)] / 1000.0, fr[m - 1] / 1000.0])
	for w: Array in _worst:
		var parts: Dictionary = w[3]
		var captured: String = "%d tiles in %d rings" % [int(parts.get("_tiles", 0)), int(parts.get("_rings", 0))]
		parts.erase("_tiles")
		parts.erase("_rings")
		var keys: Array = parts.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return parts[a] > parts[b])
		var top: Array[String] = []
		for k: String in keys.slice(0, 3):
			top.append("%s %.1f" % [k, parts[k] / 1000.0])
		print("[profile]   slow tick %.2f ms at %s (%d attacks, %s): %s" % [int(w[0]) / 1000.0, GameState.format_time(float(w[1])), int(w[2]), captured, ", ".join(top)])


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
	sim.call("_tick_bots")
	t = _time("bots", t)
	sim.call("_check_win_conditions")
	t = _time("win_check", t)
	if _real:
		sim.call("_tick_flashes")
		sim.call("_tick_popups")
		t = _time("flashes_popups", t)
		_map.render()
		t = _time("presentation", t)
		_frame_extra.append(int(_tick_parts.get("presentation", 0)))
	_last_events = st.events.duplicate()
	st.events.clear()
	st.tick_count += 1
