class_name Attack
extends RefCounted

# One active attack. The attacker has already paid troops_remaining into
# this attack; retreating refunds 75 % of what's left, natural depletion returns 0.

var attacker_id: int = 0
var defender_id: int = 0
var troops_remaining: float = 0.0

# Defender-owned tiles currently adjacent to the attacker. Advances
# consume these next ring tick; new neighbours get added as we capture.
var front: Dictionary = {}

# Seconds remaining until the next ring advance.
var advance_timer: float = 0.0
# Total cost of the front tiles the last ring couldn't afford (0 = none
# stalled). Hard bots read their own attacks' value to decide on retreating.
var last_ring_cost: float = 0.0
