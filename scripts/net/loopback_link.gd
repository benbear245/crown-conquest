class_name LoopbackLink
extends RefCounted

# Two in-memory queues standing in for a network connection between a client
# and a NetHost in the same app. Packets still go through Protocol encoding,
# so "practice online" exercises exactly what travels over a real network.

var _to_server: Array[PackedByteArray] = []
var _to_client: Array[PackedByteArray] = []


func send(packet: PackedByteArray) -> void:
	_to_server.append(packet)


func receive() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = _to_client
	_to_client = []
	return out


func is_connected_to_server() -> bool:
	return true


func close() -> void:
	_to_server.clear()
	_to_client.clear()


# Host side.
func take_for_server() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = _to_server
	_to_server = []
	return out


func push_to_client(packet: PackedByteArray) -> void:
	_to_client.append(packet)
