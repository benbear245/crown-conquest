extends RefCounted

# Prompt 15 checks: XP and levels, unlocks, achievements (incl. mid-match
# pop-ups), end-screen XP animation, cosmetics in a match, safe saving, and
# the Customize / Stats / Achievements screens.

const SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(2400, 1080)]


func run(t: SmokeTest) -> void:
	SaveData.data = SaveData.defaults()
	_xp_and_levels(t)
	_record(t)
	await _match_flow(t)
	await _cosmetics(t)
	_save_safety(t)
	await _screens(t)
	SaveData.data = SaveData.defaults()


static func _result(over: Dictionary) -> Dictionary:
	var r: Dictionary = {
		"mode": MatchConfig.Mode.SKIRMISH, "map_type": Balance.MAP_TYPE_CONTINENT, "won": false, "peak_pct": 10.0,
		"crowns": 0, "duration_sec": 500.0, "hard": false, "win_reason": "", "smallest_at_3min": false,
		"ports_built": 0, "buildings_built": 0, "truces_made": 0, "crown_attacked": true, "sent_to_ally": 0.0,
		"siege_crowns": 0, "daily_score": -1,
	}
	r.merge(over, true)
	return r


func _xp_and_levels(t: SmokeTest) -> void:
	var xp: Dictionary = Progression.match_xp(_result({"won": true, "peak_pct": 41.7, "crowns": 2, "hard": true}))
	t.check(int(xp.total) == 1665, "XP: 100 play + 410 land (41%%) + 300 Crowns + 300 win, ×1.5 on Hard = 1,665 (%d)" % int(xp.total))
	t.check(int(Progression.match_xp(_result({})).total) == 200, "XP: a plain loss with 10% peak land = 200")
	t.check(Progression.xp_needed(1) == 600 and Progression.xp_needed(5) == 1000, "level n needs 500 + 100 × n XP")
	var l: Dictionary = Progression.level_info(1299)
	t.check(int(Progression.level_info(0).level) == 1 and int(Progression.level_info(600).level) == 2 and int(l.level) == 2 and int(l.into) == 699, "levels: 600 XP = level 2, 1,300 XP = level 3")
	var all: Array[String] = []
	for lvl in range(2, 21):
		all.append_array(Progression.unlocks_at(lvl))
	var colors: int = all.filter(func(s: String) -> bool: return s.ends_with("colour")).size()
	var patterns: int = all.filter(func(s: String) -> bool: return s.ends_with("pattern")).size()
	var crowns: int = all.filter(func(s: String) -> bool: return s.ends_with("Crown")).size()
	t.check(colors == 12 and patterns == 6 and crowns == 7, "unlocks: 16 colours (4 free), 6 patterns, 8 Crown icons (1 free)")
	t.check(all.has("title \"Knight\"") and all.has("Confetti victory effect"), "unlocks include titles and victory effects")
	var every_level: bool = true
	for lvl2 in range(2, 16):
		every_level = every_level and not Progression.unlocks_at(lvl2).is_empty()
	t.check(every_level, "every level from 2 to 15 unlocks something")
	t.check(Progression.ACHIEVEMENTS.size() == 12, "12 achievements (the design's 5 + 7 more)")


func _record(t: SmokeTest) -> void:
	SaveData.data = SaveData.defaults()
	var won := _result({"won": true, "peak_pct": 41.7, "crowns": 3, "hard": true, "duration_sec": 330.0,
		"win_reason": "Dominion win (60%+ of the usable map)", "crown_attacked": false, "smallest_at_3min": true})
	var s: Dictionary = SaveData.record_match(won)
	t.check(int(s.xp) == 1890 and int(s.new_level) == 3 and int(s.old_level) == 1, "first match: +1,890 XP, level 1 → 3")
	t.check((s.unlocks as Array).has("Violet colour") and (s.unlocks as Array).has("Stripes pattern") and (s.unlocks as Array).has("Tiara Crown"), "level-ups list what unlocked")
	var fresh: Array = s.new_achievements
	for id: String in ["kingslayer", "underdog", "speedrun", "dominion", "first_victory", "hard_won", "untouchable"]:
		if not fresh.has(id):
			t.check(false, "achievement %s earned" % id)
	t.check(fresh.size() == 7, "that match earns Kingslayer, Underdog, Speedrun, Dominion, First Victory, Hard Won, Untouchable")
	var st: Dictionary = SaveData.data.stats
	t.check(int(st.matches) == 1 and int(st.wins) == 1 and int(st.crowns) == 3 and is_equal_approx(float(st.fastest_win_sec), 330.0), "stats: matches, wins, Crowns, fastest win")
	var s2: Dictionary = SaveData.record_match(_result({"won": false, "mode": MatchConfig.Mode.TEAMS}))
	t.check((s2.new_achievements as Array).is_empty() and int(SaveData.data.stats.matches) == 2 and int((SaveData.data.stats.by_mode.teams as Array)[0]) == 1, "a loss adds a match (per mode) and no repeat achievements")
	t.check(SaveData.titles().has("Knight") and SaveData.titles().has("Kingslayer") and not SaveData.titles().has("Baron"), "titles come from levels and achievements")
	var island := Progression.earned(_result({"won": true, "map_type": Balance.MAP_TYPE_ARCHIPELAGO, "ports_built": 3}))
	var team := Progression.earned(_result({"won": true, "mode": MatchConfig.Mode.TEAMS, "sent_to_ally": 1200.0}))
	var misc := Progression.earned(_result({"buildings_built": 8, "truces_made": 3, "siege_crowns": 1}))
	t.check(island.has("island_king") and team.has("team_player") and misc.has("master_builder") and misc.has("peacemaker") and misc.has("siege_lord"), "Island King, Team Player, Master Builder, Peacemaker, Siege Lord conditions")


func _match_flow(t: SmokeTest) -> void:
	SaveData.data = SaveData.defaults()
	SaveData.data.profile.xp = 590    # 10 XP short of level 2
	var cfg := MatchConfig.skirmish(Balance.MAP_SIZE_SMALL, Balance.MAP_TYPE_CONTINENT, 4, Balance.BOT_DIFFICULTY_EASY)
	t.new_match_with(cfg, 515)
	t.skip_placement()
	t.ff_safe(70.0, true)
	var st: GameState = t.sim.state
	var me: Player = t.me()
	# Take three Crowns: Kingslayer pops up mid-match.
	var taken: int = 0
	for p: Player in st.players:
		if p.id != me.id and p.is_alive and taken < 3:
			CombatOps.eliminate_player(t.sim, p.id, me.id)
			taken += 1
	t.game.call("_observe_achievements", st.events)
	st.events.clear()
	t.check(SaveData.has_achievement("kingslayer") and t.hud.alerts.has_banner("ach_kingslayer"), "Kingslayer pops up the moment you take your third Crown")
	t.sim.advance_tick()   # last bot standing: the match ends
	for p: Player in st.players:
		if p.id != me.id and p.is_alive:
			CombatOps.eliminate_player(t.sim, p.id, me.id)
	t.sim.advance_tick()
	t.check(st.phase == Balance.PHASE_ENDED and t.sim.local_won(), "match won")
	t.game.call("_record_result_once")
	t.hud.update_from_state()
	var xp_panel: XpPanel = t.hud.end_overlay.xp_panel
	t.check(xp_panel.visible and (xp_panel.get("_gain") as Label).text.begins_with("+"), "end screen shows the XP gained")
	t.check(t.hud.end_overlay.victory_effect.is_playing(), "a victory effect (Fireworks) plays when you win")
	var ach_text: String = (xp_panel.get("_achievements") as Label).text
	t.check(ach_text.contains("Kingslayer") and ach_text.contains("First Victory"), "end screen lists this match's achievements (%s)" % ach_text)
	var leveled: bool = false
	for i in range(150):
		await t.get_tree().process_frame
		if xp_panel.level_up_shown():
			leveled = true
			break
	t.check(leveled, "the XP bar fills and 'LEVEL UP!' pops when you cross a level")
	await t.shot("progress_end_screen")
	for i in range(80):
		await t.get_tree().process_frame
	await t.shot("progress_end_screen_done")
	t.check(int(SaveData.data.stats.wins) == 1 and SaveData.level() >= 2, "the win and XP are saved")
	# The tutorial gives no XP.
	var before: int = SaveData.xp()
	t.new_match_with(MatchConfig.tutorial(), 1)
	var spot: Vector2i = CrownsOps.find_valid_crown_position(t.sim.state)
	t.sim.player_place_crown(t.sim.local_player_id, spot.x, spot.y)
	t.skip_placement()
	t.sim.end_match(t.sim.local_player_id, "test")
	t.game.call("_record_result_once")
	t.check(SaveData.xp() == before, "the tutorial doesn't give XP")


func _cosmetics(t: SmokeTest) -> void:
	SaveData.data = SaveData.defaults()
	SaveData.data.profile.xp = 20000          # level 15+
	SaveData.data.cosmetics.color = 5          # Tangerine
	SaveData.data.cosmetics.pattern = 1        # Stripes
	SaveData.data.cosmetics.crown = 3          # Star
	t.new_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 616)
	t.skip_placement()
	t.ff(20.0, true)
	var st: GameState = t.sim.state
	t.check(Palette.player(1).is_equal_approx(Progression.COLORS[5]), "your chosen colour is used for your land")
	var distinct: bool = true
	for p: Player in st.players:
		if p.id != 1:
			distinct = distinct and Palette._distance(Palette.player(p.id), Palette.player(1)) >= Palette.CLASH_DISTANCE
	t.check(distinct, "a bot whose colour clashes with yours gets a different one")
	var map: Map = t.game.get_node("Map")
	t.check(map.pattern == 1 and (t.game.get("_overlay") as WorldOverlay).local_crown_style == 3, "your pattern and Crown icon are applied")
	var stripe: Color = Color.BLACK
	var plain: Color = Color.BLACK
	map.render()
	var img: Image = map.get("_image")
	for i in range(st.owners.size()):
		if st.owners[i] != 1 or st.crown_tiles.has(i) or st.building_at_tile.has(i) or st.flash_tiles.has(i) or st.terrain[i] != Balance.TERRAIN_PLAINS:
			continue
		var xy: Vector2i = st.idx_to_xy(i)
		if Progression.pattern_shade(1, xy.x, xy.y) > 0.0:
			stripe = img.get_pixelv(xy)
		else:
			plain = img.get_pixelv(xy)
	t.check(stripe != Color.BLACK and plain != Color.BLACK and stripe.v < plain.v, "the pattern shows on your land (striped tiles are darker)")
	await t.zoom_to(Vector2i(t.me().crown_x, t.me().crown_y), 3.0)
	await t.shot("cosmetics_in_match")
	# Locked choices are ignored.
	SaveData.data.profile.xp = 0
	SaveData.data.cosmetics.pattern = 6
	t.new_match(Balance.MAP_SIZE_SMALL, Balance.MAP_TYPE_CONTINENT, 617)
	t.check(map.pattern == 0 and Palette.player(1).is_equal_approx(Balance.PLAYER_COLORS[1]), "locked cosmetics fall back to the defaults")
	# Colour-blind palette beats a custom colour.
	SaveData.data.profile.xp = 20000
	SaveData.data.cosmetics.color = 5
	Settings.colorblind = true
	t.new_match(Balance.MAP_SIZE_SMALL, Balance.MAP_TYPE_CONTINENT, 618)
	t.check(Palette.player(1).is_equal_approx(Balance.PLAYER_COLORS_COLORBLIND[1]), "the colour-blind palette overrides a custom colour")
	Settings.colorblind = false
	SaveData.data = SaveData.defaults()
	t.new_match(Balance.MAP_SIZE_SMALL, Balance.MAP_TYPE_CONTINENT, 619)


func _save_safety(t: SmokeTest) -> void:
	SaveData.data = SaveData.defaults()
	SaveData.data.profile.xp = 4321
	t.check(SaveData.save() and FileAccess.file_exists(SaveData.PATH) and not FileAccess.file_exists(SaveData.TMP_PATH), "save writes save.json via a temp file")
	SaveData.data = {}
	SaveData.load_save()
	t.check(SaveData.xp() == 4321, "progress loads back")
	# A crash between writing the temp file and renaming it: the temp file is used.
	var f := FileAccess.open(SaveData.TMP_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"profile": {"xp": 999}}))
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.PATH))
	SaveData.load_save()
	t.check(SaveData.xp() == 999 and SaveData.data.has("stats"), "if save.json is missing, the temp copy is loaded (and new fields get defaults)")
	# A corrupt save never crashes: defaults are used.
	var g := FileAccess.open(SaveData.PATH, FileAccess.WRITE)
	g.store_string("{ not json")
	g.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SaveData.TMP_PATH))
	SaveData.load_save()
	t.check(SaveData.xp() == 0, "a corrupt save falls back to a fresh profile instead of crashing")
	SaveData.data = SaveData.defaults()
	SaveData.save()


func _screens(t: SmokeTest) -> void:
	SaveData.data = SaveData.defaults()
	SaveData.data.profile.xp = 3500        # level 5 (levels 1-4 take 600 + 700 + 800 + 900)
	SaveData.unlock_achievement("kingslayer")
	var menu: MenuRoot = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	var layer := CanvasLayer.new()
	layer.layer = 50
	t.add_child(layer)
	layer.add_child(menu)
	await t.get_tree().process_frame
	t.check((menu.screen("main").get("_profile") as Label).text.contains("Level 5"), "main menu shows your level and title")
	menu.show_screen("customize")
	var cz: CustomizeScreen = menu.screen("customize")
	await t.get_tree().process_frame
	var grid: GridContainer = cz.get("_grid")
	var buttons: Array = grid.get_children()
	var locked: int = buttons.filter(func(b: Button) -> bool: return b.disabled).size()
	t.check(buttons.size() == 16 and locked == 16 - 8, "Colour tab: 16 colours, 8 unlocked at level 5, the rest show their level")
	(buttons[6] as Button).pressed.emit()        # Teal (level 4)
	t.check(int(SaveData.cosmetic("color")) == 6 and cz.preview.color.is_equal_approx(Progression.COLORS[6]), "picking a colour saves it and updates the live preview")
	await _fits_all(t, menu, "customize", "customize_colour")
	for tab in range(1, 5):
		cz.tab_row.select(tab)
		cz.tab_row.changed.emit(tab)
		await t.get_tree().process_frame
		await _fits_all(t, menu, "customize", "customize_" + CustomizeScreen.TABS[tab].to_lower().replace(" ", "_"))
	cz.tab_row.select(2)
	cz.tab_row.changed.emit(2)
	(grid.get_child(1) as Button).pressed.emit()   # Tiara
	t.check(cz.preview.crown == 1, "picking a Crown icon updates the preview")
	cz.tab_row.select(3)
	cz.tab_row.changed.emit(3)
	var titles: Array[String] = []
	for b: Node in grid.get_children():
		if not (b as Button).disabled:
			titles.append((b as Button).text)
	t.check(titles.has("Kingslayer") and titles.has("Knight") and not titles.has("Baron"), "Title tab: level titles and achievement titles you've earned")
	menu.show_screen("stats")
	await t.get_tree().process_frame
	await _fits_all(t, menu, "stats", "stats")
	menu.show_screen("achievements")
	await t.get_tree().process_frame
	var ach: AchievementsScreen = menu.screen("achievements")
	t.check((ach.get("_grid") as GridContainer).get_child_count() == 12, "Achievements screen lists all 12")
	await _fits_all(t, menu, "achievements", "achievements")
	layer.queue_free()
	await t.get_tree().process_frame


func _fits_all(t: SmokeTest, menu: MenuRoot, screen_name: String, shot_name: String) -> void:
	for sz: Vector2i in SIZES:
		t.get_window().content_scale_size = sz
		await t.get_tree().process_frame
		await t.get_tree().process_frame
		var root_c: Control = menu.screen(screen_name)
		var view: Rect2 = menu.get_viewport_rect()
		var ok: bool = view.encloses(root_c.get_global_rect().grow(-1.0))
		for b: Node in root_c.find_children("*", "Button", true, false):
			var btn: Button = b
			if btn.is_visible_in_tree():
				ok = ok and btn.size.y >= Balance.MIN_BUTTON_PX - 0.5 and view.encloses(btn.get_global_rect().grow(-1.0))
		t.check(ok, "%s fits on a %dx%d screen" % [shot_name, sz.x, sz.y])
	t.get_window().content_scale_size = Vector2i(1920, 1080)
	await t.get_tree().process_frame
	await t.shot("menu_" + shot_name)
