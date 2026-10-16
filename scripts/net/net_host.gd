class_name NetHost
extends Node

# Hosts a MatchServer. Players can reach it two ways at once:
#   - over the network (ENet, UDP) when listen() is called — other phones on
#     the same Wi-Fi, or anyone on a dedicated server;
#   - through a LoopbackLink — the host's own player in the same app.

const LOOPBACK_PEER_ID: int = 1     # ENet's own server id is 1, never used by a remote peer

var server: MatchServer
var _enet: ENetMultiplayerPeer
var _loopback: LoopbackLink


func _init(host_is_local: bool = true) -> void:
	# A dedicated server has no host player of its own: the first person to
	# join becomes the one who can press Start.
	server = MatchServer.new(LOOPBACK_PEER_ID if host_is_local else -1)


# Opens the UDP port. Returns an Error.
func listen(port: int = Protocol.DEFAULT_PORT) -> int:
	_enet = ENetMultiplayerPeer.new()
	var err: int = _enet.create_server(port, Protocol.MAX_PLAYERS)
	if err != OK:
		_enet = null
		return err
	_enet.peer_connected.connect(func(_id: int) -> void: pass)
	_enet.peer_disconnected.connect(func(id: int) -> void: server.peer_left(id))
	return OK


func attach_loopback(link: LoopbackLink) -> void:
	_loopback = link


func stop() -> void:
	if _enet != null:
		_enet.close()
		_enet = null


func _process(delta: float) -> void:
	_poll_inputs()
	server.update(delta)
	_flush()


func _poll_inputs() -> void:
	if _loopback != null:
		for packet in _loopback.take_for_server():
			server.receive(LOOPBACK_PEER_ID, packet)
	if _enet == null:
		return
	_enet.poll()
	while _enet.get_available_packet_count() > 0:
		var from: int = _enet.get_packet_peer()
		var packet: PackedByteArray = _enet.get_packet()
		server.receive(from, packet)


func _flush() -> void:
	for m: Dictionary in server.outbox:
		var peer: int = int(m["peer"])
		if peer == LOOPBACK_PEER_ID and _loopback != null:
			_loopback.push_to_client(m["bytes"])
		elif _enet != null:
			_enet.set_target_peer(peer)
			_enet.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
			_enet.put_packet(m["bytes"])
	server.outbox.clear()


# Private network addresses to show on the host's screen ("Join 192.168.1.20").
static func lan_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a: String in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			out.append(a)
	return out
