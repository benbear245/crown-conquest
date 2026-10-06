class_name TrucesOps
extends RefCounted

# Truces and the Oathbreaker penalty. Called from Simulation each tick to:
#   - resolve pending bot replies (2 s after an offer),
#   - expire active truces,
#   - give Opportunist bots a chance to break their truces.


static func has_truce(a: Player, b_id: int, now: float) -> bool:
	if not a.active_truces.has(b_id):
		return false
	return float(a.active_truces[b_id]) > now


static func active_truce_count(p: Player, now: float) -> int:
	var n := 0
	for k in p.active_truces.keys():
		if float(p.active_truces[k]) > now:
			n += 1
	return n


static func is_oathbreaker(p: Player, now: float) -> bool:
	return p.oathbreaker_until > now


# Called by Simulation.player_offer_truce (or the bot analogue). Queues a
# pending offer that bots answer 2 s later; a human target would accept via UI.
static func offer(sim: Simulation, from_id: int, to_id: int) -> bool:
	if from_id == to_id:
		return false
	var state: GameState = sim.state
	var from_p: Player = state.get_player(from_id)
	var to_p: Player = state.get_player(to_id)
	if from_p == null or to_p == null or not from_p.is_alive or not to_p.is_alive:
		return false
	if has_truce(from_p, to_id, state.match_time):
		return false
	if active_truce_count(from_p, state.match_time) >= Balance.TRUCE_LIMIT:
		return false
	if to_p.refuses_all_truces:
		state.active_announcement_text = "%s refuses your truce." % to_p.display_name
		state.active_announcement_until = state.match_time + 3.0
		return false
	# Dedupe: don't stack identical pending offers.
	for off_v in state.pending_truces:
		var off: Dictionary = off_v
		if int(off["from_id"]) == from_id and int(off["to_id"]) == to_id:
			return false
	state.pending_truces.append({
		"from_id": from_id,
		"to_id": to_id,
		"decide_at": state.match_time + Balance.TRUCE_BOT_RESPONSE_SEC,
	})
	return true


# Immediate accept — bypasses the pending list. Both players record the truce.
static func accept(sim: Simulation, a_id: int, b_id: int) -> void:
	var state: GameState = sim.state
	var a: Player = state.get_player(a_id)
	var b: Player = state.get_player(b_id)
	if a == null or b == null:
		return
	var expires: float = state.match_time + Balance.TRUCE_DURATION_SEC
	a.active_truces[b_id] = expires
	b.active_truces[a_id] = expires
	state.active_announcement_text = "Truce — %s and %s" % [a.display_name, b.display_name]
	state.active_announcement_until = state.match_time + 3.0


# A player attacking someone they have a truce with breaks it: Oathbreaker +20%
# cost for 45 s and no bot will accept their truces for the rest of the match.
static func break_truce(sim: Simulation, breaker_id: int, other_id: int) -> void:
	var state: GameState = sim.state
	var breaker: Player = state.get_player(breaker_id)
	var other: Player = state.get_player(other_id)
	if breaker == null:
		return
	breaker.active_truces.erase(other_id)
	if other != null:
		other.active_truces.erase(breaker_id)
	breaker.oathbreaker_until = state.match_time + Balance.OATHBREAKER_DURATION_SEC
	breaker.refuses_all_truces = true
	state.active_announcement_text = "%s is now an Oathbreaker!" % breaker.display_name
	state.active_announcement_until = state.match_time + 3.0


static func tick(sim: Simulation) -> void:
	var state: GameState = sim.state
	# Expire any active truces that have run out.
	for p: Player in state.players:
		if p.active_truces.is_empty():
			continue
		var dead: Array = []
		for k in p.active_truces.keys():
			if float(p.active_truces[k]) <= state.match_time:
				dead.append(k)
		for k in dead:
			p.active_truces.erase(k)
	# Resolve bot replies to pending offers.
	var i := 0
	while i < state.pending_truces.size():
		var off: Dictionary = state.pending_truces[i]
		if state.match_time < float(off["decide_at"]):
			i += 1
			continue
		var from_id: int = int(off["from_id"])
		var to_id: int = int(off["to_id"])
		state.pending_truces.remove_at(i)
		var from_p: Player = state.get_player(from_id)
		var to_p: Player = state.get_player(to_id)
		if from_p == null or to_p == null or not from_p.is_alive or not to_p.is_alive:
			continue
		if not to_p.is_bot:
			# The HUD handles human replies via explicit UI; skip here.
			continue
		if _bot_accepts(sim, to_p, from_p):
			accept(sim, from_id, to_id)
		else:
			state.active_announcement_text = "%s declines %s's truce." % [to_p.display_name, from_p.display_name]
			state.active_announcement_until = state.match_time + 3.0
	# Opportunist break chance: about 20% per minute while they hold a truce.
	for p: Player in state.players:
		if not p.is_alive or not p.is_bot:
			continue
		if p.personality != Balance.BOT_PERSONALITY_OPPORTUNIST:
			continue
		if p.refuses_all_truces or p.active_truces.is_empty():
			continue
		var per_tick_chance: float = Balance.BOT_OPPORTUNIST_TRUCE_BREAK_CHANCE * Balance.TICK_DELTA / 60.0
		if sim.state.rng.randf() < per_tick_chance:
			var victim_id: int = int(p.active_truces.keys()[0])
			break_truce(sim, p.id, victim_id)


static func _bot_accepts(sim: Simulation, bot: Player, offerer: Player) -> bool:
	if bot.refuses_all_truces:
		return false
	if active_truce_count(bot, sim.state.match_time) >= Balance.TRUCE_LIMIT:
		return false
	var chance: float = 0.50
	# Already fighting someone else?
	for a_v in sim.state.attacks:
		var a: Attack = a_v
		if a.defender_id == bot.id and a.attacker_id != offerer.id:
			chance += 0.25
			break
		if a.attacker_id == bot.id and a.defender_id != offerer.id:
			chance += 0.10
			break
	# Offerer bigger?
	if offerer.land > bot.land * 1.3:
		chance += 0.25
	# Opportunist is a bit flakier.
	if bot.personality == Balance.BOT_PERSONALITY_OPPORTUNIST:
		chance -= 0.05
	return sim.state.rng.randf() < clampf(chance, 0.05, 0.95)
