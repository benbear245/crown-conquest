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
# The bot's most recent BotScan (what it saw on its last think).
var bot_scan: RefCounted = null
# Bot move counts by type ("expand", "attack", ...), for the simulator report.
var bot_actions: Dictionary = {}

# HUD alert when an attack enters this player's Crown zone.
var crown_alert_until: float = 0.0
var crown_alert_attacker: int = 0
var crowns_captured: int = 0
var eliminated_at: float = -1.0

# Crown move (once per match). While match_time < crown_move_until the Crown
# has no special defense.
var crown_moved: bool = false
var crown_move_until: float = 0.0

# Final Siege switches Keep upgrades off (set by Simulation when it begins).
var keep_disabled: bool = false

# Usage stats for the balance simulator: building type -> times built,
# ability id -> times used.
var buildings_built: Dictionary = {}
var abilities_used: Dictionary = {}
var boats_launched: int = 0
var truces_made: int = 0
var truces_broken: int = 0

# Buildings (counts for cost scaling and limit checks).
var fort_count: int = 0           # includes Fort II (Fort II upgrades count as one Fort)
var barracks_count: int = 0
var port_count: int = 0
var wall_count: int = 0

# Keep upgrade level: 0 base, 1-3 upgraded.
var keep_level: int = 0

# Fort tile indices this player owns (used for defense lookup, max 6).
var fort_tiles: PackedInt32Array = PackedInt32Array()

# Ability state. "*_cd_until" is the absolute match_time when the cooldown ends;
# "*_until" is when the active effect ends (or 0.0 if not active).
var swift_march_cd_until: float = 0.0
var swift_march_until: float = 0.0
var crown_shield_cd_until: float = 0.0
var crown_shield_until: float = 0.0
var rally_cd_until: float = 0.0
var rally_until: float = 0.0
var bombard_cd_until: float = 0.0
var bombard_until: float = 0.0

# Bot ability-think jitter so they don't all hit buttons on the same tick.
var ability_think_timer: float = 0.0

# Truces + Oathbreaker.
# other_player_id -> absolute match_time this truce expires.
var active_truces: Dictionary = {}
var oathbreaker_until: float = 0.0
# Broke a truce at some point this match: every bot refuses their truces.
var oathbroken: bool = false
# Opportunist plan: partner_id -> match_time it will attack (break the truce).
var truce_break_at: Dictionary = {}
# Bots: no new truce offers before this time.
var truce_offer_cd_until: float = 0.0


func troop_cap() -> float:
	var cap: float = Balance.TROOP_CAP_BASE + Balance.TROOP_CAP_PER_LAND * float(land)
	cap *= 1.0 + Balance.BARRACKS_TROOP_CAP_BONUS * float(barracks_count)
	if keep_level >= 3 and not keep_disabled:
		cap *= 1.0 + Balance.KEEP_3_TROOP_CAP_BONUS
	return cap


func crown_zone_radius() -> int:
	if keep_level < 0 or keep_level >= Balance.KEEP_ZONE_RADIUS.size():
		return Balance.CROWN_ZONE_RADIUS
	return Balance.KEEP_ZONE_RADIUS[keep_level]


func crown_zone_defense() -> float:
	if keep_level < 0 or keep_level >= Balance.KEEP_ZONE_DEF.size():
		return Balance.CROWN_ZONE_DEFENSE
	return Balance.KEEP_ZONE_DEF[keep_level]


func crown_tile_defense() -> float:
	if keep_level < 0 or keep_level >= Balance.KEEP_CROWN_TILE_DEF.size():
		return Balance.CROWN_TILE_DEFENSE
	return Balance.KEEP_CROWN_TILE_DEF[keep_level]


# Growth rate in troops/second at this player's current state. Positive when
# below the cap, negative (shrink toward the cap) when over it.
func troops_per_second_at(cap: float) -> float:
	if troops > cap:
		return -(troops - cap) * Balance.OVER_CAP_SHRINK_PER_SEC
	if cap <= 0.0:
		return 0.0
	var interest := Balance.GROWTH_INTEREST_RATE_PER_SEC * troops * (1.0 - troops / cap)
	return Balance.GROWTH_BASE_PER_SEC + Balance.GROWTH_PER_LAND_PER_SEC * float(land) + interest
