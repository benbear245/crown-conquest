class_name Bots
extends RefCounted

# Basic bot brain. Prompt 4: expansion only. Smarter choices land in Prompt 11.
# Bots call the exact same Simulation commands as the local player.


static func tick(sim: Simulation, player: Player) -> void:
	player.think_timer -= Balance.TICK_DELTA
	if player.think_timer > 0.0:
		return
	player.think_timer = _think_interval(player.difficulty, sim.state.rng)
	_basic_expand(sim, player)


static func _think_interval(difficulty: int, rng: RandomNumberGenerator) -> float:
	var base: float
	match difficulty:
		Balance.BOT_DIFFICULTY_HARD:
			base = Balance.BOT_HARD_THINK_SEC
		Balance.BOT_DIFFICULTY_NORMAL:
			base = Balance.BOT_NORMAL_THINK_SEC
		_:
			base = Balance.BOT_EASY_THINK_SEC
	# A little jitter so bots don't all think on the same tick.
	return base * rng.randf_range(0.85, 1.15)


static func _send_range(difficulty: int) -> Vector2:
	match difficulty:
		Balance.BOT_DIFFICULTY_HARD:
			return Vector2(Balance.BOT_HARD_SEND_MIN, Balance.BOT_HARD_SEND_MAX)
		Balance.BOT_DIFFICULTY_NORMAL:
			return Vector2(Balance.BOT_NORMAL_SEND_MIN, Balance.BOT_NORMAL_SEND_MAX)
		_:
			return Vector2(Balance.BOT_EASY_SEND_MIN, Balance.BOT_EASY_SEND_MAX)


static func _basic_expand(sim: Simulation, player: Player) -> void:
	if player.border.is_empty() or player.troops < 1.0:
		return
	var state: GameState = sim.state
	var border_keys: Array = player.border.keys()
	# Try a handful of border tiles, pick the first one that touches a tappable free tile.
	for _attempt in range(16):
		var i: int = border_keys[state.rng.randi_range(0, border_keys.size() - 1)]
		var pos := state.idx_to_xy(i)
		for off in Simulation.NEIGHBOR_OFFSETS:
			var nx: int = pos.x + off.x
			var ny: int = pos.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			var ni := state.idx(nx, ny)
			var ow: int = state.owners[ni]
			if ow != 0 and ow != GameState.RUINS_OWNER_ID:
				continue
			if state.is_blocked_terrain(state.terrain[ni]):
				continue
			var range_v := _send_range(player.difficulty)
			var frac := state.rng.randf_range(range_v.x, range_v.y)
			sim.player_expand(player.id, nx, ny, frac)
			return
