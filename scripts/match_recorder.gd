class_name MatchRecorder
extends RefCounted

# Watches one match from the local player's side and builds the summary the
# recap, XP, achievements and daily challenges are worked out from. Reads
# the Simulation (local or mirrored) and the events and command results the
# game passes in, so it works the same offline and online.

const SAMPLE_EVERY_SEC: float = 5.0
const UNDERDOG_CHECK_SEC: float = 180.0

var mode: String = MatchSetup.MODE_SKIRMISH
var online: bool = false
var difficulty: int = MatchSetup.DIFFICULTY_MIXED
var map_type: int = Balance.MAP_TYPE_CONTINENT

var land_samples: PackedFloat32Array = PackedFloat32Array()   # land % every SAMPLE_EVERY_SEC
var moments: Array[Dictionary] = []                           # {time, text, score}
var finished: bool = false
var result: Dictionary = {}                                   # Profile.record_match() output

var _next_sample: float = 0.0
var _peak_pct: float = 0.0
var _underdog_checked: bool = false
var _underdog_at_3: bool = false
var _held_all_shrines: bool = false
var _milestone: int = 0          # last land % milestone reached (10, 20, …)
var _counts: Dictionary = {"crowns": 0, "shrines_taken": 0, "spy_ok": 0, "truces_made": 0,
	"forts_built": 0, "walls_built": 0, "ports_built": 0, "bombards": 0}


func _init(setup: MatchSetup, is_online: bool) -> void:
	online = is_online
	if setup != null:
		mode = setup.mode
		difficulty = setup.difficulty
		map_type = setup.map_type
	if online:
		mode = MatchSetup.MODE_ONLINE


# Called every frame while the match runs.
func observe(sim: Simulation) -> void:
	var state: GameState = sim.state
	var me: Player = state.get_player(sim.local_player_id)
	if me == null or state.phase == Balance.PHASE_PLACEMENT:
		return
	var pct: float = 100.0 * state.land_fraction(me)
	if me.is_alive:
		_peak_pct = maxf(_peak_pct, pct)
		while _peak_pct >= float(_milestone + 10):
			_milestone += 10
			if _milestone >= 20:
				_moment(state.match_time, "Reached %d%% of the land" % _milestone, 20 + _milestone)
	while state.match_time >= _next_sample:
		land_samples.append(pct if me.is_alive else 0.0)
		_next_sample += SAMPLE_EVERY_SEC
	if not _underdog_checked and state.match_time >= UNDERDOG_CHECK_SEC:
		_underdog_checked = true
		_underdog_at_3 = me.is_alive and _is_smallest(state, me)
	if not _held_all_shrines and not state.shrines.is_empty() and me.is_alive:
		var all_mine: bool = true
		for s: Shrine in state.shrines:
			all_mine = all_mine and s.holder_id == me.id
		if all_mine:
			_held_all_shrines = true
			_moment(state.match_time, "Held every Shrine at once", 70)


func on_event(sim: Simulation, e: Dictionary) -> void:
	var me: int = sim.local_player_id
	var t: float = sim.state.match_time
	match String(e["type"]):
		"crown_fell":
			if int(e["capturer_id"]) == me:
				_counts["crowns"] += 1
				var victim: Player = sim.state.get_player(int(e["victim_id"]))
				var who: String = victim.display_name if victim != null else "a rival"
				_moment(t, "Took %s's Crown" % who, 100 + int(_counts["crowns"]) * 10)
			elif int(e["victim_id"]) == me:
				_moment(t, "Your Crown fell", 5)
		"shrine_taken":
			if int(e["player_id"]) == me:
				_counts["shrines_taken"] += 1
				_moment(t, "Captured the %s" % Shrine.kind_label(int(e["kind"])), 30)
		"spy_done":
			if int(e["spender_id"]) == me:
				_counts["spy_ok"] += 1
		"truce_made":
			if int(e["a_id"]) == me or int(e["b_id"]) == me:
				_counts["truces_made"] += 1


# A command the local player sent, once the match has answered it.
func on_command(cmd: String, args: Array, ok: bool) -> void:
	if not ok:
		return
	match cmd:
		"build":
			var t: int = int(args[0])
			if t == Balance.BUILDING_FORT:
				_counts["forts_built"] += 1
			elif t == Balance.BUILDING_PORT:
				_counts["ports_built"] += 1
		"build_wall":
			_counts["walls_built"] += 1
		"ability":
			if int(args[0]) == AbilitiesOps.ID_BOMBARD:
				_counts["bombards"] += 1


# True once: the moment the recap should be shown and progress recorded.
func should_finish(sim: Simulation) -> bool:
	if finished:
		return false
	var me: Player = sim.state.get_player(sim.local_player_id)
	return sim.state.phase == Balance.PHASE_ENDED or (me != null and not me.is_alive)


func summary(sim: Simulation) -> Dictionary:
	var state: GameState = sim.state
	var me: Player = state.get_player(sim.local_player_id)
	var ended: bool = state.phase == Balance.PHASE_ENDED
	var won: bool = ended and state.winner_id == sim.local_player_id
	var s: Dictionary = _counts.duplicate()
	s.merge({
		"won": won, "place": HudRecap.place_of(state, me) if me != null else state.players.size(),
		"players": state.players.size(), "time": state.match_time,
		"reason": state.win_reason if ended else "", "dominion": won and state.win_reason.contains("Dominion"),
		"mode": mode, "map_type": map_type, "difficulty": difficulty, "online": online,
		"peak_land_pct": _peak_pct, "held_all_shrines": _held_all_shrines, "underdog_at_3": _underdog_at_3,
		"survived_sec": state.match_time if me != null and me.is_alive else (me.eliminated_at if me != null else 0.0),
	})
	return s


func best_moment() -> Dictionary:
	var best: Dictionary = {}
	for m in moments:
		if best.is_empty() or int(m["score"]) > int(best["score"]):
			best = m
	return best


func _moment(t: float, text: String, score: int) -> void:
	moments.append({"time": t, "text": text, "score": score})


static func _is_smallest(state: GameState, me: Player) -> bool:
	for p: Player in state.players:
		if p != me and p.is_alive and p.land < me.land:
			return false
	return true
