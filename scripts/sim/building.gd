class_name Building
extends RefCounted

# One structure. Fort, Fort II, Barracks or Port. Wall tiles live separately
# in GameState.wall_tiles because they're single-tile features without an
# effect radius.

var type: int = Balance.BUILDING_FORT
var owner_id: int = 0
var x: int = 0
var y: int = 0
var tile_idx: int = 0
# Troops actually paid (including a Fort II upgrade). Loot is a share of this.
var paid: float = 0.0


func radius() -> int:
	match type:
		Balance.BUILDING_FORT:
			return Balance.FORT_RADIUS
		Balance.BUILDING_FORT2:
			return Balance.FORT2_RADIUS
		_:
			return 0


func defense_mult() -> float:
	match type:
		Balance.BUILDING_FORT:
			return Balance.FORT_DEFENSE
		Balance.BUILDING_FORT2:
			return Balance.FORT2_DEFENSE
		_:
			return 1.0

