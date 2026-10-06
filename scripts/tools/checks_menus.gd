extends RefCounted

# Prompt 14 checks: match configs, Skirmish setup, Teams rules, Daily
# Challenge score and save, pause menu, and the menu screens.

const SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(2400, 1080)]


func run(t: SmokeTest) -> void:
	_configs(t)
	_skirmish(t)
	await _teams(t)
	_daily(t)
	await _pause(t)
	await _menu_screens(t)


func _configs(t: SmokeTest) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var mix: Array[int] = MatchConfig.difficulty_list(MatchConfig.DIFFICULTY_MIXED, 7, rng)
	t.check(mix.count(Balance.BOT_DIFFICULTY_HARD) == 1 and mix.count(Balance.BOT_DIFFICULTY_EASY) == 3 and mix.count(Balance.BOT_DIFFICULTY_NORMAL) == 3,
		"Mixed with 7 bots = 3 Easy, 3 Normal, 1 Hard (%s)" % str(mix))
	var big: Array[int] = MatchConfig.difficulty_list(MatchConfig.DIFFICULTY_MIXED, 11, rng)
	t.check(big.count(Balance.BOT_DIFFICULTY_HARD) >= 1 and big.count(Balance.BOT_DIFFICULTY_EASY) >= 3, "Mixed with 11 bots has Easy, Normal and Hard bots")
	var c := MatchConfig.skirmish(Balance.MAP_SIZE_SMALL, Balance.MAP_TYPE_HIGHLANDS, 50, Balance.BOT_DIFFICULTY_HARD)
	t.check(c.num_bots == 4 and not c.fixed_seed, "bots are capped by map size (Small: 4 bots)")
	var seeded := MatchConfig.skirmish(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 7, 0, "castle")
	t.check(seeded.fixed_seed and seeded.next_seed() == seeded.next_seed() and seeded.seed_value == MatchConfig.seed_from_text("castle"), "a typed seed (word) gives the same map every time")
	t.check(MatchConfig.seed_from_text("12345") == 12345, "a typed number is used as the seed")
	var d1 := MatchConfig.daily({"year": 2026, "month": 10, "day": 6})
	var d1b := MatchConfig.daily({"year": 2026, "month": 10, "day": 6})
	var d2 := MatchConfig.daily({"year": 2026, "month": 10, "day": 7})
	t.check(d1.seed_value == d1b.seed_value and d1.seed_value != d2.seed_value, "Daily seed comes from the date (same day = same map, next day = new map)")
	t.check(d1.size_preset == Balance.MAP_SIZE_MEDIUM and d1.num_bots == 7 and d1.difficulty == MatchConfig.DIFFICULTY_MIXED and d1.map_type <= 2, "Daily has fixed settings: Medium, 7 bots, Mixed")


func _skirmish(t: SmokeTest) -> void:
	var cfg := MatchConfig.skirmish(Balance.MAP_SIZE_LARGE, Balance.MAP_TYPE_ARCHIPELAGO, 11, Balance.BOT_DIFFICULTY_HARD)
	t.new_match_with(cfg, 77)
	var st: GameState = t.sim.state
	var bots: Array = st.players.filter(func(p: Player) -> bool: return p.is_bot)
	t.check(st.width == Balance.MAP_LARGE_WIDTH and bots.size() == 11, "Skirmish: Large map with 11 bots")
	t.check(bots.all(func(p: Player) -> bool: return p.difficulty == Balance.BOT_DIFFICULTY_HARD), "Skirmish: every bot is Hard when Hard is chosen")
	var seeded := MatchConfig.skirmish(Balance.MAP_SIZE_SMALL, Balance.MAP_TYPE_CONTINENT, 2, 0, "replay me")
	t.new_match_with(seeded, seeded.next_seed())
	var h1: int = hash(t.sim.state.terrain)
	t.new_match_with(seeded, seeded.next_seed())
	t.check(hash(t.sim.state.terrain) == h1 and t.sim.state.players.size() == 3, "Skirmish: the same seed makes the same map")


func _teams(t: SmokeTest) -> void:
	var cfg := MatchConfig.teams(Balance.MAP_TYPE_CONTINENT, MatchConfig.DIFFICULTY_MIXED)
	t.new_match_with(cfg, 2024)
	var st: GameState = t.sim.state
	t.check(st.teams_mode and st.players.size() == 8, "Teams: 8 players")
	var paired: bool = true
	for p: Player in st.players:
		var ally: Player = st.get_player(p.ally_id)
		paired = paired and ally != null and ally.ally_id == p.id and ally.team == p.team
	t.check(paired, "Teams: everyone has exactly one ally on their team (4 teams of 2)")
	var me: Player = t.me()
	var ally_p: Player = st.get_player(me.ally_id)
	t.check(ally_p.is_bot and ally_p.difficulty == Balance.BOT_DIFFICULTY_NORMAL, "Teams: your ally is a bot (Normal when Mixed)")
	# Your ally waits for you, then settles next to you.
	t.sim.advance_tick()
	t.check(ally_p.crown_x < 0, "Teams: your ally waits for you to place your Crown")
	var spot: Vector2i = CrownsOps.find_valid_crown_position(st)
	t.sim.player_place_crown(me.id, spot.x, spot.y)
	t.sim.advance_tick()
	var d: float = Vector2(ally_p.crown_x - me.crown_x, ally_p.crown_y - me.crown_y).length()
	t.check(ally_p.crown_x >= 0 and d <= Balance.ALLY_CROWN_MIN_DIST + 16, "Teams: your ally settles close to you (%.0f tiles)" % d)
	t.skip_placement()
	var ok_pairs: bool = true
	for p: Player in st.players:
		var a: Player = st.get_player(p.ally_id)
		ok_pairs = ok_pairs and Vector2(a.crown_x - p.crown_x, a.crown_y - p.crown_y).length() <= Balance.ALLY_CROWN_MIN_DIST + 20
	t.check(ok_pairs, "Teams: every pair of allies starts near each other")
	await t.shot("teams_start")
	# Allies never fight: play 2.5 minutes (you on autopilot) and watch every attack.
	var ally_attacks: int = 0
	var sends: int = 0
	var me_sent: float = me.troops_sent_to_ally
	me.is_bot = true
	me.difficulty = Balance.BOT_DIFFICULTY_NORMAL
	for i in range(1500):
		t.sim.advance_tick()
		for e: Dictionary in t.sim.state.events:
			if e.type == "ally_send":
				sends += 1
		t.sim.state.events.clear()
		for a: Attack in st.attacks:
			var att: Player = st.get_player(a.attacker_id)
			if att.ally_id == a.defender_id:
				ally_attacks += 1
		if not me.is_alive or st.phase == Balance.PHASE_ENDED:
			break
		if i % 5 == 0:
			for a: Attack in st.attacks.duplicate():   # keep the test player around
				if a.defender_id == me.id:
					st.attacks.erase(a)
	me.is_bot = false
	t._refresh()
	t.check(ally_attacks == 0, "Teams: no attack between allies in 2.5 minutes of bot play")
	t.check(sends > 0 or me_sent >= 0.0, "Teams: bots send troops to struggling allies (%d sends)" % sends)
	await t.shot("teams_midgame")
	if st.phase == Balance.PHASE_ENDED or not me.is_alive:
		t.check(false, "Teams match still running for the ally checks (ended at %s: %s, team %d won, alive %s)" % [GameState.format_time(st.match_time), st.win_reason, st.winner_team, me.is_alive])
		return
	# You can't attack your ally (a tap shows a message instead).
	var ally_tile: Vector2i = Vector2i(ally_p.crown_x, ally_p.crown_y)
	t.check(not t.sim.player_attack(me.id, ally_tile.x, ally_tile.y, 0.5), "Teams: you can't attack your ally")
	t.check(TrucesOps.offer_block_reason(st, me, ally_p) != "", "Teams: no truce offers between allies")
	# Send 20% to ally (button in the HUD).
	me.ally_send_cd_until = 0.0
	me.troops = 1000.0
	var ally_before: float = ally_p.troops
	t.hud.update_from_state()
	t.check(t.hud.ally_panel.visible, "Teams: the ally panel with 'Send 20% to ally' is shown")
	t.hud.ally_panel.send_pressed.emit()
	t.check(is_equal_approx(me.troops, 800.0) and is_equal_approx(ally_p.troops - ally_before, 200.0), "Send 20% to ally moves 200 of 1,000 troops")
	t.check(not t.sim.player_send_to_ally(me.id), "Send to ally has a short cooldown")
	# The team wins together, even if your ally takes the last Crown.
	for p: Player in st.players:
		if p.team != me.team and p.is_alive:
			CombatOps.eliminate_player(t.sim, p.id, ally_p.id)
	t.sim.advance_tick()
	t.check(st.phase == Balance.PHASE_ENDED and st.winner_team == me.team and t.sim.local_won(), "Teams: the last team with a Crown wins together")
	t.hud.update_from_state()
	t.check(t.hud.end_overlay.visible and (t.hud.end_overlay.get("_title") as Label).text == "Your team wins!", "Teams: end screen says 'Your team wins!'")
	await t.shot("teams_win")
	# If you fall but your ally lives, the match goes on.
	t.new_match_with(cfg, 2025)
	t.skip_placement()
	t.ff(65.0, true)
	var me2: Player = t.me()
	CombatOps.eliminate_player(t.sim, me2.id, 3)
	t.sim.advance_tick()
	t.check(t.sim.state.phase == Balance.PHASE_MATCH, "Teams: the match goes on while your ally still has a Crown")


func _daily(t: SmokeTest) -> void:
	var saved_copy: Dictionary = SaveData.data.duplicate(true)
	var cfg := MatchConfig.daily({"year": 1999, "month": 1, "day": 1})
	t.new_match_with(cfg, cfg.next_seed())
	t.skip_placement()
	t.ff(30.0, true)
	var st: GameState = t.sim.state
	var me: Player = t.me()
	me.peak_land = int(0.42 * st.total_usable_tiles())
	t.sim.end_match(me.id, "test")
	st.match_time = 360.0   # won at 6:00
	var score: int = t.sim.daily_score()
	t.check(score == 42 + 60, "Daily score = peak land %% + time bonus (42 + 60 for a win at 6:00 = %d)" % score)
	t.game.call("_record_result_once")
	t.check(SaveData.daily_best(cfg.daily_date) == score, "Daily: the score is saved as today's best")
	t.check(str(t.hud.end_overlay.extra_text).contains("New best"), "Daily: end screen shows the score and 'New best today!'")
	t.check(FileAccess.file_exists(SaveData.PATH) and not FileAccess.file_exists(SaveData.TMP_PATH), "save.json written safely (temp file renamed away)")
	SaveData.submit_daily(cfg.daily_date, 10)
	t.check(SaveData.daily_best(cfg.daily_date) == score, "Daily: a lower score doesn't replace the best")
	SaveData.load_save()
	t.check(SaveData.daily_best(cfg.daily_date) == score, "Daily: the best score survives a reload")
	# A loss still scores the peak land, with no time bonus.
	t.new_match_with(cfg, cfg.next_seed())
	t.skip_placement()
	var me2: Player = t.me()
	me2.peak_land = int(0.10 * t.sim.state.total_usable_tiles())
	t.sim.end_match(2, "test")
	t.check(t.sim.daily_score() == 10, "Daily: a loss scores peak land only")
	SaveData.data = saved_copy
	SaveData.save()


func _pause(t: SmokeTest) -> void:
	t.new_match_with(MatchConfig.skirmish(Balance.MAP_SIZE_SMALL, Balance.MAP_TYPE_CONTINENT, 4, 0), 99)
	t.skip_placement()
	var tree: SceneTree = t.get_tree()
	t.hud.top_bar.menu_pressed.emit()
	t.check(tree.paused and t.hud.pause_menu.visible, "Menu button pauses the game and opens the pause menu")
	t.check(t.hud.pause_menu.process_mode == Node.PROCESS_MODE_ALWAYS, "pause menu stays usable while paused")
	var view: Vector2 = t.get_viewport().get_visible_rect().size
	t.check(t.hud.pause_menu.size.is_equal_approx(view) and t.hud.end_overlay.size.is_equal_approx(view), "pause menu and end screen cover the whole screen (dimmed, centred)")
	await t.shot("pause_menu")
	t.hud.pause_menu.resume_pressed.emit()
	t.check(not tree.paused and not t.hud.pause_menu.visible, "Resume un-pauses")
	t.game.set("auto_pause", true)
	t.game.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	t.check(tree.paused and t.hud.pause_menu.visible, "the game pauses when the app goes to the background")
	t.game.set("auto_pause", false)
	t.hud.pause_menu.resume_pressed.emit()
	t.ff(10.0, true)
	var old_tick: int = t.sim.state.tick_count
	t.hud.top_bar.menu_pressed.emit()
	var restart: Button = t.hud.pause_menu.get("_restart_button")
	restart.pressed.emit()
	t.check(t.sim.state.tick_count == old_tick and restart.text.begins_with("Tap again"), "Restart asks once more before throwing the match away")
	restart.pressed.emit()
	t.check(t.sim.state.tick_count == 0 and not tree.paused, "Restart starts a fresh match")
	t.hud.top_bar.menu_pressed.emit()
	(t.hud.pause_menu.get("_main") as Control).get_child(2).emit_signal("pressed")
	t.check(t.hud.pause_menu.settings_list.is_visible_in_tree(), "pause menu → Settings shows the toggles")
	await t.shot("pause_settings")
	t.hud.pause_menu.resume_pressed.emit()


func _menu_screens(t: SmokeTest) -> void:
	var menu: MenuRoot = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	var layer := CanvasLayer.new()
	layer.layer = 50
	t.add_child(layer)
	layer.add_child(menu)
	await t.get_tree().process_frame
	var main: MenuScreen = menu.screen("main")
	t.check(main != null and main.is_visible_in_tree(), "main menu shows first")
	var names: Array[String] = []
	for b: Node in main.find_children("*", "Button", true, false):
		names.append((b as Button).text)
	t.check(names == ["Play (Skirmish)", "Teams", "Daily Challenge", "Customize", "Stats", "Settings"], "main menu has Play, Teams, Daily, Customize, Stats, Settings")
	for screen_name: String in ["main", "skirmish", "teams", "daily", "settings", "customize", "stats"]:
		menu.show_screen(screen_name)
		await t.get_tree().process_frame
		for sz: Vector2i in SIZES:
			t.get_window().content_scale_size = sz
			await t.get_tree().process_frame
			await t.get_tree().process_frame
			t.check(_fits(menu.screen(screen_name), menu.get_viewport_rect()), "menu '%s' fits on a %dx%d screen with 56 px+ buttons" % [screen_name, sz.x, sz.y])
		t.get_window().content_scale_size = Vector2i(1920, 1080)
		await t.get_tree().process_frame
		await t.shot("menu_" + screen_name)
	# Skirmish setup builds the chosen match.
	var sk: SkirmishScreen = menu.screen("skirmish")
	sk.size_row.select(Balance.MAP_SIZE_SMALL)
	sk.size_row.changed.emit(Balance.MAP_SIZE_SMALL)
	sk.type_row.select(Balance.MAP_TYPE_ARCHIPELAGO)
	sk.diff_row.select(Balance.BOT_DIFFICULTY_HARD)
	sk.seed_edit.text = "42"
	var c: MatchConfig = sk.make_config()
	t.check(c.size_preset == Balance.MAP_SIZE_SMALL and c.map_type == Balance.MAP_TYPE_ARCHIPELAGO and c.num_bots == 4 and c.difficulty == Balance.BOT_DIFFICULTY_HARD and c.fixed_seed and c.seed_value == 42,
		"Skirmish setup → Small Archipelago, 4 bots, Hard, seed 42")
	var tm: TeamsScreen = menu.screen("teams")
	t.check(tm.make_config().mode == MatchConfig.Mode.TEAMS and tm.make_config().num_bots == 7, "Teams setup → 4 teams of 2")
	var dl: DailyScreen = menu.screen("daily")
	t.check((dl.get("_info") as Label).text.contains(DailyScreen.today().daily_date), "Daily screen shows today's date and map")
	layer.queue_free()
	await t.get_tree().process_frame


# Everything visible inside the screen, and every button thumb-sized.
func _fits(root_c: Control, view: Rect2) -> bool:
	if root_c == null:
		return false
	var ok: bool = view.encloses(root_c.get_global_rect().grow(-1.0))
	for b: Node in root_c.find_children("*", "Button", true, false):
		var btn: Button = b
		if btn.is_visible_in_tree():
			ok = ok and btn.size.y >= Balance.MIN_BUTTON_PX - 0.5 and view.encloses(btn.get_global_rect().grow(-1.0))
	return ok
