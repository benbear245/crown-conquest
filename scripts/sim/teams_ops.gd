class_name TeamsOps
extends RefCounted

# Teams mode (4 teams of 2: allies never fight, "Send 20% to ally", the team
# wins together) and the Daily Challenge score. Simulation keeps thin
# wrappers so the HUD and bots call sim.team_land(), sim.ally_of() etc.


# Pairs players up: (1, 2), (3, 4), ... You and your ally are team 0. Your
# ally plays at the chosen difficulty (Normal when Mixed).
static func setup(state: GameState, cfg: MatchConfig) -> void:
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


static func team_name(team: int) -> String:
	if team < 0 or team >= Balance.TEAM_NAMES.size():
		return "Team %d" % (team + 1)
	return Balance.TEAM_NAMES[team]


static func team_land(state: GameState, team: int) -> int:
	var n: int = 0
	for p: Player in state.players:
		if p.team == team and p.is_alive:
			n += p.land
	return n


# The last team with a Crown wins; Team Dominion (80%) and the time limit
# count the team's combined land.
static func check_win(sim: Simulation) -> void:
	var state: GameState = sim.state
	var alive_teams: Dictionary = {}       # team -> best (most land) alive player
	for p: Player in state.players:
		if p.is_alive:
			var best: Player = alive_teams.get(p.team, null)
			if best == null or p.land > best.land:
				alive_teams[p.team] = p
	if alive_teams.size() <= 1:
		if alive_teams.is_empty():
			sim.end_match(0, "Draw")
		else:
			var team: int = alive_teams.keys()[0]
			_end(sim, team, alive_teams[team], "Last team with a Crown")
		return
	var usable: float = float(maxi(state.total_usable_tiles(), 1))
	for team: int in alive_teams.keys():
		if float(team_land(state, team)) / usable >= Balance.TEAM_DOMINION_WIN_FRACTION:
			_end(sim, team, alive_teams[team], "Team Dominion (%d%%+ of the usable map)" % roundi(Balance.TEAM_DOMINION_WIN_FRACTION * 100.0))
			return
	if state.match_time >= Balance.MATCH_TIME_LIMIT_SEC and not state.tutorial_rules:
		var lead_team: int = -1
		for team: int in alive_teams.keys():
			if lead_team < 0 or team_land(state, team) > team_land(state, lead_team):
				lead_team = team
		_end(sim, lead_team, alive_teams[lead_team], "Most land at the 15:00 limit")


static func _end(sim: Simulation, team: int, best: Player, reason: String) -> void:
	sim.state.winner_team = team
	sim.end_match(best.id, reason)


# Why `p` can't send 20% to their ally right now, or "" if they can.
static func send_block_reason(state: GameState, p: Player) -> String:
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


static func send_to_ally(sim: Simulation, player_id: int) -> bool:
	var state: GameState = sim.state
	var p: Player = state.get_player(player_id)
	if send_block_reason(state, p) != "":
		return false
	var ally: Player = state.get_player(p.ally_id)
	var amount: float = floorf(p.troops * Balance.ALLY_SEND_FRACTION)
	p.troops -= amount
	ally.troops += amount
	p.troops_sent_to_ally += amount
	p.ally_send_cd_until = state.match_time + Balance.ALLY_SEND_COOLDOWN_SEC
	if ally.crown_x >= 0:
		sim.add_popup(state.idx(ally.crown_x, ally.crown_y), "+%s from %s" % [GameState.format_int(int(amount)), p.display_name], ally.id)
	sim.emit_event({"type": "ally_send", "from_id": p.id, "to_id": ally.id, "amount": amount})
	return true


# Daily Challenge: peak land % (rounded) + a bonus for winning fast.
static func daily_score(sim: Simulation) -> int:
	var state: GameState = sim.state
	var me: Player = state.get_player(sim.local_player_id)
	if me == null:
		return 0
	var peak_pct: float = 100.0 * float(me.peak_land) / float(maxi(state.total_usable_tiles(), 1))
	return roundi(peak_pct) + daily_time_bonus(sim)


static func daily_time_bonus(sim: Simulation) -> int:
	if not sim.local_won():
		return 0
	var left: float = maxf(0.0, Balance.MATCH_TIME_LIMIT_SEC - sim.state.match_time)
	return roundi(Balance.DAILY_TIME_BONUS_MAX * left / Balance.MATCH_TIME_LIMIT_SEC)
