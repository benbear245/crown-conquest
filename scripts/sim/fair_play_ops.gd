class_name FairPlayOps
extends RefCounted

# Troop growth plus the comeback rules: Underdog, Empire upkeep and Rising
# Empire. The alive-average land and the Rising Empire are refreshed once a
# second (they change slowly) and cached on GameState.


static func apply_growth(state: GameState) -> void:
	for p: Player in state.players:
		if not p.is_alive:
			continue
		var cap: float = p.troop_cap()
		if p.troops > cap:
			var extra: float = p.troops - cap
			p.troops = cap + extra * (1.0 - Balance.OVER_CAP_SHRINK_PER_SEC * Balance.TICK_DELTA)
		else:
			var base_tps: float = p.troops_per_second_at(cap)
			p.troops += base_tps * growth_multiplier(state, p) * Balance.TICK_DELTA
			if p.troops > cap:
				p.troops = cap


# Gems, Underdog and Empire upkeep add together (e.g. +10% gems and +25%
# Underdog make growth x1.35).
static func growth_multiplier(state: GameState, p: Player) -> float:
	var mult: float = 1.0 + gem_bonus(p)
	if is_underdog(state, p):
		mult += Balance.UNDERDOG_GROWTH_BONUS
	mult += empire_upkeep(state, p)
	return maxf(mult, 0.1)


static func gem_bonus(p: Player) -> float:
	return minf(float(p.gem_tiles) * Balance.GEM_GROWTH_BONUS_PER_TILE, Balance.GEM_GROWTH_BONUS_MAX)


# Empire upkeep growth penalty for owning too much (0 if none applies).
static func empire_upkeep(state: GameState, p: Player) -> float:
	var frac: float = state.land_fraction(p)
	if frac > Balance.EMPIRE_UPKEEP_LAND_THRESHOLD_2:
		return Balance.EMPIRE_UPKEEP_PENALTY_2
	if frac > Balance.EMPIRE_UPKEEP_LAND_THRESHOLD_1:
		return Balance.EMPIRE_UPKEEP_PENALTY_1
	return 0.0


# Underdog: your land is under 50% of the average land of players still alive.
static func is_underdog(state: GameState, p: Player) -> bool:
	if state.avg_alive_land <= 0.0 or not p.is_alive:
		return false
	return float(p.land) < Balance.UNDERDOG_LAND_FRACTION_OF_AVG * state.avg_alive_land


static func recompute_once_per_second(state: GameState) -> void:
	if state.tick_count < state.fair_play_next_tick:
		return
	state.fair_play_next_tick = state.tick_count + Balance.TICKS_PER_SECOND
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
	state.avg_alive_land = float(alive_land) / float(maxi(alive_count, 1))
	# Rising Empire: one player owns over 30% of the map.
	state.rising_empire_id = -1
	if biggest != null and state.land_fraction(biggest) > Balance.RISING_EMPIRE_LAND_THRESHOLD:
		state.rising_empire_id = biggest.id
