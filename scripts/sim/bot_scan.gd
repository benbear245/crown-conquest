class_name BotScan
extends RefCounted

# What a bot "sees" when it thinks: one pass over (a sample of) its border.
# Sampling keeps a think cheap on big empires; the result is plain data.

var free_tiles: PackedInt32Array = PackedInt32Array()     # unowned land touching us
var ruins_tiles: PackedInt32Array = PackedInt32Array()    # Ruins touching us
var enemy_tile: Dictionary = {}       # enemy id -> one of their tiles touching us
var enemy_contact: Dictionary = {}    # enemy id -> how many sampled border contacts
var threat_tile: int = -1             # our border tile touching an enemy, nearest our Crown
var threat_dist2: int = 1 << 30       # its squared distance to our Crown
var busy: Dictionary = {}             # player id -> true if in any attack (either side)
var attackers_on_me: Dictionary = {}  # attacker id -> troops they are pushing into us
var my_attacks: Array[Attack] = []
var coast_tiles: PackedInt32Array = PackedInt32Array()    # our border tiles next to water


static func scan(sim: Simulation, p: Player) -> BotScan:
	var out := BotScan.new()
	var state: GameState = sim.state
	var owners: PackedByteArray = state.owners
	var blocked: PackedByteArray = state.blocked
	var w: int = state.width
	var h: int = state.height
	for a: Attack in state.attacks:
		out.busy[a.attacker_id] = true
		out.busy[a.defender_id] = true
		if a.defender_id == p.id:
			out.attackers_on_me[a.attacker_id] = float(out.attackers_on_me.get(a.attacker_id, 0.0)) + a.troops_remaining
		elif a.attacker_id == p.id:
			out.my_attacks.append(a)
	var keys: Array = p.border.keys()
	var n: int = keys.size()
	if n == 0:
		return out
	var stride: int = maxi(1, ceili(float(n) / float(Balance.BOT_SCAN_SAMPLES)))
	var start: int = state.rng.randi_range(0, stride - 1)
	var k: int = start
	while k < n:
		var i: int = keys[k]
		k += stride
		var x: int = i % w
		@warning_ignore("integer_division")
		var y: int = i / w
		for dir in range(4):
			var ni: int
			if dir == 0:
				if x + 1 >= w:
					continue
				ni = i + 1
			elif dir == 1:
				if x <= 0:
					continue
				ni = i - 1
			elif dir == 2:
				if y + 1 >= h:
					continue
				ni = i + w
			else:
				if y <= 0:
					continue
				ni = i - w
			var ow: int = owners[ni]
			if blocked[ni] == 1:
				if out.coast_tiles.size() < 16 and state.terrain[ni] == Balance.TERRAIN_WATER and (out.coast_tiles.is_empty() or out.coast_tiles[out.coast_tiles.size() - 1] != i):
					out.coast_tiles.append(i)
				continue
			if ow == p.id:
				continue
			if ow == 0:
				if out.free_tiles.size() < 24:
					out.free_tiles.append(ni)
			elif ow == GameState.RUINS_OWNER_ID:
				if out.ruins_tiles.size() < 24:
					out.ruins_tiles.append(ni)
			else:
				if not out.enemy_tile.has(ow):
					out.enemy_tile[ow] = ni
				out.enemy_contact[ow] = int(out.enemy_contact.get(ow, 0)) + 1
				if p.crown_x >= 0:
					var dx: int = x - p.crown_x
					var dy: int = y - p.crown_y
					var d2: int = dx * dx + dy * dy
					if d2 < out.threat_dist2:
						out.threat_dist2 = d2
						out.threat_tile = i
	return out


func has_free_land() -> bool:
	return not free_tiles.is_empty() or not ruins_tiles.is_empty()


func threatened() -> bool:
	return threat_dist2 <= Balance.BOT_THREAT_RADIUS * Balance.BOT_THREAT_RADIUS or not attackers_on_me.is_empty()
