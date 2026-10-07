class_name IntelOps
extends RefCounted

# Hidden information and spying. Rivals' troop counts are hidden: everyone
# sees only a free strength band (weaker / even / stronger than you). Spending
# troops on Scout, Spy, Sabotage or Steal plans reveals more. Watchtowers and
# the Shrine of Sight give free, slower Scout-level snapshots.
#
# Everything a player (or bot) knows about a rival goes through this file, so
# an online server can send each client only what IntelOps says it may see.

const BAND_WEAKER: int = -1
const BAND_EVEN: int = 0
const BAND_STRONGER: int = 1

const VIEW_LIVE: String = "live"        # exact, from an active Spy
const VIEW_RANGE: String = "range"      # fresh Scout snapshot (+/- 20%)
const VIEW_STALE: String = "stale"      # old Scout snapshot
const VIEW_BAND: String = "band"        # nothing paid for: strength band only


# --- What can be seen ----------------------------------------------------------

# Troops as the world sees them: Disinformation multiplies every view.
static func apparent_troops(target: Player, now: float) -> float:
	if target.disinfo_until > now:
		return target.troops * target.disinfo_mult
	return target.troops


static func strength_band(viewer: Player, target: Player, now: float) -> int:
	var mine: float = maxf(viewer.troops, 1.0)
	var ratio: float = apparent_troops(target, now) / mine
	if ratio < Balance.STRENGTH_BAND_WEAK_RATIO:
		return BAND_WEAKER
	if ratio > Balance.STRENGTH_BAND_STRONG_RATIO:
		return BAND_STRONGER
	return BAND_EVEN


static func band_label(band: int) -> String:
	match band:
		BAND_WEAKER:
			return "Weaker than you"
		BAND_STRONGER:
			return "Stronger than you"
		_:
			return "About even"


static func has_live_spy(viewer: Player, target_id: int, now: float) -> bool:
	var rec: Dictionary = viewer.intel.get(target_id, {})
	return float(rec.get("spy_until", 0.0)) > now


static func has_plans(viewer: Player, target_id: int, now: float) -> bool:
	var rec: Dictionary = viewer.intel.get(target_id, {})
	return float(rec.get("plans_until", 0.0)) > now


# The best troop information viewer has about target right now.
static func troop_view(viewer: Player, target: Player, now: float) -> Dictionary:
	if viewer.id == target.id:
		return {"kind": VIEW_LIVE, "value": target.troops}
	if has_live_spy(viewer, target.id, now):
		return {"kind": VIEW_LIVE, "value": apparent_troops(target, now)}
	var rec: Dictionary = viewer.intel.get(target.id, {})
	if rec.has("scout_at"):
		var v: float = float(rec["scout_value"])
		var age: float = now - float(rec["scout_at"])
		return {
			"kind": VIEW_RANGE if age <= Balance.SCOUT_FRESH_SEC else VIEW_STALE,
			"value": v, "age": age,
			"low": v * (1.0 - Balance.SCOUT_RANGE_FRACTION),
			"high": v * (1.0 + Balance.SCOUT_RANGE_FRACTION),
		}
	return {"kind": VIEW_BAND, "band": strength_band(viewer, target, now)}


# A single best-guess number for bots, built only from what troop_view allows.
static func estimate_troops(viewer: Player, target: Player, now: float) -> float:
	var view: Dictionary = troop_view(viewer, target, now)
	if view["kind"] != VIEW_BAND:
		return float(view["value"])
	match int(view["band"]):
		BAND_WEAKER:
			return viewer.troops * Balance.BAND_ESTIMATE_WEAK
		BAND_STRONGER:
			return viewer.troops * Balance.BAND_ESTIMATE_STRONG
		_:
			return viewer.troops * Balance.BAND_ESTIMATE_EVEN


# --- Spy actions ----------------------------------------------------------------

static func action_label(action: int) -> String:
	match action:
		Balance.SPY_SCOUT:
			return "Scout"
		Balance.SPY_SPY:
			return "Spy"
		Balance.SPY_SABOTAGE:
			return "Sabotage"
		Balance.SPY_PLANS:
			return "Steal plans"
		_:
			return "?"


static func action_cost(spender: Player, action: int) -> float:
	return maxf(Balance.SPY_MIN_COST[action], floorf(spender.troops * Balance.SPY_COST_FRACTION[action]))


static func catch_chance(target: Player, now: float, state: GameState) -> float:
	var towers: int = 0
	for b: Building in state.buildings:
		if b.owner_id == target.id and b.type == Balance.BUILDING_WATCHTOWER and b.is_active(now):
			towers += 1
	return clampf(Balance.SPY_CATCH_CHANCE_BASE + Balance.SPY_CATCH_CHANCE_PER_WATCHTOWER * float(towers), 0.0, 0.95)


# Why spender can't do this action on target now, or "" if they can.
static func action_blocker(sim: Simulation, spender: Player, target_id: int, action: int) -> String:
	var state: GameState = sim.state
	var now: float = state.match_time
	var target: Player = state.get_player(target_id)
	if target == null or not target.is_alive or target_id == spender.id:
		return "No target"
	if now < Balance.SPY_UNLOCK_SEC[action]:
		return "unlocks %s" % GameState.format_time(Balance.SPY_UNLOCK_SEC[action])
	var cd: float = float(spender.spy_cd_until.get(target_id, 0.0))
	if cd > now:
		return "wait %ds" % int(ceilf(cd - now))
	if spender.troops < action_cost(spender, action):
		return "need %d" % int(action_cost(spender, action))
	if action == Balance.SPY_SABOTAGE and BuildingsOps.nearest_building_to(state, target_id, spender) == null:
		return "no buildings"
	return ""


static func perform(sim: Simulation, spender: Player, target_id: int, action: int) -> bool:
	if action < 0 or action > Balance.SPY_PLANS:
		return false
	if action_blocker(sim, spender, target_id, action) != "":
		return false
	var state: GameState = sim.state
	var now: float = state.match_time
	var target: Player = state.get_player(target_id)
	spender.troops -= action_cost(spender, action)
	spender.spy_cd_until[target_id] = now + Balance.SPY_TARGET_COOLDOWN_SEC
	if state.rng.randf() < catch_chance(target, now, state):
		target.grudges[spender.id] = now + Balance.BOT_GRUDGE_SEC
		sim.emit({"type": "spy_caught", "spender_id": spender.id, "target_id": target_id, "action": action})
		sim.announce("%s caught a spy from %s!" % [target.display_name, spender.display_name], [spender.id, target_id])
		return true
	var rec: Dictionary = spender.intel.get(target_id, {})
	match action:
		Balance.SPY_SCOUT:
			_snapshot_into(rec, target, now, state.rng)
		Balance.SPY_SPY:
			rec["spy_until"] = now + Balance.SPY_DURATION_SEC
		Balance.SPY_PLANS:
			rec["plans_until"] = now + Balance.PLANS_DURATION_SEC
		Balance.SPY_SABOTAGE:
			var b: Building = BuildingsOps.nearest_building_to(state, target_id, spender)
			b.disabled_until = now + Balance.SABOTAGE_DURATION_SEC
			state.dirty_tiles[b.tile_idx] = true
			sim.announce("A %s of %s was sabotaged!" % [Building.type_label(b.type), target.display_name], [spender.id, target_id])
	spender.intel[target_id] = rec
	target.watched_until = now + Balance.SPY_WARNING_SEC
	sim.emit({"type": "spy_done", "spender_id": spender.id, "target_id": target_id, "action": action})
	return true


static func _snapshot_into(rec: Dictionary, target: Player, now: float, rng: RandomNumberGenerator) -> void:
	var noise: float = rng.randf_range(-Balance.SCOUT_NOISE_FRACTION, Balance.SCOUT_NOISE_FRACTION)
	rec["scout_value"] = apparent_troops(target, now) * (1.0 + noise)
	rec["scout_at"] = now


# --- Disinformation -------------------------------------------------------------

static func disinfo_blocker(sim: Simulation, p: Player) -> String:
	var now: float = sim.state.match_time
	if p.disinfo_until > now:
		return "active %ds" % int(ceilf(p.disinfo_until - now))
	if p.disinfo_cd_until > now:
		return "cd %ds" % int(ceilf(p.disinfo_cd_until - now))
	if p.troops < disinfo_cost(p):
		return "need %d" % int(disinfo_cost(p))
	return ""


static func disinfo_cost(p: Player) -> float:
	return floorf(p.troops * Balance.DISINFO_COST_FRACTION)


static func start_disinformation(sim: Simulation, p: Player, look_strong: bool) -> bool:
	if disinfo_blocker(sim, p) != "":
		return false
	var now: float = sim.state.match_time
	p.troops -= disinfo_cost(p)
	p.disinfo_mult = Balance.DISINFO_STRONG_MULT if look_strong else Balance.DISINFO_WEAK_MULT
	p.disinfo_until = now + Balance.DISINFO_DURATION_SEC
	p.disinfo_cd_until = now + Balance.DISINFO_DURATION_SEC + Balance.DISINFO_COOLDOWN_SEC
	return true


# --- Passive intel (Watchtowers, Shrine of Sight) ------------------------------

static func tick(sim: Simulation) -> void:
	var state: GameState = sim.state
	var every: int = int(Balance.INTEL_PASSIVE_REFRESH_SEC * Balance.TICKS_PER_SECOND)
	if state.tick_count % every != 0:
		return
	var now: float = state.match_time
	for viewer: Player in state.players:
		if not viewer.is_alive:
			continue
		_forget_old(viewer, now)
		var sight: bool = ShrinesOps.holds_kind(state, viewer.id, Balance.SHRINE_SIGHT)
		var towers: Array[Building] = []
		if not sight:
			for b: Building in state.buildings:
				if b.owner_id == viewer.id and b.type == Balance.BUILDING_WATCHTOWER and b.is_active(now):
					towers.append(b)
			if towers.is_empty():
				continue
		var seen: Dictionary = {}
		if sight:
			for p: Player in state.players:
				seen[p.id] = true
		else:
			for b in towers:
				_rivals_near(state, b.x, b.y, b.radius(), seen)
		for target_id: int in seen.keys():
			var target: Player = state.get_player(target_id)
			if target == null or not target.is_alive or target_id == viewer.id:
				continue
			var rec: Dictionary = viewer.intel.get(target_id, {})
			_snapshot_into(rec, target, now, state.rng)
			viewer.intel[target_id] = rec


static func _rivals_near(state: GameState, cx: int, cy: int, r: int, out: Dictionary) -> void:
	var r2: int = r * r
	for y in range(maxi(0, cy - r), mini(state.height, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(state.width, cx + r + 1)):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) > r2:
				continue
			var ow: int = state.owners[state.idx(x, y)]
			if state.is_player_owner(ow):
				out[ow] = true


static func _forget_old(viewer: Player, now: float) -> void:
	for tid: int in viewer.intel.keys():
		var rec: Dictionary = viewer.intel[tid]
		if rec.has("scout_at") and now - float(rec["scout_at"]) > Balance.SCOUT_FORGET_SEC:
			rec.erase("scout_at")
			rec.erase("scout_value")
		if rec.is_empty():
			viewer.intel.erase(tid)
