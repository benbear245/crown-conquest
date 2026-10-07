class_name NetSession
extends GameSession

# Online play: commands go to the host, and the host's personal updates keep
# a Mirror of the match current. The link is a LoopbackLink (host's own
# player, or practice on one device) or an ENetLink (another phone).

var player_name: String = "Player"

var _link: RefCounted              # LoopbackLink or ENetLink
var _mirror: Mirror = Mirror.new()
var _hello_sent: bool = false
var _seq: int = 0
var _pending: Dictionary = {}      # seq -> Callable


func _init(link: RefCounted, name_: String) -> void:
	online = true
	_link = link
	player_name = name_
	if _link is ENetLink:
		(_link as ENetLink).lost.connect(func(reason: String) -> void: ended.emit(reason))


func sim() -> Simulation:
	return _mirror.sim if _mirror.is_ready else null


func update(_delta: float) -> Array:
	if not _hello_sent and _link.is_connected_to_server():
		_hello_sent = true
		_link.send(Protocol.encode({"t": "hello", "name": player_name, "v": Protocol.VERSION}))
	var events: Array = []
	for packet: PackedByteArray in _link.receive():
		var msg: Dictionary = Protocol.decode(packet)
		if msg.is_empty():
			continue
		match String(msg["t"]):
			"lobby":
				lobby_changed.emit(msg.get("names", []), bool(msg.get("host", false)))
			"full":
				_mirror = Mirror.new()
				_mirror.apply(msg)
				match_ready.emit()
				_run_acks(msg)
			"tick":
				events.append_array(_mirror.apply(msg))
				_run_acks(msg)
			"bye":
				ended.emit(String(msg.get("msg", "Disconnected.")))
	return events


func send(cmd: String, args: Array, on_result: Callable = Callable()) -> void:
	_seq += 1
	if on_result.is_valid():
		_pending[_seq] = on_result
	_link.send(Protocol.encode({"t": "cmd", "seq": _seq, "c": cmd, "a": args}))


func request_start() -> void:
	_link.send(Protocol.encode({"t": "start"}))


func close() -> void:
	_link.close()


func _run_acks(msg: Dictionary) -> void:
	for ack: Array in msg.get("acks", []):
		var cb: Variant = _pending.get(int(ack[0]))
		_pending.erase(int(ack[0]))
		if cb is Callable and (cb as Callable).is_valid():
			(cb as Callable).call(bool(ack[1]))
