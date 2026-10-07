class_name Simulation
extends RefCounted

# Drives the match at 10 ticks per second and is the one entry point for
# player commands (the local player and bots call the same methods).
# Never touches nodes. The rules themselves live in the *_ops.gd scripts.

var state: GameState = GameState.new()
var map_type: int = Balance.MAP_TYPE_CONTINENT
var size_preset: int = Balance.MAP_SIZE_MEDIUM
var local_player_id: int = 1
# Headless mode: skip presentation events (banners, sounds) so the balance
# sim can run many matches without paying for things nobody will see.
var headless: bool = false
# Capture flashes are drawing-only; an online server leaves them to clients.
var flashes: bool = true
var _final_siege_announced: bool = false
# Cached average land of alive players for Underdog checks, and the Rising
# Empire (-1 if nobody owns > 30% of the map). Refreshed once a second.
var _avg_land_cache: float = 0.0
var _rising_empire_id: int = -1


# --- Match setup -------------------------------------------------------------

func start_default_match(match_seed: int = 0) -> void:
	start_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, match_seed, 7)


func start_match(size: int, mt: int, match_seed: int, num_bots: int = -1) -> void:
	size_preset = size
	map_type = mt
	_final_siege_announced = false
	_avg_land_cache = 0.0
	_rising_empire_id = -1
	var dims := MapGen.dims_for_size(size)
	state.configure(dims.x, dims.y, match_seed)
	MapGen.generate(state, mt)
	if num_bots < 0:
		num_bots = MapGen.players_for_size(size) - 1
	_setup_players(num_bots)


func _setup_players(num_bots: int) -> void:
	var total: int = clampi(num_bots + 1, 1, Balance.PLAYER_COLORS.size() - 1)
	for i in range(total):
		var p := Player.new()
		p.id = i + 1
		if i == 0:
			p.display_name = "You"
			p.is_bot = false
		else:
			p.display_name = Balance.generate_name(state.rng)
			p.is_bot = true
			p.difficulty = _mixed_difficulty(i)
			p.personality = state.rng.randi() % 4
			p.think_timer = state.rng.randf_range(0.5, 2.0)
		state.players.append(p)


# Default skirmish is Mixed: for 7 bots that's 3 Easy, 3 Normal, 1 Hard.
func _mixed_difficulty(bot_number: int) -> int:
	if bot_number % 7 == 0:
		return Balance.BOT_DIFFICULTY_HARD
	return Balance.BOT_DIFFICULTY_EASY if bot_number % 7 <= 3 else Balance.BOT_DIFFICULTY_NORMAL


# --- Tick loop ---------------------------------------------------------------

func advance_tick() -> void:
	match state.phase:
		Balance.PHASE_PLACEMENT:
			MatchOps.tick_placement(self)
		Balance.PHASE_MATCH:
			state.match_time += Balance.TICK_DELTA
			_announce_final_siege_once()
			if state.tick_count % Balance.TICKS_PER_SECOND == 0:
				_recompute_fair_play()
				_repaint_reenabled_buildings()
			_apply_growth()
			TerritoryOps.apply_expansions(self)
			AbilitiesOps.tick(self)
			TrucesOps.tick(self)
			IntelOps.tick(self)
			MatchOps.tick_crown_moves(self)
			CombatOps.tick_attacks(self)
			if not state.boats.is_empty():
				BoatsOps.tick(self)
			CombatOps.check_crown_alerts(self)
			if not headless:
				_tick_flashes()
			for p in state.players:
				if p.is_alive and p.is_bot:
					Bots.tick(self, p)
			MatchOps.check_win_conditions(self)
	state.tick_count += 1


func _announce_final_siege_once() -> void:
	if _final_siege_announced or not state.is_final_siege():
		return
	_final_siege_announced = true
	emit({"type": "final_siege"})
	announce("Final Siege begins — Crowns weaken, plunder doubles.")


func _tick_flashes() -> void:
	if state.flash_tiles.is_empty():
		return
	for i: int in state.flash_tiles.keys():
		if state.match_time >= state.flash_tiles[i]:
			state.flash_tiles.erase(i)
			state.dirty_tiles[i] = true


# Sabotaged buildings are drawn grey; repaint them once they work again.
func _repaint_reenabled_buildings() -> void:
	if headless:
		return
	for b: Building in state.buildings:
		if b.disabled_until > 0.0 and b.disabled_until <= state.match_time:
			b.disabled_until = 0.0
			state.dirty_tiles[b.tile_idx] = true


# --- Events for the presentation layer ---------------------------------------

func emit(event: Dictionary) -> void:
	if not headless:
		state.push_event(event)


# A banner message. `to` limits who sees it (empty = everyone).
func announce(text: String, to: Array = []) -> void:
	emit({"type": "announce", "text": text, "to": to})


func mark_flash(tile_idx: int) -> void:
	if headless or not flashes:
		return
	state.flash_tiles[tile_idx] = state.match_time + 0.3
	state.dirty_tiles[tile_idx] = true


# --- Growth and fair play ----------------------------------------------------

func _apply_growth() -> void:
	for p in state.players:
		if not p.is_alive:
			continue
		var cap := p.troop_cap()
		if p.troops > cap:
			var extra := p.troops - cap
			p.troops = cap + extra * (1.0 - Balance.OVER_CAP_SHRINK_PER_SEC * Balance.TICK_DELTA)
		else:
			p.troops = minf(cap, p.troops + p.troops_per_second_at(cap) * growth_multiplier(p) * Balance.TICK_DELTA)


# Growth bonuses and penalties add together (gems, Underdog, Shrine of
# Plenty, Empire upkeep).
func growth_multiplier(p: Player) -> float:
	var mult: float = 1.0
	mult += minf(float(p.gem_tiles) * Balance.GEM_GROWTH_BONUS_PER_TILE, Balance.GEM_GROWTH_BONUS_MAX)
	if is_underdog(p):
		mult += Balance.UNDERDOG_GROWTH_BONUS
	mult += ShrinesOps.growth_bonus(state, p.id)
	var frac: float = state.land_fraction(p)
	if frac >= Balance.EMPIRE_UPKEEP_LAND_THRESHOLD_2:
		mult += Balance.EMPIRE_UPKEEP_PENALTY_2
	elif frac >= Balance.EMPIRE_UPKEEP_LAND_THRESHOLD_1:
		mult += Balance.EMPIRE_UPKEEP_PENALTY_1
	return maxf(mult, 0.1)


func _recompute_fair_play() -> void:
	var alive_land: int = 0
	var alive_count: int = 0
	var biggest: Player = null
	for p: Player in state.players:
		if not p.is_alive:
			continue
		alive_land += p.land
		alive_count += 1
		if biggest == null or p.land > biggest.land:
			biggest = p
	_avg_land_cache = float(alive_land) / float(maxi(alive_count, 1))
	var prev: int = _rising_empire_id
	_rising_empire_id = -1
	if biggest != null and state.land_fraction(biggest) > Balance.RISING_EMPIRE_LAND_THRESHOLD:
		_rising_empire_id = biggest.id
	if _rising_empire_id > 0 and _rising_empire_id != prev:
		announce("%s is a Rising Empire — attacks on them cost less!" % biggest.display_name)


func rising_empire_id() -> int:
	return _rising_empire_id


func average_land() -> float:
	return _avg_land_cache


# Online clients don't run the rules; the server tells them these values.
func set_fair_play_view(rising_id: int, avg_land: float) -> void:
	_rising_empire_id = rising_id
	_avg_land_cache = avg_land


func is_underdog(p: Player) -> bool:
	if _avg_land_cache <= 0.0:
		return false
	return float(p.land) < Balance.UNDERDOG_LAND_FRACTION_OF_AVG * _avg_land_cache


# --- Queries used by HUD and bots --------------------------------------------

func active_attack_count(player_id: int) -> int:
	var n := 0
	for a: Attack in state.attacks:
		if a.attacker_id == player_id:
			n += 1
	return n


func attacks_by(player_id: int) -> Array:
	var out: Array = []
	for a: Attack in state.attacks:
		if a.attacker_id == player_id:
			out.append(a)
	return out


# The player issuing a command, if they may act at all right now.
func _actor(player_id: int) -> Player:
	if state.phase != Balance.PHASE_MATCH:
		return null
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return null
	return p


# Counts a successful command in state.usage and passes the result through.
func _used(what: String, ok: bool) -> bool:
	if ok:
		state.usage[what] = int(state.usage.get(what, 0)) + 1
	return ok


# --- Player commands ---------------------------------------------------------

func player_place_crown(player_id: int, x: int, y: int) -> bool:
	if state.phase != Balance.PHASE_PLACEMENT:
		return false
	var p := state.get_player(player_id)
	if p == null or p.crown_x >= 0 or not state.in_bounds(x, y):
		return false
	if not MatchOps.is_valid_crown_tile(state, x, y, Balance.CROWN_MIN_DIST_FROM_OTHER):
		return false
	MatchOps.place_crown(self, p, x, y)
	return true


func player_expand(player_id: int, tx: int, ty: int, fraction: float) -> bool:
	var p := _actor(player_id)
	if p == null or not state.in_bounds(tx, ty):
		return false
	var ti: int = state.idx(tx, ty)
	if state.is_player_owner(state.owners[ti]) or state.is_blocked_terrain(state.terrain[ti]):
		return false
	if not TerritoryOps.tile_touches_player(state, tx, ty, player_id):
		return false
	var send_amount := floorf(p.troops * clampf(fraction, Balance.SEND_MIN_FRACTION, Balance.SEND_MAX_FRACTION))
	if send_amount <= 0.0:
		return false
	p.troops -= send_amount
	p.expansion_troops += send_amount
	if p.expansion_timer <= 0.0:
		p.expansion_timer = Balance.EXPANSION_RING_INTERVAL_SEC
	return true


# Target tile must be owned by another live player and touch the attacker's border.
func player_attack(player_id: int, tx: int, ty: int, fraction: float) -> bool:
	var p := _actor(player_id)
	if p == null or not state.in_bounds(tx, ty):
		return false
	var target_owner: int = state.owners[state.idx(tx, ty)]
	if not CombatOps.can_attack(self, p, target_owner):
		return false
	var front: Dictionary = CombatOps.build_attack_front(state, p, target_owner)
	var send: float = floorf(p.troops * clampf(fraction, Balance.SEND_MIN_FRACTION, Balance.SEND_MAX_FRACTION))
	if front.is_empty() or send <= 0.0:
		return false
	p.troops -= send
	CombatOps.open_attack(self, p, target_owner, send, front)
	return true


func player_retreat(player_id: int, local_index: int) -> bool:
	return CombatOps.retreat(self, player_id, local_index)


func player_build(player_id: int, type: int, x: int, y: int) -> bool:
	var p := _actor(player_id)
	return _used(Building.type_label(type), p != null and BuildingsOps.build(self, p, type, x, y))


func player_upgrade_fort(player_id: int, x: int, y: int) -> bool:
	var p := _actor(player_id)
	return _used("Fort II", p != null and BuildingsOps.upgrade_fort(self, p, x, y))


func player_build_wall(player_id: int, x: int, y: int) -> bool:
	var p := _actor(player_id)
	return _used("Wall", p != null and BuildingsOps.build_wall(self, p, x, y))


func player_buy_keep(player_id: int, level: int) -> bool:
	var p := _actor(player_id)
	return _used("Keep %d" % level, p != null and BuildingsOps.buy_keep(self, p, level))


func player_move_crown(player_id: int, x: int, y: int) -> bool:
	var p := _actor(player_id)
	return _used("Crown move", p != null and MatchOps.start_crown_move(self, p, x, y))


func player_launch_boat(player_id: int, port_x: int, port_y: int,
		target_x: int, target_y: int, fraction: float) -> bool:
	var p := _actor(player_id)
	return _used("Boat", p != null and BoatsOps.try_launch(self, p, port_x, port_y, target_x, target_y, fraction))


func player_activate_ability(player_id: int, ability_id: int, target_x: int = -1, target_y: int = -1) -> bool:
	var p := _actor(player_id)
	var label: String = ["Swift March", "Crown Shield", "Rally", "Bombard"][clampi(ability_id, 0, 3)]
	return _used(label, p != null and AbilitiesOps.activate(self, p, ability_id, target_x, target_y))


func player_offer_truce(player_id: int, target_id: int) -> bool:
	return _used("Truce offer", _actor(player_id) != null and TrucesOps.offer(self, player_id, target_id))


func player_answer_truce(player_id: int, from_id: int, accepted: bool) -> bool:
	return _actor(player_id) != null and TrucesOps.answer(self, player_id, from_id, accepted)


func player_spy(player_id: int, target_id: int, action: int) -> bool:
	var p := _actor(player_id)
	return _used(IntelOps.action_label(action), p != null and IntelOps.perform(self, p, target_id, action))


func player_disinformation(player_id: int, look_strong: bool) -> bool:
	var p := _actor(player_id)
	return _used("Disinformation", p != null and IntelOps.start_disinformation(self, p, look_strong))
