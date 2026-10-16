class_name ENetLink
extends RefCounted

# A client's connection to a NetHost over the network (ENet, UDP). Same
# send / receive shape as LoopbackLink so a session can use either.

signal lost(reason: String)

var _peer: ENetMultiplayerPeer
var _was_connected: bool = false


func connect_to(address: String, port: int = Protocol.DEFAULT_PORT) -> int:
	_peer = ENetMultiplayerPeer.new()
	var err: int = _peer.create_client(address, port)
	if err != OK:
		_peer = null
	return err


func is_connected_to_server() -> bool:
	return _peer != null and _peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func send(packet: PackedByteArray) -> void:
	if not is_connected_to_server():
		return
	_peer.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	_peer.set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	_peer.put_packet(packet)


func receive() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if _peer == null:
		return out
	_peer.poll()
	var status: int = _peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_CONNECTED:
		_was_connected = true
	elif status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_peer = null
		lost.emit("Lost connection to the host." if _was_connected else "Couldn't reach the host.")
		return out
	while _peer.get_available_packet_count() > 0:
		out.append(_peer.get_packet())
	return out


func close() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
