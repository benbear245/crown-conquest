class_name Boat
extends RefCounted

# A sea unit launched from a Port. Carries troops along a water path at
# Balance.BOAT_SPEED_TILES_PER_SEC, then lands and converts into either an
# expansion or an attack on the landing tile.

var owner_id: int = 0
var troops: float = 0.0
var path: PackedInt32Array = PackedInt32Array()
var progress: float = 0.0           # tiles travelled along the path
var landing_tile_x: int = 0
var landing_tile_y: int = 0
var send_fraction: float = 0.5


func current_tile_idx() -> int:
	if path.is_empty():
		return -1
	var i: int = clampi(int(progress), 0, path.size() - 1)
	return path[i]


func is_done() -> bool:
	return progress >= float(path.size() - 1)
