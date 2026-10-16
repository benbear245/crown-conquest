class_name TapTargets
extends RefCounted

# Works out what a tap on the map means, forgiving a finger that lands a few
# tiles off: a tap on your own land (or water) near the border snaps to the
# closest enemy or free tile. Also says why an action would be refused, so a
# tap never fails silently. Reads the Simulation only.

const NONE: String = ""
const EXPAND: String = "expand"
const ATTACK: String = "attack"


# {action, tile: Vector2i, owner}. action is NONE when nothing is in reach.
static func resolve(state: GameState, me: Player, tile: Vector2i, radius: int) -> Dictionary:
	var direct: Dictionary = _classify(state, me, tile)
	if String(direct["action"]) != NONE:
		return direct
	var best: Dictionary = direct
	var best_d2: int = radius * radius + 1
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var d2: int = dx * dx + dy * dy
			if d2 >= best_d2:
				continue
			var c: Dictionary = _classify(state, me, tile + Vector2i(dx, dy))
			if String(c["action"]) != NONE:
				best = c
				best_d2 = d2
	return best


static func _classify(state: GameState, me: Player, t: Vector2i) -> Dictionary:
	var out: Dictionary = {"action": NONE, "tile": t, "owner": 0}
	if not state.in_bounds(t.x, t.y):
		return out
	var i: int = state.idx(t.x, t.y)
	if state.is_blocked_terrain(state.terrain[i]):
		return out
	var owner_id: int = state.owners[i]
	out["owner"] = owner_id
	if owner_id == me.id:
		return out
	if state.is_player_owner(owner_id):
		var p: Player = state.get_player(owner_id)
		if p != null and p.is_alive:
			out["action"] = ATTACK
		return out
	out["action"] = EXPAND
	return out


# Why attacking this player would be refused right now, or "" if it's fine.
static func attack_blocker(sim: Simulation, me: Player, owner_id: int, fraction: float) -> String:
	var state: GameState = sim.state
	var target: Player = state.get_player(owner_id)
	var who: String = target.display_name if target != null else "them"
	if state.is_peace():
		return "Peace — no attacks until %s" % GameState.format_time(state.peace_sec)
	if floorf(me.troops * fraction) <= 0.0:
		return "Not enough troops — wait for them to grow"
	if CombatOps.build_attack_front(state, me, owner_id).is_empty():
		return "You don't border %s yet — grow toward them, or sail there from a Port" % who
	if CombatOps.attack_on(state, me.id, owner_id) == null \
			and sim.active_attack_count(me.id) >= Balance.MAX_SIMULTANEOUS_ATTACKS:
		return "You already have %d attacks running — tap one of those enemies to reinforce it" % Balance.MAX_SIMULTANEOUS_ATTACKS
	return ""


static func expand_blocker(sim: Simulation, me: Player, fraction: float) -> String:
	if floorf(me.troops * fraction) <= 0.0:
		return "Not enough troops — wait for them to grow"
	if not TerritoryOps.has_frontier(sim.state, me):
		return "No free land next to your border — attack a rival to grow"
	return ""
