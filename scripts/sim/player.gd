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
var gem_tiles: int = 0                  # owned gem-field tiles, drives growth bonus

# Expansion bucket: troops committed to grabbing free land. Refunded when done.
var expansion_troops: float = 0.0
var expansion_timer: float = 0.0        # seconds until the next ring tick

# Bot think cadence (ignored for the local player).
var think_timer: float = 0.0

# HUD alert when an attack enters this player's Crown zone.
var crown_alert_until: float = 0.0
var crowns_captured: int = 0


func troop_cap() -> float:
	return Balance.TROOP_CAP_BASE + Balance.TROOP_CAP_PER_LAND * float(land)


# Growth rate in troops/second at this player's current state. Positive when
# below the cap, negative (shrink toward the cap) when over it.
func troops_per_second_at(cap: float) -> float:
	if troops > cap:
		return -(troops - cap) * Balance.OVER_CAP_SHRINK_PER_SEC
	if cap <= 0.0:
		return 0.0
	var interest := Balance.GROWTH_INTEREST_RATE_PER_SEC * troops * (1.0 - troops / cap)
	return Balance.GROWTH_BASE_PER_SEC + Balance.GROWTH_PER_LAND_PER_SEC * float(land) + interest
