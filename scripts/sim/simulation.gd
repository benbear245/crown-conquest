class_name Simulation
extends RefCounted

# Drives the match. 10 ticks per second. Never touches nodes.
# For Prompt 1 it only sets up the state and advances the tick counter.

const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

var state: GameState = GameState.new()


func start_default_match(match_seed: int = 0) -> void:
	state.configure(Balance.MAP_MEDIUM_WIDTH, Balance.MAP_MEDIUM_HEIGHT, match_seed)
	_fill_default_terrain()
	_add_local_player()


func _fill_default_terrain() -> void:
	# Plains everywhere for Prompt 1. Terrain generation lands in Prompt 3.
	for i in range(state.terrain.size()):
		state.terrain[i] = Balance.TERRAIN_PLAINS


func _add_local_player() -> void:
	var p := Player.new()
	p.id = 1
	p.display_name = "You"
	p.color = Balance.color_for_player(1)
	p.troops = Balance.STARTING_TROOPS
	state.players.append(p)
	# Place the starting circle near the left of the map.
	@warning_ignore("integer_division")
	var cy: int = state.height / 2
	var cx: int = 10
	_claim_circle(p, cx, cy, Balance.STARTING_LAND_RADIUS)


func _claim_circle(player: Player, cx: int, cy: int, r: int) -> void:
	var r2 := r * r
	var count := 0
	for y in range(maxi(0, cy - r), mini(state.height, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(state.width, cx + r + 1)):
			var dx := x - cx
			var dy := y - cy
			if dx * dx + dy * dy <= r2:
				state.set_owner(x, y, player.id)
				count += 1
	player.land = count
	player.peak_land = count
	_rebuild_border_for(player)


func _rebuild_border_for(player: Player) -> void:
	player.border.clear()
	for i in range(state.owners.size()):
		if state.owners[i] != player.id:
			continue
		var p := state.idx_to_xy(i)
		for off in NEIGHBOR_OFFSETS:
			var nx := p.x + off.x
			var ny := p.y + off.y
			if not state.in_bounds(nx, ny):
				continue
			if state.get_owner_at(nx, ny) != player.id:
				player.border[i] = true
				break


func advance_tick() -> void:
	# Prompt 1: just advance time. Growth and expansion arrive in Prompt 2.
	state.tick_count += 1
