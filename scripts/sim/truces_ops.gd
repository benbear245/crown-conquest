class_name TrucesOps
extends RefCounted

# Truces and the Oathbreaker penalty. Called from Simulation each tick to:
#   - resolve pending bot replies (2 s after an offer),
#   - expire offers to humans nobody answered,
#   - expire active truces,
#   - give Opportunist bots a chance to break their truces.


static func has_truce(a: Player, b_id: int, now: float) -> bool:
	return float(a.active_truces.get(b_id, 0.0)) > now


static func active_truce_count(p: Player, now: float) -> int:
	var n := 0
	for k in p.active_truces.keys():
		if float(p.active_truces[k]) > now:
			n += 1
	return n


static func is_oathbreaker(p: Player, now: float) -> bool:
	return p.oathbreaker_until > now


# Why from can't offer a truce to to right now, or "" if they can.
static func offer_blocker(sim: Simulation, from_id: int, to_id: int) -> String:
	var state: GameState = sim.state
	var from_p: Player = state.get_player(from_id)
	var to_p: Player = state.get_player(to_id)
	if from_id == to_id or from_p == null or to_p == null or not from_p.is_alive or not to_p.is_alive:
		return "No target"
	var now: float = state.match_time
	if has_truce(from_p, to_id, now):
		return "Already in truce"
	if active_truce_count(from_p, now) >= Balance.TRUCE_LIMIT:
		return "At truce limit (%d)" % Balance.TRUCE_LIMIT
	if to_p.is_bot and from_p.refuses_all_truces:
		return "Oathbreaker — bots refuse you"
	if pending_offer(state, from_id, to_id) >= 0:
		return "Offer sent…"
	return ""


static func pending_offer(state: GameState, from_id: int, to_id: int) -> int:
	for i in range(state.pending_truces.size()):
		var off: Dictionary = state.pending_truces[i]
		if int(off["from_id"]) == from_id and int(off["to_id"]) == to_id:
			return i
	return -1


# Queues an offer. Bots answer after TRUCE_BOT_RESPONSE_SEC; humans answer
# with the HUD (accept / decline) before TRUCE_HUMAN_REPLY_SEC runs out.
static func offer(sim: Simulation, from_id: int, to_id: int) -> bool:
	if offer_blocker(sim, from_id, to_id) != "":
		return false
	var state: GameState = sim.state
	var to_p: Player = state.get_player(to_id)
	var wait: float = Balance.TRUCE_BOT_RESPONSE_SEC if to_p.is_bot else Balance.TRUCE_HUMAN_REPLY_SEC
	state.pending_truces.append({"from_id": from_id, "to_id": to_id, "decide_at": state.match_time + wait})
	if not to_p.is_bot:
		sim.emit({"type": "truce_offer", "from_id": from_id, "to_id": to_id})
	return true


# A human's answer to a pending offer made to them.
static func answer(sim: Simulation, to_id: int, from_id: int, accepted: bool) -> bool:
	var state: GameState = sim.state
	var at: int = pending_offer(state, from_id, to_id)
	if at < 0:
		return false
	state.pending_truces.remove_at(at)
	if accepted:
		var to_p: Player = state.get_player(to_id)
		if to_p != null and active_truce_count(to_p, state.match_time) < Balance.TRUCE_LIMIT:
			accept(sim, from_id, to_id)
			return true
	_announce_decline(sim, to_id, from_id)
	return true


# Immediate accept. Both players record the truce.
static func accept(sim: Simulation, a_id: int, b_id: int) -> void:
	var state: GameState = sim.state
	var a: Player = state.get_player(a_id)
	var b: Player = state.get_player(b_id)
	if a == null or b == null:
		return
	var expires: float = state.match_time + Balance.TRUCE_DURATION_SEC
	a.active_truces[b_id] = expires
	b.active_truces[a_id] = expires
	sim.announce("Truce — %s and %s" % [a.display_name, b.display_name])


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
		other.grudges[breaker_id] = state.match_time + Balance.BOT_GRUDGE_SEC
	breaker.oathbreaker_until = state.match_time + Balance.OATHBREAKER_DURATION_SEC
	breaker.refuses_all_truces = true
	sim.announce("%s is now an Oathbreaker!" % breaker.display_name)


static func tick(sim: Simulation) -> void:
	var state: GameState = sim.state
	var now: float = state.match_time
	for p: Player in state.players:
		for k in p.active_truces.keys():
			if float(p.active_truces[k]) <= now:
				p.active_truces.erase(k)
	var i := 0
	while i < state.pending_truces.size():
		var off: Dictionary = state.pending_truces[i]
		if now < float(off["decide_at"]):
			i += 1
			continue
		state.pending_truces.remove_at(i)
		var from_p: Player = state.get_player(int(off["from_id"]))
		var to_p: Player = state.get_player(int(off["to_id"]))
		if from_p == null or to_p == null or not from_p.is_alive or not to_p.is_alive:
			continue
		if to_p.is_bot and _bot_accepts(sim, to_p, from_p):
			accept(sim, from_p.id, to_p.id)
		else:
			# Bots said no, or the human let the offer run out.
			_announce_decline(sim, to_p.id, from_p.id)
	# Opportunist break chance: about 20% per minute while they hold a truce.
	for p: Player in state.players:
		if not p.is_alive or not p.is_bot or p.personality != Balance.BOT_PERSONALITY_OPPORTUNIST:
			continue
		if p.refuses_all_truces or p.active_truces.is_empty():
			continue
		var per_tick_chance: float = Balance.BOT_OPPORTUNIST_TRUCE_BREAK_CHANCE * Balance.TICK_DELTA / 60.0
		if state.rng.randf() < per_tick_chance:
			var victim_id: int = int(p.active_truces.keys()[0])
			var victim: Player = state.get_player(victim_id)
			# Breaking a truce means attacking: the Opportunist turns on its partner.
			if victim != null and victim.is_alive and CombatOps.can_attack(sim, p, victim_id):
				var front: Dictionary = CombatOps.build_attack_front(state, p, victim_id)
				var send: float = floorf(p.troops * 0.4)
				if not front.is_empty() and send > 0.0:
					p.troops -= send
					CombatOps.open_attack(sim, p, victim_id, send, front)
					continue
			break_truce(sim, p.id, victim_id)


static func _announce_decline(sim: Simulation, decliner_id: int, offerer_id: int) -> void:
	var d: Player = sim.state.get_player(decliner_id)
	var o: Player = sim.state.get_player(offerer_id)
	if d != null and o != null:
		sim.announce("%s declines %s's truce." % [d.display_name, o.display_name], [decliner_id, offerer_id])


static func _bot_accepts(sim: Simulation, bot: Player, offerer: Player) -> bool:
	var now: float = sim.state.match_time
	if offerer.refuses_all_truces:
		return false
	if active_truce_count(bot, now) >= Balance.TRUCE_LIMIT:
		return false
	if float(bot.grudges.get(offerer.id, 0.0)) > now:
		return false
	var chance: float = 0.50
	# Already fighting someone else?
	for a: Attack in sim.state.attacks:
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
