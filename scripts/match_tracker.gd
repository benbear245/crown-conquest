class_name MatchTracker
extends RefCounted

# Watches one match from the local player's side and sums it up for XP,
# stats and achievements. Presentation side only: it reads the sim, never
# changes it.

var _sim: Simulation
var _smallest_checked: bool = false
var smallest_at_3min: bool = false
var siege_crowns: int = 0


func _init(sim: Simulation) -> void:
	_sim = sim


# Once per frame, with the frame's events. Returns the ids of achievements
# earned right now (mid-match), e.g. Kingslayer on the third Crown.
func observe(events: Array) -> Array[String]:
	var st: GameState = _sim.state
	var me: Player = st.get_player(_sim.local_player_id)
	var now: Array[String] = []
	if me == null:
		return now
	if not _smallest_checked and st.match_time >= 180.0 and st.phase == Balance.PHASE_MATCH:
		_smallest_checked = true
		smallest_at_3min = me.is_alive
		for p: Player in st.players:
			if p.is_alive and p.id != me.id and p.land < me.land:
				smallest_at_3min = false
	for e: Dictionary in events:
		if e.type == "crown_fall" and int(e.capturer_id) == me.id:
			if st.is_final_siege():
				siege_crowns += 1
				now.append("siege_lord")
			if me.crowns_captured >= 3:
				now.append("kingslayer")
	return now


func result() -> Dictionary:
	var st: GameState = _sim.state
	var me: Player = st.get_player(_sim.local_player_id)
	var cfg: MatchConfig = _sim.config
	var built: int = 0
	for type: int in me.buildings_built.keys():
		if type != BuildingsOps.TYPE_WALL:
			built += int(me.buildings_built[type])
	var ended_time: float = st.match_time if me.is_alive else me.eliminated_at
	return {
		"mode": cfg.mode if cfg != null else MatchConfig.Mode.SKIRMISH,
		"map_type": st.resolved_map_type,
		"won": _sim.local_won(),
		"peak_pct": 100.0 * float(me.peak_land) / float(maxi(st.total_usable_tiles(), 1)),
		"crowns": me.crowns_captured,
		"duration_sec": ended_time,
		"hard": cfg != null and cfg.difficulty == Balance.BOT_DIFFICULTY_HARD,
		"win_reason": st.win_reason,
		"smallest_at_3min": smallest_at_3min,
		"ports_built": int(me.buildings_built.get(Balance.BUILDING_PORT, 0)),
		"buildings_built": built,
		"truces_made": me.truces_made,
		"crown_attacked": me.crown_alert_until > 0.0,
		"sent_to_ally": me.troops_sent_to_ally,
		"siege_crowns": siege_crowns,
		"daily_score": _sim.daily_score() if cfg != null and cfg.mode == MatchConfig.Mode.DAILY else -1,
	}
