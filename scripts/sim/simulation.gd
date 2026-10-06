class_name Simulation
extends RefCounted

# Drives the match: 10 ticks per second. Never touches nodes. The rules live
# in the *_ops.gd helpers; this file owns the tick order, growth, fair-play
# bookkeeping, win conditions, and the player command entry points that both
# the local player and the bots call.

const NEIGHBOR_OFFSETS: Array[Vector2i] = TerritoryOps.NEIGHBOR_OFFSETS
const POPUP_SEC: float = 1.6

var state: GameState = GameState.new()
var map_type: int = Balance.MAP_TYPE_CONTINENT
var size_preset: int = Balance.MAP_SIZE_MEDIUM
var local_player_id: int = 1
# How this match was set up (mode, map, bots). Null for plain start_match().
var config: MatchConfig = null
# Headless mode: skip presentation-only bookkeeping (capture flashes, floating
# numbers) so the balance sim doesn't pay for state nobody will draw.
var headless: bool = false
var _final_siege_announced: bool = false


# --- Match setup -------------------------------------------------------------

func start_default_match(match_seed: int = 0) -> void:
	start_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, match_seed, 7)


# Starts a match from the menus: map, bots, difficulty, and Teams / Daily /
# Tutorial rules.
func start_with(cfg: MatchConfig, match_seed: int) -> void:
	start_match(cfg.size_preset, cfg.map_type, match_seed, cfg.num_bots)
	config = cfg
	var bots: Array[Player] = []
	for p: Player in state.players:
		if p.is_bot:
			bots.append(p)
	var diffs: Array[int] = MatchConfig.difficulty_list(cfg.difficulty, bots.size(), state.rng)
	for i in range(bots.size()):
		bots[i].difficulty = diffs[i]
	if cfg.mode == MatchConfig.Mode.TEAMS:
		_setup_teams(cfg)
	elif cfg.mode == MatchConfig.Mode.TUTORIAL:
		state.tutorial_rules = true


func start_match(size: int, mt: int, match_seed: int, num_bots: int = -1) -> void:
	config = null
	size_preset = size
	map_type = mt
	_final_siege_announced = false
	var dims := MapGen.dims_for_size(size)
	state.configure(dims.x, dims.y, match_seed)
	state.track_dirty = not headless
	MapGen.generate(state, mt)
	state.finalize_terrain()
	if num_bots < 0:
		num_bots = MapGen.players_for_size(size) - 1
	_setup_players(num_bots)


func _setup_players(num_bots: int) -> void:
	var total: int = clampi(num_bots + 1, 1, Balance.PLAYER_COLORS.size() - 1)
	for i in range(total):
		var p := Player.new()
		p.id = i + 1
		p.color = Balance.color_for_player(p.id)
		if i == 0:
			p.display_name = "You"
			p.is_bot = false
		else:
			p.display_name = _generate_name(state.rng)
			p.is_bot = true
			p.difficulty = Balance.BOT_DIFFICULTY_EASY
			p.personality = state.rng.randi() % 4
			p.think_timer = state.rng.randf_range(0.5, 2.0)
		state.players.append(p)


# Pairs players up: (1, 2), (3, 4), ... You and your ally are team 0. Your
# ally plays at the chosen difficulty (Normal when Mixed).
func _setup_teams(cfg: MatchConfig) -> void:
	state.teams_mode = true
	for i in range(state.players.size()):
		var p: Player = state.players[i]
		@warning_ignore("integer_division")
		p.team = i / Balance.TEAM_SIZE
		var mate_index: int = i + 1 if i % 2 == 0 else i - 1
		if mate_index < state.players.size():
			p.ally_id = state.players[mate_index].id
	if state.players.size() > 1:
		var ally: Player = state.players[1]
		ally.difficulty = Balance.BOT_DIFFICULTY_NORMAL if cfg.difficulty == MatchConfig.DIFFICULTY_MIXED else cfg.difficulty


func team_name(team: int) -> String:
	if team < 0 or team >= Balance.TEAM_NAMES.size():
		return "Team %d" % (team + 1)
	return Balance.TEAM_NAMES[team]


func ally_of(p: Player) -> Player:
	if p == null or p.ally_id <= 0:
		return null
	return state.get_player(p.ally_id)


# True if the local player won (alone, or with their team in Teams).
func local_won() -> bool:
	if state.phase != Balance.PHASE_ENDED:
		return false
	if state.winner_id == local_player_id:
		return true
	var me: Player = state.get_player(local_player_id)
	return state.teams_mode and me != null and me.team >= 0 and me.team == state.winner_team


func team_land(team: int) -> int:
	var n: int = 0
	for p: Player in state.players:
		if p.team == team and p.is_alive:
			n += p.land
	return n


# Daily Challenge score: peak land % + a bonus for winning fast.
func daily_score() -> int:
	var me: Player = state.get_player(local_player_id)
	if me == null:
		return 0
	var peak_pct: float = 100.0 * float(me.peak_land) / float(maxi(state.total_usable_tiles(), 1))
	return roundi(peak_pct) + daily_time_bonus()


func daily_time_bonus() -> int:
	if not local_won():
		return 0
	var left: float = maxf(0.0, Balance.MATCH_TIME_LIMIT_SEC - state.match_time)
	return roundi(Balance.DAILY_TIME_BONUS_MAX * left / Balance.MATCH_TIME_LIMIT_SEC)


# Fantasy bot names: a title and a name, e.g. "Duke Ashford".
static func _generate_name(rng: RandomNumberGenerator) -> String:
	var title: String = Balance.BOT_TITLES[rng.randi() % Balance.BOT_TITLES.size()]
	var given: String = Balance.BOT_NAMES[rng.randi() % Balance.BOT_NAMES.size()]
	return "%s %s" % [title, given]


# --- Tick loop ---------------------------------------------------------------

func advance_tick() -> void:
	match state.phase:
		Balance.PHASE_PLACEMENT:
			_tick_placement()
		Balance.PHASE_MATCH:
			state.match_time += Balance.TICK_DELTA
			_announce_final_siege_once()
			FairPlayOps.recompute_once_per_second(state)
			FairPlayOps.apply_growth(state)
			TerritoryOps.apply_expansions(self)
			AbilitiesOps.tick(self)
			TrucesOps.tick(self)
			CombatOps.tick_attacks(self)
			_tick_boats()
			CombatOps.check_crown_alerts(state)
			if not headless:
				_tick_flashes()
				_tick_popups()
			_tick_bots()
			_check_win_conditions()
	state.tick_count += 1


func _announce_final_siege_once() -> void:
	if _final_siege_announced:
		return
	if not state.is_final_siege():
		return
	_final_siege_announced = true
	for p: Player in state.players:
		p.keep_disabled = true
	announce("Final Siege begins — Crowns weaken, plunder doubles.", 5.0)
	state.events.append({"type": "final_siege"})


func _tick_placement() -> void:
	if not state.tutorial_rules:
		state.placement_time_left -= Balance.TICK_DELTA
	# Bots place as soon as they get a chance (first tick that reaches them).
	# In Teams, a bot places next to its ally (a human's ally waits for them).
	for p: Player in state.players:
		if p.is_bot and p.crown_x < 0:
			var ally: Player = ally_of(p)
			if ally != null and not ally.is_bot and ally.crown_x < 0:
				continue
			var pos: Vector2i = _crown_spot_for(p)
			if pos.x >= 0:
				CrownsOps.place_crown(self, p, pos.x, pos.y)
	if state.placement_time_left <= 0.0:
		for p: Player in state.players:
			if p.crown_x < 0:
				var pos: Vector2i = _crown_spot_for(p)
				CrownsOps.place_crown(self, p, pos.x, pos.y)
	var all_placed: bool = true
	for p: Player in state.players:
		all_placed = all_placed and p.crown_x >= 0
	if state.placement_time_left <= 0.0 or (state.tutorial_rules and all_placed):
		state.phase = Balance.PHASE_MATCH


func _crown_spot_for(p: Player) -> Vector2i:
	var ally: Player = ally_of(p)
	if ally != null and ally.crown_x >= 0:
		var near: Vector2i = CrownsOps.find_valid_crown_position_near(state, ally.crown_x, ally.crown_y)
		if near.x >= 0:
			return near
	return CrownsOps.find_valid_crown_position(state)


func _tick_bots() -> void:
	for p: Player in state.players:
		if p.is_alive and p.is_bot:
			Bots.tick(self, p)


# --- Fair play queries (rules live in FairPlayOps) ---------------------------

func growth_multiplier(p: Player) -> float:
	return FairPlayOps.growth_multiplier(state, p)


func empire_upkeep(p: Player) -> float:
	return FairPlayOps.empire_upkeep(state, p)


func rising_empire_id() -> int:
	return state.rising_empire_id


func is_underdog(p: Player) -> bool:
	return FairPlayOps.is_underdog(state, p)


# --- Win conditions ----------------------------------------------------------

func _check_win_conditions() -> void:
	if state.teams_mode:
		_check_team_win_conditions()
		return
	var alive: Array[Player] = []
	for p: Player in state.players:
		if p.is_alive:
			alive.append(p)
	if alive.size() <= 1:
		if alive.size() == 1:
			end_match(alive[0].id, "Last Crown standing")
		else:
			end_match(0, "Draw")
		return
	for p: Player in alive:
		if state.land_fraction(p) >= Balance.DOMINION_WIN_FRACTION and not state.tutorial_rules:
			end_match(p.id, "Dominion win (60%+ of the usable map)")
			return
	if state.match_time >= Balance.MATCH_TIME_LIMIT_SEC and not state.tutorial_rules:
		var leader: Player = alive[0]
		for p: Player in alive:
			if p.land > leader.land:
				leader = p
		end_match(leader.id, "Most land at the 15:00 limit")


# Teams: the last team with a Crown wins; Team Dominion (80%) and the time
# limit count the team's combined land.
func _check_team_win_conditions() -> void:
	var alive_teams: Dictionary = {}       # team -> best (most land) alive player
	for p: Player in state.players:
		if p.is_alive:
			var best: Player = alive_teams.get(p.team, null)
			if best == null or p.land > best.land:
				alive_teams[p.team] = p
	if alive_teams.size() <= 1:
		if alive_teams.is_empty():
			end_match(0, "Draw")
		else:
			var team: int = alive_teams.keys()[0]
			_end_team_match(team, alive_teams[team], "Last team with a Crown")
		return
	var usable: float = float(maxi(state.total_usable_tiles(), 1))
	for team: int in alive_teams.keys():
		if float(team_land(team)) / usable >= Balance.TEAM_DOMINION_WIN_FRACTION:
			_end_team_match(team, alive_teams[team], "Team Dominion (%d%%+ of the usable map)" % roundi(Balance.TEAM_DOMINION_WIN_FRACTION * 100.0))
			return
	if state.match_time >= Balance.MATCH_TIME_LIMIT_SEC and not state.tutorial_rules:
		var lead_team: int = -1
		for team: int in alive_teams.keys():
			if lead_team < 0 or team_land(team) > team_land(lead_team):
				lead_team = team
		_end_team_match(lead_team, alive_teams[lead_team], "Most land at the 15:00 limit")


func _end_team_match(team: int, best: Player, reason: String) -> void:
	state.winner_team = team
	end_match(best.id, reason)


func end_match(winner_id: int, reason: String) -> void:
	state.phase = Balance.PHASE_ENDED
	state.winner_id = winner_id
	state.win_reason = reason
	state.attacks.clear()
	if state.teams_mode and state.winner_team >= 0:
		announce("Team %s wins! %s" % [team_name(state.winner_team), reason], 6.0)
	elif winner_id > 0:
		var w: Player = state.get_player(winner_id)
		if w != null:
			announce("%s wins! %s" % [w.display_name, reason], 6.0)
	else:
		announce("Match ends: %s" % reason, 6.0)
	state.events.append({"type": "match_end", "winner_id": winner_id})


# --- Presentation helpers (pure data the HUD reads) --------------------------

func announce(text: String, seconds: float = 4.0) -> void:
	state.active_announcement_text = text
	state.active_announcement_until = state.match_time + seconds
	state.events.append({"type": "announce", "text": text, "seconds": seconds})


# Presentation-only events (sounds, shake, vibration). Skipped in headless
# runs so the balance simulator doesn't pay for them.
func emit_event(e: Dictionary) -> void:
	if not headless:
		state.events.append(e)


func mark_flash(tile_idx: int) -> void:
	if headless:
		return
	state.flash_tiles[tile_idx] = state.match_time + 0.3
	state.dirty_tiles[tile_idx] = true


func add_popup(tile_idx: int, text: String, owner_id: int) -> void:
	if headless:
		return
	state.popups.append({"tile_idx": tile_idx, "text": text, "owner_id": owner_id, "until": state.match_time + POPUP_SEC})


func _tick_flashes() -> void:
	if state.flash_tiles.is_empty():
		return
	var expired: Array[int] = []
	for i: int in state.flash_tiles.keys():
		if state.match_time >= state.flash_tiles[i]:
			expired.append(i)
	for i: int in expired:
		state.flash_tiles.erase(i)
		state.dirty_tiles[i] = true


func _tick_popups() -> void:
	var i: int = 0
	while i < state.popups.size():
		if state.match_time >= float(state.popups[i]["until"]):
			state.popups.remove_at(i)
			continue
		i += 1


func _tick_boats() -> void:
	if state.boats.is_empty():
		return
	BoatsOps.tick(self)


# --- Queries used by the HUD and bots ----------------------------------------

func combined_defense_at(tile_idx: int) -> float:
	return CombatOps.combined_defense_at(state, tile_idx)


func active_attack_count(player_id: int) -> int:
	return CombatOps.active_attack_count(state, player_id)


func attacks_by(player_id: int) -> Array[Attack]:
	var out: Array[Attack] = []
	for a: Attack in state.attacks:
		if a.attacker_id == player_id:
			out.append(a)
	return out


func _live_player(player_id: int) -> Player:
	if state.phase != Balance.PHASE_MATCH:
		return null
	var p: Player = state.get_player(player_id)
	if p == null or not p.is_alive:
		return null
	return p


# --- Player commands (the local player and bots both call these) -------------

func player_place_crown(player_id: int, x: int, y: int) -> bool:
	if state.phase != Balance.PHASE_PLACEMENT:
		return false
	var p: Player = state.get_player(player_id)
	if p == null or p.crown_x >= 0:
		return false
	if not state.in_bounds(x, y) or not CrownsOps.is_valid_crown_tile(state, x, y, Balance.CROWN_MIN_DIST_FROM_OTHER):
		return false
	CrownsOps.place_crown(self, p, x, y)
	return true


func player_expand(player_id: int, tx: int, ty: int, fraction: float) -> bool:
	if _live_player(player_id) == null:
		return false
	return TerritoryOps.player_expand(self, player_id, tx, ty, fraction)


func player_attack(player_id: int, tx: int, ty: int, fraction: float) -> bool:
	if _live_player(player_id) == null:
		return false
	return CombatOps.player_attack(self, player_id, tx, ty, fraction)


func player_retreat(player_id: int, local_index: int) -> bool:
	return CombatOps.player_retreat(self, player_id, local_index)


func player_build_fort(player_id: int, x: int, y: int) -> bool:
	var p: Player = _live_player(player_id)
	return p != null and BuildingsOps.build_fort(self, p, x, y)


func player_upgrade_fort(player_id: int, x: int, y: int) -> bool:
	var p: Player = _live_player(player_id)
	return p != null and BuildingsOps.upgrade_fort(self, p, x, y)


func player_build_barracks(player_id: int, x: int, y: int) -> bool:
	var p: Player = _live_player(player_id)
	return p != null and BuildingsOps.build_barracks(self, p, x, y)


func player_build_port(player_id: int, x: int, y: int) -> bool:
	var p: Player = _live_player(player_id)
	return p != null and BuildingsOps.build_port(self, p, x, y)


func player_build_wall(player_id: int, x: int, y: int) -> bool:
	var p: Player = _live_player(player_id)
	return p != null and BuildingsOps.build_wall(self, p, x, y)


func player_buy_keep(player_id: int, level: int) -> bool:
	var p: Player = _live_player(player_id)
	return p != null and BuildingsOps.buy_keep(self, p, level)


func player_move_crown(player_id: int, x: int, y: int) -> bool:
	var p: Player = _live_player(player_id)
	return p != null and CrownsOps.move_crown(self, p, x, y)


func player_launch_boat(player_id: int, port_x: int, port_y: int,
		target_x: int, target_y: int, fraction: float) -> bool:
	var p: Player = _live_player(player_id)
	return p != null and BoatsOps.try_launch(self, p, port_x, port_y, target_x, target_y, fraction)


func player_activate_swift_march(player_id: int) -> bool:
	var p: Player = _live_player(player_id)
	return p != null and AbilitiesOps.activate_swift_march(self, p)


func player_activate_crown_shield(player_id: int) -> bool:
	var p: Player = _live_player(player_id)
	return p != null and AbilitiesOps.activate_crown_shield(self, p)


func player_activate_rally(player_id: int) -> bool:
	var p: Player = _live_player(player_id)
	return p != null and AbilitiesOps.activate_rally(self, p)


func player_activate_bombard(player_id: int, target_x: int, target_y: int) -> bool:
	var p: Player = _live_player(player_id)
	return p != null and AbilitiesOps.activate_bombard(self, p, target_x, target_y)


# Teams: give your ally 20% of your troops (short cooldown).
func send_to_ally_block_reason(p: Player) -> String:
	if p == null or not p.is_alive or p.ally_id <= 0:
		return "No ally"
	var ally: Player = state.get_player(p.ally_id)
	if ally == null or not ally.is_alive:
		return "Your ally has fallen"
	if state.phase != Balance.PHASE_MATCH:
		return "Not yet"
	if p.ally_send_cd_until > state.match_time:
		return "Ready in %ds" % ceili(p.ally_send_cd_until - state.match_time)
	if floorf(p.troops * Balance.ALLY_SEND_FRACTION) < 1.0:
		return "No troops to send"
	return ""


func player_send_to_ally(player_id: int) -> bool:
	var p: Player = state.get_player(player_id)
	if send_to_ally_block_reason(p) != "":
		return false
	var ally: Player = state.get_player(p.ally_id)
	var amount: float = floorf(p.troops * Balance.ALLY_SEND_FRACTION)
	p.troops -= amount
	ally.troops += amount
	p.troops_sent_to_ally += amount
	p.ally_send_cd_until = state.match_time + Balance.ALLY_SEND_COOLDOWN_SEC
	if ally.crown_x >= 0:
		add_popup(state.idx(ally.crown_x, ally.crown_y), "+%s from %s" % [GameState.format_int(int(amount)), p.display_name], ally.id)
	emit_event({"type": "ally_send", "from_id": p.id, "to_id": ally.id, "amount": amount})
	return true


func player_offer_truce(player_id: int, target_id: int) -> bool:
	if _live_player(player_id) == null:
		return false
	return TrucesOps.offer(self, player_id, target_id)


func player_respond_truce(player_id: int, from_id: int, accepted: bool) -> bool:
	if _live_player(player_id) == null:
		return false
	return TrucesOps.respond(self, from_id, player_id, accepted)
