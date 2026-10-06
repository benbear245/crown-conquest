extends Node

# Scene-flow check: the app opens on the menu, Play starts the chosen match,
# the pause menu's Quit returns to the menu, and Daily returns to its screen.
# Run headless:  godot --headless --path . res://scenes/tools/flow_test.tscn

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# Survive scene changes: hand the "current scene" role to a dummy node,
	# so changing scenes frees the dummy and not this test.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dummy := Node.new()
	get_tree().root.add_child.call_deferred(dummy)
	await get_tree().process_frame
	get_tree().current_scene = dummy
	var saved_setup: Dictionary = Settings.last_setup.duplicate(true)
	var saved_data: Dictionary = SaveData.data.duplicate(true)
	await _first_launch()
	await _run()
	Settings.last_setup = saved_setup
	Settings.save_settings()
	SaveData.data = saved_data
	SaveData.save()
	print("[flow] %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# A brand-new player: the tutorial starts by itself; Skip goes to the menu
# and it doesn't start again.
func _first_launch() -> void:
	SaveData.data = SaveData.defaults()
	Session.booted = false
	get_tree().change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _frames(5)
	var game: Node = get_tree().current_scene
	var tut: Tutorial = game.get("_tutorial") if game != null and game.has_method("pause_game") else null
	_check(tut != null, "first launch starts the tutorial")
	if tut == null:
		return
	game.set("auto_pause", false)
	(tut.card.get("_skip") as Button).pressed.emit()
	await _frames(4)
	_check(get_tree().current_scene is MenuRoot and bool(SaveData.data.profile.get("tutorial_done", false)), "Skip goes to the main menu and remembers it")
	Session.booted = false
	get_tree().change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _frames(4)
	_check(get_tree().current_scene is MenuRoot, "next launch opens the menu, not the tutorial")


func _run() -> void:
	get_tree().change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await _frames(3)
	var menu: Node = get_tree().current_scene
	_check(menu is MenuRoot and (menu as MenuRoot).current == "main", "the app opens on the main menu")
	(menu as MenuRoot).show_screen("skirmish")
	var sk: SkirmishScreen = (menu as MenuRoot).screen("skirmish")
	sk.size_row.select(Balance.MAP_SIZE_SMALL)
	sk.size_row.changed.emit(Balance.MAP_SIZE_SMALL)
	sk.diff_row.select(Balance.BOT_DIFFICULTY_HARD)
	(sk.find_child("Action", true, false) as Button).pressed.emit()
	await _frames(4)
	var game: Node = get_tree().current_scene
	_check(game != null and game.has_method("pause_game"), "Start opens the game scene")
	if game == null or not game.has_method("pause_game"):
		return
	game.set("auto_pause", false)
	var sim: Simulation = game.get("_simulation")
	_check(sim.size_preset == Balance.MAP_SIZE_SMALL and sim.state.players.size() == 5, "the match uses the Skirmish setup (Small, 4 bots)")
	_check(sim.state.players.slice(1).all(func(p: Player) -> bool: return p.difficulty == Balance.BOT_DIFFICULTY_HARD), "...with Hard bots")
	await _frames(20)
	_check(sim.state.tick_count > 0, "the match runs")
	game.call("pause_game")
	var t0: int = sim.state.tick_count
	await _frames(20)
	_check(get_tree().paused and sim.state.tick_count == t0, "pausing stops the match clock")
	var hud: HUD = game.get("_hud")
	hud.pause_menu.resume_pressed.emit()
	await _frames(20)
	_check(not get_tree().paused and sim.state.tick_count > t0, "resume carries on")
	game.call("pause_game")
	hud.pause_menu.quit_pressed.emit()
	await _frames(4)
	menu = get_tree().current_scene
	_check(menu is MenuRoot and not get_tree().paused, "Quit returns to the menu, un-paused")
	Session.play(DailyScreen.today())
	await _frames(4)
	game = get_tree().current_scene
	game.set("auto_pause", false)
	var dsim: Simulation = game.get("_simulation")
	_check(dsim.config.mode == MatchConfig.Mode.DAILY and dsim.state.match_seed == DailyScreen.today().seed_value, "Daily Challenge starts today's seeded map")
	(game.get("_hud") as HUD).end_overlay.menu_pressed.emit()
	await _frames(4)
	menu = get_tree().current_scene
	_check(menu is MenuRoot and (menu as MenuRoot).current == "daily", "leaving a Daily match goes back to the Daily screen")


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[flow] %s %s" % ["PASS" if ok else "FAIL", what])
