class_name Attack
extends RefCounted

# One active attack. The attacker has already paid troops_remaining into
# this attack; retreating refunds 75 % of what's left, natural depletion returns 0.

var attacker_id: int = 0
var defender_id: int = 0
var troops_remaining: float = 0.0
# What was originally sent (for the HUD and bots judging how a push is going).
var troops_sent: float = 0.0
# Tiles captured on the most recent ring advance (0 means the push stalled).
var tiles_taken_last_ring: int = 0
# Rings in a row that captured nothing (bots retreat from these).
var stalled_rings: int = 0
# Cheapest front tile we couldn't afford last ring, and whether Crown Shield
# held part of the front (then the attack waits instead of ending).
var cheapest_blocked_cost: float = INF
var shield_blocked: bool = false

# Defender-owned tiles currently adjacent to the attacker. Advances
# consume these next ring tick; new neighbours get added as we capture.
var front: Dictionary = {}

# Seconds remaining until the next ring advance.
var advance_timer: float = 0.0

# The ring being eaten right now. A ring is spread over the ticks of one ring
# interval (a quarter per tick at 0.4 s) so a huge front never lands in a
# single tick: ring_queue is the front as it was when the ring started,
# ring_pos how far we got, ring_new_front the front the ring is building.
var ring_active: bool = false
var ring_queue: Array = []
var ring_pos: int = 0
var ring_chunk: int = 0
var ring_new_front: Dictionary = {}

# Cached "does the front touch the defender's Crown zone?" for Crown alerts.
# Invalidate (zone_cache_valid = false) whenever `front` changes.
var zone_cache_valid: bool = false
var zone_cache_key: Vector3i = Vector3i(-1, -1, -1)
var zone_touch: bool = false

