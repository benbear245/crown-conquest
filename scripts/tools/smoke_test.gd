class_name SmokeTest
extends Node

# Drives the real game scene (scenes/main.tscn) fast, exercises features via
# the same input events / signals a player would use, and prints PASS / FAIL.
# Run headless:
#   godot --headless --path . res://scenes/tools/smoke_test.tscn
# With screenshots (needs a display):
#   godot --path . res://scenes/tools/smoke_test.tscn -- --shots <dir>
# Optional: --only buildings,abilities,...   to run some suites.

var game: Node
var sim: Simulation
var hud: HUD
var shots_dir: String = ""
var _passed: int = 0
var _failed: int = 0
var _suites: Array[String] = []


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--shots" and i + 1 < args.size():
			shots_dir = args[i + 1]
			DirAccess.make_dir_recursive_absolute(shots_dir)
		elif args[i] == "--only" and i + 1 < args.size():
			for s: String in args[i + 1].split(","):
				_suites.append(s.strip_edges())
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	game.set_process(false)   # the test owns the clock
	sim = game.get("_simulation")
	hud = game.get("_hud")
	await _run_all()
	print("[smoke] %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _run_all() -> void:
	var suites: Dictionary = {
		"buildings": preload("res://scripts/tools/checks_buildings.gd"),
	}
	for key: String in suites.keys():
		if not _suites.is_empty() and not _suites.has(key):
			continue
		print("[smoke] --- %s ---" % key)
		var suite: RefCounted = suites[key].new()
		await suite.run(self)


# --- Helpers for check suites -------------------------------------------------

func new_match(size: int, map_type: int, match_seed: int) -> void:
	sim.headless = false
	sim.start_match(size, map_type, match_seed)
	game.call("_bind_match")
	hud.end_overlay.reset()


func me() -> Player:
	return sim.state.get_player(sim.local_player_id)


# Advances the sim `seconds` of match time, keeping the HUD and map in sync.
# With autopilot the local player plays as a Normal bot meanwhile.
func ff(seconds: float, autopilot: bool = true) -> void:
	var ticks: int = int(round(seconds * float(Balance.TICKS_PER_SECOND)))
	var mine: Player = me()
	if autopilot and mine != null:
		mine.is_bot = true
		mine.difficulty = Balance.BOT_DIFFICULTY_NORMAL
	for i in range(ticks):
		sim.advance_tick()
		sim.state.events.clear()
		if i % 50 == 0:
			_refresh()
	if mine != null:
		mine.is_bot = false
	_refresh()


# Like ff, but tops the local player's troops up to 40% of the cap when low,
# so it survives long fast-forwards without steamrolling everyone.
func ff_safe(seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		var step: float = minf(5.0, left)
		var mine: Player = me()
		if mine != null and mine.is_alive:
			mine.troops = maxf(mine.troops, 0.4 * mine.troop_cap())
		ff(step)
		left -= step


func _refresh() -> void:
	(game.get_node("Map") as Map).render()
	hud.update_from_state()
	game.call("_sync_overlay")


func skip_placement() -> void:
	while sim.state.phase == Balance.PHASE_PLACEMENT:
		sim.advance_tick()
	_refresh()


func tile_to_screen(t: Vector2i) -> Vector2:
	return get_viewport().canvas_transform * (Vector2(t) + Vector2(0.5, 0.5))


func tap_tile(t: Vector2i) -> void:
	await press(tile_to_screen(t))
	await release(tile_to_screen(t))


func press(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev, true)
	await get_tree().process_frame


func release(pos: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = pos
	ev.global_position = pos
	get_viewport().push_input(ev, true)
	await get_tree().process_frame


func drag_to(from: Vector2, to: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = to
	ev.global_position = to
	ev.relative = to - from
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	get_viewport().push_input(ev, true)
	await get_tree().process_frame


# Holds the pointer down long enough for a long-press, then releases.
func long_press_tile(t: Vector2i) -> void:
	var pos: Vector2 = tile_to_screen(t)
	await press(pos)
	game.call("_check_long_press", 0.5)
	await release(pos)


func zoom_to(t: Vector2i, factor: float) -> void:
	var cam: CameraRig = game.get_node("Camera2D")
	cam.zoom_by(factor)
	cam.look_at_tile(t)
	await get_tree().process_frame


func shot(shot_name: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	_refresh()
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(shots_dir.path_join(shot_name + ".png"))
	print("[smoke] screenshot %s" % shot_name)


func check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("[smoke] PASS %s" % what)
	else:
		_failed += 1
		print("[smoke] FAIL %s" % what)


# --- Map searches --------------------------------------------------------------

# First own tile (spiralling out from `centre`) where pred(tile_idx) is true.
func find_own_tile(centre: Vector2i, max_r: int, pred: Callable) -> Vector2i:
	var st: GameState = sim.state
	for r in range(0, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var x: int = centre.x + dx
				var y: int = centre.y + dy
				if not st.in_bounds(x, y):
					continue
				var ti: int = st.idx(x, y)
				if st.owners[ti] == sim.local_player_id and pred.call(ti):
					return Vector2i(x, y)
	return Vector2i(-1, -1)
