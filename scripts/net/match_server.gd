class_name MatchServer
extends RefCounted

# Runs one online match: a lobby until the host starts, then the real
# Simulation at 10 ticks per second. Knows nothing about sockets: packets come
# in through receive() and go out through the outbox, so the same server works
# over ENet, over a loopback link in one app, or headless on a machine.

# A message for one connection: {peer, bytes}.
var outbox: Array[Dictionary] = []
var sim: Simulation
var started: bool = false

var _names: Dictionary = {}         # peer_id -> chosen name (join order kept in _order)
var _order: Array[int] = []
var _seats: Dictionary = {}         # peer_id -> player_id once the match starts
var _host_peer: int = -1
var _acks: Dictionary = {}          # peer_id -> Array of [seq, ok]
var _tick_accumulator: float = 0.0
var _human_count: int = 0           # seats 1.._human_count belong to people


func _init(host_peer_id: int) -> void:
	_host_peer = host_peer_id


func peer_count() -> int:
	return _order.size()


# --- Connections ---------------------------------------------------------------

func peer_left(peer_id: int) -> void:
	if not _names.has(peer_id):
		return
	_names.erase(peer_id)
	_order.erase(peer_id)
	if peer_id == _host_peer and not _order.is_empty():
		_host_peer = _order[0]
	if started and _seats.has(peer_id):
		# A bot takes over the empire; the player can rejoin under the same name.
		var p: Player = sim.state.get_player(int(_seats[peer_id]))
		if p != null and p.is_alive:
			p.is_bot = true
			p.difficulty = Balance.BOT_DIFFICULTY_NORMAL
			sim.announce("%s left — a bot takes over their empire." % p.display_name)
		_seats.erase(peer_id)
	else:
		_send_lobby()


func receive(peer_id: int, packet: PackedByteArray) -> void:
	var msg: Dictionary = Protocol.decode(packet)
	if msg.is_empty():
		return
	match String(msg["t"]):
		"hello":
			_on_hello(peer_id, msg)
		"start":
			if peer_id == _host_peer and not started:
				start_match(int(Time.get_unix_time_from_system()))
		"cmd":
			_on_command(peer_id, msg)


func _on_hello(peer_id: int, msg: Dictionary) -> void:
	if int(msg.get("v", -1)) != Protocol.VERSION:
		_send(peer_id, {"t": "bye", "msg": "Different game version — update the app."})
		return
	var wanted: String = String(msg.get("name", "Player")).strip_edges().left(16)
	if wanted == "":
		wanted = "Player"
	if started:
		_rejoin(peer_id, wanted)
		return
	if _order.size() >= Protocol.MAX_PLAYERS:
		_send(peer_id, {"t": "bye", "msg": "This game is full."})
		return
	_names[peer_id] = _unique_name(wanted)
	_order.append(peer_id)
	if _host_peer < 0:
		_host_peer = peer_id
	_send_lobby()


# A player who dropped out can take their empire back from the bot.
func _rejoin(peer_id: int, wanted: String) -> void:
	for p: Player in sim.state.players:
		if p.display_name == wanted and p.is_alive and p.is_bot and not _seats.values().has(p.id) and p.id <= _human_seats():
			p.is_bot = false
			_names[peer_id] = wanted
			_order.append(peer_id)
			_seats[peer_id] = p.id
			_send(peer_id, Snapshot.full(sim, p.id, PackedInt32Array(), [], []))
			sim.announce("%s is back!" % wanted)
			return
	_send(peer_id, {"t": "bye", "msg": "The match has already started."})


func _human_seats() -> int:
	return _human_count


func _unique_name(wanted: String) -> String:
	var name_taken := func(n: String) -> bool: return _names.values().has(n)
	if not name_taken.call(wanted):
		return wanted
	var k: int = 2
	while name_taken.call("%s %d" % [wanted, k]):
		k += 1
	return "%s %d" % [wanted, k]


func _send_lobby() -> void:
	var names: Array = []
	for pid in _order:
		names.append(_names[pid])
	for pid in _order:
		_send(pid, {"t": "lobby", "names": names, "host": pid == _host_peer})


# --- The match -----------------------------------------------------------------

# Humans take the first seats in join order; bots fill the rest.
func start_match(match_seed: int) -> void:
	sim = Simulation.new()
	sim.start_default_match(match_seed)
	sim.flashes = false
	_human_count = mini(_order.size(), sim.state.players.size())
	for k in range(_human_count):
		var peer_id: int = _order[k]
		var p: Player = sim.state.players[k]
		p.is_bot = false
		p.display_name = _names[peer_id]
		_seats[peer_id] = p.id
	started = true
	_take_tiles()
	for peer_id: int in _seats.keys():
		_send(peer_id, Snapshot.full(sim, int(_seats[peer_id]), PackedInt32Array(), [], []))


func update(delta: float) -> void:
	if not started:
		return
	_tick_accumulator += delta
	var ticks := 0
	while _tick_accumulator >= Balance.TICK_DELTA and ticks < 5:
		_tick_accumulator -= Balance.TICK_DELTA
		ticks += 1
		_tick_once()
	if ticks == 5:
		_tick_accumulator = 0.0


func _tick_once() -> void:
	sim.advance_tick()
	var tiles: PackedInt32Array = _take_tiles()
	var events: Array = sim.state.events
	sim.state.events = []
	for peer_id: int in _seats.keys():
		var me: int = int(_seats[peer_id])
		var mine: Array = []
		for e: Dictionary in events:
			var routed: Dictionary = Snapshot.route_event(e, me)
			if not routed.is_empty():
				mine.append(routed)
		_send(peer_id, Snapshot.tick(sim, me, tiles, mine, _acks.get(peer_id, [])))
		_acks[peer_id] = []


func _on_command(peer_id: int, msg: Dictionary) -> void:
	if not started or not _seats.has(peer_id):
		return
	var args: Variant = msg.get("a", [])
	var ok: bool = false
	if typeof(args) == TYPE_ARRAY:
		ok = CommandRouter.apply(sim, int(_seats[peer_id]), String(msg.get("c", "")), args)
	var list: Array = _acks.get(peer_id, [])
	list.append([int(msg.get("seq", 0)), ok])
	_acks[peer_id] = list


# Tiles that changed since the last call, packed for the wire.
func _take_tiles() -> PackedInt32Array:
	var state: GameState = sim.state
	var out := PackedInt32Array()
	for i: int in state.dirty_tiles.keys():
		out.append(Protocol.pack_tile(state, i))
	state.dirty_tiles.clear()
	return out


func _send(peer_id: int, msg: Dictionary) -> void:
	outbox.append({"peer": peer_id, "bytes": Protocol.encode(msg)})
