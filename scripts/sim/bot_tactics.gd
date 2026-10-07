class_name BotTactics
extends RefCounted

# Bot abilities, spying, truce offers, retreats and Crown moves.


# --- Abilities (own timer, every 1-2 s) ---------------------------------------

static func use_abilities(sim: Simulation, p: Player) -> void:
	if p.difficulty < Balance.BOT_DIFFICULTY_NORMAL:
		return
	var state: GameState = sim.state
	var now: float = state.match_time
	# Crown Shield: pop it if an enemy is pressing the Crown zone right now.
	if p.crown_alert_until > now and AbilitiesOps.is_ready(AbilitiesOps.ID_CROWN_SHIELD, p, sim):
		sim.player_activate_ability(p.id, AbilitiesOps.ID_CROWN_SHIELD)
	# Swift March: during the land rush, while there's free land to grab.
	if now < 180.0 and p.expansion_troops > 0.0 and AbilitiesOps.is_ready(AbilitiesOps.ID_SWIFT_MARCH, p, sim):
		sim.player_activate_ability(p.id, AbilitiesOps.ID_SWIFT_MARCH)
	if p.difficulty < Balance.BOT_DIFFICULTY_HARD:
		return
	# Hard: Bombard + Rally together on an enemy Crown or a Fort in the way.
	var target: Vector2i = _bombard_target(sim, p)
	var big_attack: bool = false
	for a: Attack in sim.attacks_by(p.id):
		if a.troops_remaining > p.troops * 0.3:
			big_attack = true
	if target.x >= 0 and AbilitiesOps.is_ready(AbilitiesOps.ID_BOMBARD, p, sim):
		sim.player_activate_ability(p.id, AbilitiesOps.ID_BOMBARD, target.x, target.y)
	if big_attack and AbilitiesOps.is_ready(AbilitiesOps.ID_RALLY, p, sim):
		sim.player_activate_ability(p.id, AbilitiesOps.ID_RALLY)
	# Disinformation: look strong when someone is circling.
	if p.watched_until > now and IntelOps.disinfo_blocker(sim, p) == "":
		sim.player_disinformation(p.id, true)
	_side_intel(sim, p)


# Hard bots spy as a side action: exact numbers on whoever they're attacking,
# and the plans of whoever is attacking them.
static func _side_intel(sim: Simulation, p: Player) -> void:
	var state: GameState = sim.state
	var now: float = state.match_time
	if state.rng.randf() > 0.08:
		return
	var target: Player = state.get_player(p.plan_target_id)
	if target != null and target.is_alive and sim.active_attack_count(p.id) > 0 \
			and not IntelOps.has_live_spy(p, target.id, now) \
			and IntelOps.action_blocker(sim, p, target.id, Balance.SPY_SPY) == "":
		sim.player_spy(p.id, target.id, Balance.SPY_SPY)
		return
	for a: Attack in state.attacks:
		if a.defender_id == p.id and IntelOps.action_blocker(sim, p, a.attacker_id, Balance.SPY_PLANS) == "":
			sim.player_spy(p.id, a.attacker_id, Balance.SPY_PLANS)
			return


# Nearest enemy Crown in range, else an enemy Fort next to one of our attacks.
static func _bombard_target(sim: Simulation, p: Player) -> Vector2i:
	var state: GameState = sim.state
	var r: int = Balance.BOMBARD_RANGE_TILES
	for other: Player in state.players:
		if other.id == p.id or not other.is_alive or other.crown_x < 0:
			continue
		if TrucesOps.has_truce(p, other.id, state.match_time):
			continue
		if AbilitiesOps.in_range_of_border(sim, p, other.crown_x, other.crown_y, r):
			return Vector2i(other.crown_x, other.crown_y)
	for a: Attack in sim.attacks_by(p.id):
		for b: Building in state.buildings:
			if b.owner_id == a.defender_id and b.is_fort() and AbilitiesOps.in_range_of_border(sim, p, b.x, b.y, r):
				return Vector2i(b.x, b.y)
	return Vector2i(-1, -1)


# --- Attacks in progress (every think) ------------------------------------------

static func manage_attacks(sim: Simulation, p: Player) -> void:
	var state: GameState = sim.state
	var now: float = state.match_time
	var mine: Array = sim.attacks_by(p.id)
	for i in range(mine.size() - 1, -1, -1):
		var a: Attack = mine[i]
		var retreat: bool = false
		# Hard: pull out of attacks that can't afford their front any more.
		if p.difficulty == Balance.BOT_DIFFICULTY_HARD and a.last_ring_cost > 0.0 \
				and a.troops_remaining < a.last_ring_cost * Balance.BOT_HARD_RETREAT_RATIO:
			retreat = true
		# Easy: stop before reaching a human's Crown zone before 4:00.
		var def: Player = state.get_player(a.defender_id)
		if def != null and Bots._easy_spares_crown(p, def, now):
			for ni: int in a.front.keys():
				if Bots._near_crown(state, def, ni, 2):
					retreat = true
					break
		if retreat:
			sim.player_retreat(p.id, i)


# --- Spying, truces and Crown moves (scored like any other move) ---------------

static func add_moves(sim: Simulation, p: Player, ctx: Dictionary, moves: Array[Dictionary]) -> void:
	var state: GameState = sim.state
	var now: float = ctx["now"]
	var neighbours: Dictionary = ctx["neighbours"]
	var hard: bool = p.difficulty == Balance.BOT_DIFFICULTY_HARD
	var opportunist: bool = p.personality == Balance.BOT_PERSONALITY_OPPORTUNIST
	if hard or (opportunist and p.difficulty == Balance.BOT_DIFFICULTY_NORMAL):
		_add_spy_moves(sim, p, ctx, moves)
	if p.difficulty >= Balance.BOT_DIFFICULTY_NORMAL and not p.refuses_all_truces:
		var attackers: Dictionary = ctx["attacked_by"]
		# Pressed on two fronts: try to calm one of them down.
		if attackers.size() >= 2 or (attackers.size() == 1 and float(ctx["ratio"]) < 0.3):
			if state.rng.randf() < Balance.BOT_TRUCE_OFFER_CHANCE * 4.0:
				for aid: int in attackers.keys():
					if TrucesOps.offer_blocker(sim, p.id, aid) == "":
						moves.append({"kind": Bots.MOVE_TRUCE, "target": aid, "score": 1.2})
						break
		elif neighbours.size() >= 3 and state.rng.randi() % 10 == 0:
			# Quiet border diplomacy: secure one flank while fighting another.
			for nid: int in neighbours.keys():
				if not attackers.has(nid) and TrucesOps.offer_blocker(sim, p.id, nid) == "":
					moves.append({"kind": Bots.MOVE_TRUCE, "target": nid, "score": 0.5})
					break
	if hard and p.crown_alert_until > now and not p.crown_moved:
		var spot: Vector2i = _safe_crown_spot(sim, p)
		if spot.x >= 0:
			sim.player_move_crown(p.id, spot.x, spot.y)


static func _add_spy_moves(sim: Simulation, p: Player, ctx: Dictionary, moves: Array[Dictionary]) -> void:
	var state: GameState = sim.state
	var now: float = ctx["now"]
	for nid: int in (ctx["neighbours"] as Dictionary).keys():
		var target: Player = state.get_player(nid)
		if target == null:
			continue
		var view: Dictionary = IntelOps.troop_view(p, target, now)
		# Scout anyone we only know by their band, more so if they're busy.
		if view["kind"] == IntelOps.VIEW_BAND and IntelOps.action_blocker(sim, p, nid, Balance.SPY_SCOUT) == "":
			var s: float = 0.55 if (ctx["busy"] as Dictionary).has(nid) else 0.35
			moves.append({"kind": Bots.MOVE_SPY, "target": nid, "action": Balance.SPY_SCOUT, "score": s})
		# Sabotage the Forts in front of our attacks.
		if p.plan_target_id == nid and sim.active_attack_count(p.id) > 0 \
				and IntelOps.action_blocker(sim, p, nid, Balance.SPY_SABOTAGE) == "":
			moves.append({"kind": Bots.MOVE_SPY, "target": nid, "action": Balance.SPY_SABOTAGE, "score": 0.6})
		if p.difficulty != Balance.BOT_DIFFICULTY_HARD:
			continue
		# Before a big push on a rival who looks as strong as us, get exact numbers.
		var near_crown: bool = target.crown_x >= 0 and Bots._near_crown(state, target, (ctx["neighbours"] as Dictionary)[nid], 8)
		var band: int = IntelOps.strength_band(p, target, now)
		if (near_crown or band >= IntelOps.BAND_EVEN) and ctx["can_spend"] \
				and IntelOps.action_blocker(sim, p, nid, Balance.SPY_SPY) == "":
			moves.append({"kind": Bots.MOVE_SPY, "target": nid, "action": Balance.SPY_SPY, "score": 0.7 if near_crown else 0.4})
		# A stronger neighbour: find out whether we're their next target.
		if band == IntelOps.BAND_STRONGER and IntelOps.action_blocker(sim, p, nid, Balance.SPY_PLANS) == "":
			moves.append({"kind": Bots.MOVE_SPY, "target": nid, "action": Balance.SPY_PLANS, "score": 0.45})


# A spot deep inside our land, far from every enemy, for a Crown move.
static func _safe_crown_spot(sim: Simulation, p: Player) -> Vector2i:
	var state: GameState = sim.state
	var best := Vector2i(-1, -1)
	var best_d: float = -1.0
	for _attempt in range(25):
		var x: int = p.crown_x + state.rng.randi_range(-25, 25)
		var y: int = p.crown_y + state.rng.randi_range(-25, 25)
		if not state.in_bounds(x, y) or state.owners[state.idx(x, y)] != p.id:
			continue
		if MatchOps.crown_move_blocker(sim, p, x, y) != "":
			continue
		var d: float = Vector2(x - p.crown_x, y - p.crown_y).length()
		if d > best_d:
			best_d = d
			best = Vector2i(x, y)
	return best
