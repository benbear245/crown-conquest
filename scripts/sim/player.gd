class_name Player
extends RefCounted

# Pure-data player record. Owned by GameState. No node/scene access here.

var id: int = 0
var display_name: String = ""
var color: Color = Color.WHITE
var troops: float = 0.0
var land: int = 0
var is_alive: bool = true
var is_bot: bool = false
var difficulty: int = 0        # Balance.BOT_DIFFICULTY_*
var personality: int = 0       # Balance.BOT_PERSONALITY_*

# Crown position (centre tile). (-1, -1) means not placed.
var crown_x: int = -1
var crown_y: int = -1

# Set of tile indices on this player's border (touching unowned/enemy).
# Updated incrementally by sim code so we never scan the whole map.
var border: Dictionary = {}

# Peak land this match (for XP after a match).
var peak_land: int = 0


func troop_cap() -> float:
	return Balance.TROOP_CAP_BASE + Balance.TROOP_CAP_PER_LAND * float(land)
