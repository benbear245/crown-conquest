class_name TrucesOps
extends RefCounted

# Truces and the Oathbreaker penalty.
#   - Offers wait for an answer: bots reply after TRUCE_BOT_RESPONSE_SEC, a
#     human answers in the HUD within TRUCE_OFFER_EXPIRE_SEC.
#   - A truce lasts TRUCE_DURATION_SEC; you can hold TRUCE_LIMIT at once.
#   - Attacking a truce partner breaks it: Oathbreaker (+20% attack cost for
#     45 s) and every bot refuses your truces for the rest of the match.
#   - Opportunist bots plan to break 20% of their truces (by attacking).


static func has_truce(a: Player, b_id: int, now: float) -> bool:
	return a.active_truces.has(b_id) and float(a.active_truces[b_id]) > now


static func truce_time_left(a: Player, b_id: int, now: float) -> float:
	if not a.active_truces.has(b_id):
		return 0.0
	return maxf(0.0, float(a.active_truces[b_id]) - now)


static func active_truce_count(p: Player, now: float) -> int:
	var n: int = 0
	for k: int in p.active_truces.keys():
		if float(p.active_truces[k]) > now:
			n += 1
	return n


static func is_oathbreaker(p: Player, now: float) -> bool:
	return p.oathbreaker_until > now


static func pending_offer(state: GameState, from_id: int, to_id: int) -> Dictionary:
	for off: Dictionary in state.pending_truces:
		if int(off["from_id"]) == from_id and int(off["to_id"]) == to_id:
			return off
	return {}


# Why from can't offer a truce to to_id right now, or "" if they can.
static func offer_block_reason(state: GameState, from_p: Player, to_p: Player) -> String:
	if from_p == null or to_p == null or not from_p.is_alive or not to_p.is_alive or from_p.id == to_p.id:
		return "Not possible"
	if has_truce(from_p, to_p.id, state.match_time):
		return "Already in a truce"
	if to_p.is_bot and from_p.oathbroken:
		return "Bots refuse truces from Oathbreakers"
	if not pending_offer(state, from_p.id, to_p.id).is_empty():
		return "Waiting for an answer"
	if active_truce_count(from_p, state.match_time) >= Balance.TRUCE_LIMIT:
		return "You have %d truces already" % Balance.TRUCE_LIMIT
	return ""


static func offer(sim: Simulation, from_id: int, to_id: int) -> bool:
	var state: GameState = sim.state
	var from_p: Player = state.get_player(from_id)
	var to_p: Player = state.get_player(to_id)
	if offer_block_reason(state, from_p, to_p) != "":
		return false
	var wait: float = Balance.TRUCE_BOT_RESPONSE_SEC if to_p.is_bot else Balance.TRUCE_OFFER_EXPIRE_SEC
	state.pending_truces.append({"from_id": from_id, "to_id": to_id, "decide_at": state.match_time + wait})
	return true


# A human's answer to a bot's offer (from the HUD).
static func respond(sim: Simulation, from_id: int, to_id: int, accepted: bool) -> bool:
	var state: GameState = sim.state
	var off: Dictionary = pending_offer(state, from_id, to_id)
	if off.is_empty():
		return false
	state.pending_truces.erase(off)
	var from_p: Player = state.get_player(from_id)
	var to_p: Player = state.get_player(to_id)
	if accepted and from_p != null and to_p != null and from_p.is_alive and to_p.is_alive \
			and active_truce_count(to_p, state.match_time) < Balance.TRUCE_LIMIT \
			and active_truce_count(from_p, state.match_time) < Balance.TRUCE_LIMIT:
		accept(sim, from_id, to_id)
		return true
	return false


# Both players record the truce. An Opportunist may secretly plan to break it.
static func accept(sim: Simulation, a_id: int, b_id: int) -> void:
	var state: GameState = sim.state
	var a: Player = state.get_player(a_id)
	var b: Player = state.get_player(b_id)
	if a == null or b == null:
		return
	var expires: float = state.match_time + Balance.TRUCE_DURATION_SEC
	a.active_truces[b_id] = expires
	b.active_truces[a_id] = expires
	a.truces_made += 1
	b.truces_made += 1
	# Neither side can attack the other: running attacks between them retreat.
	var i: int = 0
	while i < state.attacks.size():
		var atk: Attack = state.attacks[i]
		if (atk.attacker_id == a_id and atk.defender_id == b_id) or (atk.attacker_id == b_id and atk.defender_id == a_id):
			var owner: Player = state.get_player(atk.attacker_id)
			owner.troops += atk.troops_remaining * Balance.RETREAT_RETURN_FRACTION
			state.attacks.remove_at(i)
			continue
		i += 1
	for pair: Array in [[a, b], [b, a]]:
		var bot: Player = pair[0]
		if bot.is_bot and bot.personality == Balance.BOT_PERSONALITY_OPPORTUNIST \
				and state.rng.randf() < Balance.BOT_OPPORTUNIST_TRUCE_BREAK_CHANCE:
			bot.truce_break_at[(pair[1] as Player).id] = state.match_time + state.rng.randf_range(
				Balance.OPPORTUNIST_BREAK_DELAY_MIN_SEC, Balance.OPPORTUNIST_BREAK_DELAY_MAX_SEC)
	if a_id == sim.local_player_id or b_id == sim.local_player_id:
		sim.announce("Truce: %s and %s for %ds" % [a.display_name, b.display_name, int(Balance.TRUCE_DURATION_SEC)], 3.0)


static func break_truce(sim: Simulation, breaker_id: int, other_id: int) -> void:
	var state: GameState = sim.state
	var breaker: Player = state.get_player(breaker_id)
	var other: Player = state.get_player(other_id)
	if breaker == null:
		return
	breaker.active_truces.erase(other_id)
	breaker.truce_break_at.erase(other_id)
	if other != null:
		other.active_truces.erase(breaker_id)
		other.truce_break_at.erase(breaker_id)
	breaker.oathbreaker_until = state.match_time + Balance.OATHBREAKER_DURATION_SEC
	breaker.oathbroken = true
	breaker.truces_broken += 1
	sim.announce("%s broke a truce with %s and is now an Oathbreaker!" % [breaker.display_name, other.display_name if other != null else "?"], 4.0)


static func tick(sim: Simulation) -> void:
	var state: GameState = sim.state
	var now: float = state.match_time
	# Expire finished truces.
	for p: Player in state.players:
		for k: int in p.active_truces.keys():
			if float(p.active_truces[k]) <= now:
				p.active_truces.erase(k)
				p.truce_break_at.erase(k)
	# Resolve offers whose answer time has come.
	var i: int = 0
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
		var involves_local: bool = from_p.id == sim.local_player_id or to_p.id == sim.local_player_id
		if not to_p.is_bot:
			if involves_local:
				sim.announce("You let %s's truce offer expire." % from_p.display_name, 3.0)
			continue
		if bot_accepts(sim, to_p, from_p):
			accept(sim, from_p.id, to_p.id)
		elif involves_local:
			sim.announce("%s refuses your truce." % to_p.display_name, 3.0)
	_run_opportunist_plans(sim)


# Opportunists that planned to break a truce attack their partner when the
# time comes (which breaks the truce through the normal attack rules).
static func _run_opportunist_plans(sim: Simulation) -> void:
	var state: GameState = sim.state
	for p: Player in state.players:
		if p.truce_break_at.is_empty() or not p.is_alive:
			continue
		for partner_id: int in p.truce_break_at.keys():
			if float(p.truce_break_at[partner_id]) > state.match_time:
				continue
			var front: Dictionary = CombatOps.build_attack_front(state, p.id, partner_id)
			if not has_truce(p, partner_id, state.match_time) or front.is_empty():
				p.truce_break_at.erase(partner_id)   # nothing to break / no way to reach them
				continue
			# Busy with 3 attacks already? Keep the plan and try again next tick.
			var tile: Vector2i = state.idx_to_xy(int(front.keys()[0]))
			if sim.player_attack(p.id, tile.x, tile.y, Bots.random_send_fraction(p, state.rng)):
				p.truce_break_at.erase(partner_id)


static func bot_accepts(sim: Simulation, bot: Player, offerer: Player) -> bool:
	var state: GameState = sim.state
	if offerer.oathbroken:
		return false
	if active_truce_count(bot, state.match_time) >= Balance.TRUCE_LIMIT:
		return false
	var chance: float = Balance.TRUCE_ACCEPT_BASE_CHANCE
	# Already fighting someone else?
	for a: Attack in state.attacks:
		var busy: bool = (a.defender_id == bot.id and a.attacker_id != offerer.id) \
			or (a.attacker_id == bot.id and a.defender_id != offerer.id)
		if busy:
			chance += Balance.TRUCE_ACCEPT_BUSY_BONUS
			break
	if float(offerer.land) > float(bot.land) * Balance.TRUCE_ACCEPT_BIGGER_RATIO:
		chance += Balance.TRUCE_ACCEPT_BIGGER_BONUS
	return state.rng.randf() < clampf(chance, 0.0, 1.0)
