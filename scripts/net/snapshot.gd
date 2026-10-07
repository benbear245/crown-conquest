class_name Snapshot
extends RefCounted

# Server side: builds the personal update for one player. A player gets the
# public map, their own full record, and only what IntelOps lets them know
# about rivals. Hidden numbers never leave the server.

const FRONT_EVERY_TICKS: int = 2

# Fields everyone can see about every player (shown on the map or announced).
const PUBLIC_FIELDS: Array[String] = [
	"display_name", "land", "is_alive", "is_bot", "personality", "crown_x", "crown_y",
	"crown_move_to", "crown_move_until", "eliminated_at", "crowns_captured",
	"crown_alert_until", "crown_shield_until", "oathbreaker_until", "refuses_all_truces",
]
# Fields only the player themself gets.
const PRIVATE_FIELDS: Array[String] = [
	"troops", "expansion_troops", "gem_tiles", "peak_land", "crown_moved", "keep_level",
	"fort_count", "barracks_count", "port_count", "wall_count", "watchtower_count",
	"swift_march_cd_until", "swift_march_until", "crown_shield_cd_until",
	"rally_cd_until", "rally_until", "bombard_cd_until", "active_truces",
	"intel", "spy_cd_until", "watched_until", "disinfo_until", "disinfo_mult", "disinfo_cd_until",
]
# Fields a live Spy reveals about a rival (troops are sent separately, as
# seen through Disinformation).
const SPY_FIELDS: Array[String] = [
	"keep_level", "fort_count", "barracks_count", "watchtower_count", "wall_count", "gem_tiles",
	"swift_march_cd_until", "crown_shield_cd_until", "rally_cd_until", "bombard_cd_until",
	"active_truces",
]


static func fields(p: Player, names: Array[String]) -> Array:
	var out: Array = []
	for f in names:
		out.append(p.get(f))
	return out


# Sent when a player joins or the match starts: the whole map plus a tick.
static func full(sim: Simulation, viewer_id: int, tiles: PackedInt32Array, events: Array, acks: Array) -> Dictionary:
	var state: GameState = sim.state
	var structures := PackedInt32Array()
	for i: int in state.building_at_tile.keys():
		structures.append(Protocol.pack_tile(state, i))
	for i: int in state.wall_tiles.keys():
		structures.append(Protocol.pack_tile(state, i))
	var msg: Dictionary = tick(sim, viewer_id, tiles, events, acks)
	msg["t"] = "full"
	msg["w"] = state.width
	msg["h"] = state.height
	msg["size"] = sim.size_preset
	msg["map_type"] = sim.map_type
	msg["terrain"] = state.terrain
	msg["owners"] = state.owners
	msg["structures"] = structures
	msg["you"] = viewer_id
	return msg


# Sent every tick: what changed and what this player may know right now.
static func tick(sim: Simulation, viewer_id: int, tiles: PackedInt32Array, events: Array, acks: Array) -> Dictionary:
	var state: GameState = sim.state
	var now: float = state.match_time
	var viewer: Player = state.get_player(viewer_id)
	var players: Array = []
	var rivals: Dictionary = {}
	for p: Player in state.players:
		players.append(fields(p, PUBLIC_FIELDS))
		if p.id == viewer_id or viewer == null:
			continue
		var r: Dictionary = {"view": IntelOps.troop_view(viewer, p, now)}
		if IntelOps.has_live_spy(viewer, p.id, now):
			r["spy"] = fields(p, SPY_FIELDS)
			r["troops"] = IntelOps.apparent_troops(p, now)
		if IntelOps.has_plans(viewer, p.id, now):
			r["plan"] = p.plan_target_id
		rivals[p.id] = r
	var attacks: Array = []
	# Fronts only move once per ring (every few ticks), so they travel only on
	# ring ticks; in between the client keeps the last front it got.
	var send_fronts: bool = state.tick_count % FRONT_EVERY_TICKS == 0
	for a: Attack in state.attacks:
		# Other players' attack strength is hidden unless you stole their plans.
		var seen: bool = a.attacker_id == viewer_id or (viewer != null and IntelOps.has_plans(viewer, a.attacker_id, now))
		var front: Variant = null
		if send_fronts:
			front = PackedInt32Array(a.front.keys())
		attacks.append([a.attacker_id, a.defender_id, a.troops_remaining if seen else -1.0, front])
	var boats: Array = []
	for b: Boat in state.boats:
		boats.append([b.owner_id, b.current_tile_idx()])
	# Shrines appear when placement ends, so their (tiny) list rides along
	# with every update: [kind, x, y, holder] each.
	var shrines := PackedInt32Array()
	for s: Shrine in state.shrines:
		shrines.append_array([s.kind, s.x, s.y, s.holder_id])
	var truces: Array = []
	for off: Dictionary in state.pending_truces:
		if int(off["from_id"]) == viewer_id or int(off["to_id"]) == viewer_id:
			truces.append(off)
	return {
		"t": "tick",
		"tick": state.tick_count,
		"phase": state.phase,
		"time": now,
		"placement_left": state.placement_time_left,
		"winner": state.winner_id,
		"reason": state.win_reason,
		"rising": sim.rising_empire_id(),
		"avg_land": sim.average_land(),
		"tiles": tiles,
		"players": players,
		"me": fields(viewer, PRIVATE_FIELDS) if viewer != null else [],
		"rivals": rivals,
		"attacks": attacks,
		"boats": boats,
		"bombards": state.bombards,
		"shrines": shrines,
		"truces": truces,
		"events": events,
		"acks": acks,
	}


# Which of this tick's sim events a player should hear about, with anything
# they mustn't learn removed. Returns {} to drop the event for them.
static func route_event(e: Dictionary, viewer_id: int) -> Dictionary:
	match String(e["type"]):
		"announce":
			var to: Array = e.get("to", [])
			return e if to.is_empty() or to.has(viewer_id) else {}
		"crown_alert", "loot":
			return e if int(e["player_id"]) == viewer_id else {}
		"truce_offer":
			return e if int(e["to_id"]) == viewer_id or int(e["from_id"]) == viewer_id else {}
		"spy_caught":
			return e if int(e["spender_id"]) == viewer_id or int(e["target_id"]) == viewer_id else {}
		"spy_done":
			if int(e["spender_id"]) == viewer_id:
				return e
			if int(e["target_id"]) == viewer_id:
				# The target only learns that someone is watching, not who.
				return {"type": "spy_done", "spender_id": 0, "target_id": viewer_id, "action": -1}
			return {}
		_:
			return e
