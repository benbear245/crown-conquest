class_name Protocol
extends RefCounted

# Message format shared by server and clients. Every message is a Dictionary
# with a "t" (type) key, packed with var_to_bytes (no objects allowed) and
# compressed when large. First byte of a packet says whether it is compressed.
#
# Client -> server:  hello {name, v}   cmd {seq, c, a}   start {}
# Server -> client:  lobby {names, host}   full {...}   tick {...}   bye {msg}

const VERSION: int = 1
const DEFAULT_PORT: int = 24680
const MAX_PLAYERS: int = 8
const MAX_PACKET_BYTES: int = 1 << 20
const COMPRESS_OVER_BYTES: int = 1024
const RAW: int = 0
const ZSTD: int = 1


static func encode(msg: Dictionary) -> PackedByteArray:
	var body: PackedByteArray = var_to_bytes(msg)
	var out := PackedByteArray()
	if body.size() > COMPRESS_OVER_BYTES:
		out.append(ZSTD)
		var size := PackedByteArray()
		size.resize(4)
		size.encode_u32(0, body.size())
		out.append_array(size)
		out.append_array(body.compress(FileAccess.COMPRESSION_ZSTD))
	else:
		out.append(RAW)
		out.append_array(body)
	return out


# Returns {} for anything malformed, oversized or not a Dictionary.
static func decode(packet: PackedByteArray) -> Dictionary:
	if packet.size() < 2 or packet.size() > MAX_PACKET_BYTES:
		return {}
	var body: PackedByteArray
	if packet[0] == ZSTD:
		if packet.size() < 6:
			return {}
		var raw_size: int = packet.decode_u32(1)
		if raw_size <= 0 or raw_size > MAX_PACKET_BYTES * 8:
			return {}
		body = packet.slice(5).decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	elif packet[0] == RAW:
		body = packet.slice(1)
	else:
		return {}
	var v: Variant = bytes_to_var(body)
	if typeof(v) != TYPE_DICTIONARY or not (v as Dictionary).has("t"):
		return {}
	return v


# Tile changes travel as one int each: tile index (16 bits), owner (8 bits)
# and structure code (8 bits). Structure code: 0 none, 1 wall, 2 + building
# type for buildings, +128 while sabotaged.
const STRUCT_WALL: int = 1
const STRUCT_BUILDING_BASE: int = 2
const STRUCT_DISABLED: int = 128


static func pack_tile(state: GameState, i: int) -> int:
	var code: int = 0
	var b: Building = state.building_at_tile.get(i, null)
	if b != null:
		code = STRUCT_BUILDING_BASE + b.type
		if not b.is_active(state.match_time):
			code |= STRUCT_DISABLED
	elif state.wall_tiles.has(i):
		code = STRUCT_WALL
	return i | (int(state.owners[i]) << 16) | (code << 24)
