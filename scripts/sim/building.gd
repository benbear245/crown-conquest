class_name Building
extends RefCounted

# One structure: Fort, Fort II, Barracks, Port or Watchtower. Wall tiles live
# separately in GameState.wall_tiles because they're single-tile features
# without an effect radius.

var type: int = Balance.BUILDING_FORT
var owner_id: int = 0
var x: int = 0
var y: int = 0
var tile_idx: int = 0
# Sabotage switches a building off until this match_time.
var disabled_until: float = 0.0


func is_active(now: float) -> bool:
	return disabled_until <= now


func radius() -> int:
	match type:
		Balance.BUILDING_FORT:
			return Balance.FORT_RADIUS
		Balance.BUILDING_FORT2:
			return Balance.FORT2_RADIUS
		Balance.BUILDING_WATCHTOWER:
			return Balance.WATCHTOWER_RADIUS
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


func is_fort() -> bool:
	return type == Balance.BUILDING_FORT or type == Balance.BUILDING_FORT2


func cost() -> float:
	match type:
		Balance.BUILDING_FORT:
			return Balance.FORT_COST_BASE
		Balance.BUILDING_FORT2:
			return Balance.FORT2_COST
		Balance.BUILDING_BARRACKS:
			return Balance.BARRACKS_COST_BASE
		Balance.BUILDING_PORT:
			return Balance.PORT_COST
		Balance.BUILDING_WATCHTOWER:
			return Balance.WATCHTOWER_COST
		_:
			return 0.0


static func type_label(t: int) -> String:
	match t:
		Balance.BUILDING_FORT:
			return "Fort"
		Balance.BUILDING_FORT2:
			return "Fort II"
		Balance.BUILDING_BARRACKS:
			return "Barracks"
		Balance.BUILDING_PORT:
			return "Port"
		Balance.BUILDING_WATCHTOWER:
			return "Watchtower"
		_:
			return "Building"
