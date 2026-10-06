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

# Defender-owned tiles currently adjacent to the attacker. Advances
# consume these next ring tick; new neighbours get added as we capture.
var front: Dictionary = {}

# Seconds remaining until the next ring advance.
var advance_timer: float = 0.0
