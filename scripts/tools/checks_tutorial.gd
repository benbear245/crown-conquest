extends RefCounted

# Prompt 16 checks: the tutorial's 7 steps (each waits for you), arrows,
# Skip / finish / retry, no timers, and that it only starts when it should.


func run(t: SmokeTest) -> void:
	await _walkthrough(t)
	await _lost_and_retry(t)
	_rules(t)
	_menus(t)
	SaveData.data = SaveData.defaults()


func _tut(t: SmokeTest) -> Tutorial:
	return t.game.get("_tutorial")


func _frames(t: SmokeTest, n: int) -> void:
	for i in range(n):
		await t.get_tree().process_frame


func _walkthrough(t: SmokeTest) -> void:
	SaveData.data = SaveData.defaults()
	t.new_match_with(MatchConfig.tutorial(), MatchConfig.tutorial().seed_value)
	await _frames(t, 2)
	var tut: Tutorial = _tut(t)
	var st: GameState = t.sim.state
	t.check(tut != null and t.hud.tutorial_card != null and t.hud.tutorial_card.is_visible_in_tree(), "the tutorial card appears in a tutorial match")
	t.check(st.players.size() == 2 and st.players[1].difficulty == Balance.BOT_DIFFICULTY_EASY and st.width == Balance.MAP_SMALL_WIDTH, "small map with 1 Easy bot")
	t.check(tut.card.get("_step").text.contains("Step 1 of 7"), "Step 1 of 7: place your Crown")
	t.check(tut.arrow.target.x >= 0.0, "an arrow points at a good spot")
	var place_left: float = st.placement_time_left
	for i in range(300):
		t.sim.advance_tick()
	t.check(st.phase == Balance.PHASE_PLACEMENT and is_equal_approx(st.placement_time_left, place_left), "no placement timer: it waits for you")
	t.hud.hint("expand")
	t.check(not t.hud.alerts.has_banner("hint_expand"), "first-time tips stay quiet during the tutorial")
	await t.shot("tutorial_1_place")
	# 1. Place: tap the spot the arrow shows.
	var spot: Vector2i = tut.get("_spot")
	await t.zoom_to(spot, 1.0)
	await t.tap_tile(spot)
	await _frames(t, 2)
	t.check(t.me().crown_x >= 0 and tut.step == Tutorial.Step.EXPAND, "placing your Crown moves on to Step 2 (expand)")
	t.sim.advance_tick()
	t.check(st.phase == Balance.PHASE_MATCH, "the match starts as soon as both Crowns are placed")
	await t.shot("tutorial_2_expand")
	# 2. Expand: tap where the arrow points until you've grown enough.
	var me: Player = t.me()
	for k in range(40):
		if tut.step != Tutorial.Step.EXPAND:
			break
		var target: Vector2i = tut.get("_target_world")
		if target.x >= 0:
			await t.zoom_to(target, 1.0)
			await t.tap_tile(target)
		t.ff(1.5, false)
		await _frames(t, 2)
	t.check(tut.step == Tutorial.Step.SWEET_SPOT, "growing 25 tiles moves on to Step 3 (sweet spot)")
	t.check(tut.arrow.target.x >= 0.0 and tut.arrow.target.y < 200.0, "the arrow points at the troop bar")
	await t.shot("tutorial_3_sweet_spot")
	# 3. Sweet spot: wait until the bar is green.
	me.troops = 0.05 * me.troop_cap()
	tut.set("_step_time", 10.0)
	await _frames(t, 2)
	t.check(tut.step == Tutorial.Step.SWEET_SPOT, "...and waits while the bar isn't green")
	me.troops = 0.55 * me.troop_cap()
	await _frames(t, 2)
	t.check(tut.step == Tutorial.Step.ATTACK, "in the sweet spot: Step 4 (attack the bot)")
	t.check(tut.card.current_text().contains("peace") or st.match_time >= Balance.PEACE_PERIOD_SEC, "during the peace period it says when attacks open")
	# 4. Attack: grow until the borders touch (on autopilot), then tap the bot's land.
	var guard: int = 0
	while guard < 60 and (st.match_time < Balance.PEACE_PERIOD_SEC or tut.call("_enemy_tile_next_to_me", me, tut.call("_bot")) < 0):
		t.ff(2.0, true)
		guard += 1
	await _frames(t, 2)
	var enemy_tile: Vector2i = tut.get("_target_world")
	t.check(enemy_tile.x >= 0 and st.owners[st.idx(enemy_tile.x, enemy_tile.y)] == 2, "the arrow points at the bot's land next to yours")
	await t.zoom_to(enemy_tile, 1.0)
	t.hud.send_slider.set("fraction", 0.5)
	me.troops = maxf(me.troops, 0.6 * me.troop_cap())
	await t.tap_tile(enemy_tile)
	await _frames(t, 2)
	t.check(tut.step == Tutorial.Step.FORT, "attacking moves on to Step 5 (build a Fort)")
	await t.shot("tutorial_5_fort")
	# 5. Fort: long-press where the arrow points, then tap Fort.
	me.troops = maxf(me.troops, BuildingsOps.fort_cost_for(me) + 200.0)
	await _frames(t, 2)
	var fort_tile: Vector2i = tut.get("_target_world")
	t.check(fort_tile.x >= 0 and st.owners[st.idx(fort_tile.x, fort_tile.y)] == me.id, "the arrow points at your land facing the bot")
	await t.zoom_to(fort_tile, 1.0)
	await t.long_press_tile(fort_tile)
	await _frames(t, 2)
	t.check(t.hud.build_menu.visible, "a long-press opens the build menu")
	var fort_button: Button = t.hud.build_menu.row_button(BuildMenu.ROW_FORT)
	var fb: Rect2 = fort_button.get_global_rect()
	t.check(fb.grow(40.0).has_point(tut.arrow.target), "with the menu open, the arrow points at the Fort button")
	await t.shot("tutorial_5_fort_menu")
	fort_button.pressed.emit()
	await _frames(t, 2)
	t.check(tut.step == Tutorial.Step.SHIELD, "building a Fort moves on to Step 6 (Crown Shield)")
	var shield: AbilityButton = t.hud.ability_bar.button(AbilitiesOps.ID_CROWN_SHIELD)
	t.check(shield.get_global_rect().grow(10.0).has_point(tut.arrow.target), "the arrow points at the Crown Shield button")
	await t.shot("tutorial_6_shield")
	# 6. Crown Shield.
	shield.pressed.emit()
	await _frames(t, 2)
	t.check(tut.step == Tutorial.Step.CAPTURE, "using Crown Shield moves on to Step 7 (take the bot's Crown)")
	var bot: Player = st.get_player(2)
	t.check((tut.get("_target_world") as Vector2i) == Vector2i(bot.crown_x, bot.crown_y), "the arrow points at the bot's Crown")
	await t.shot("tutorial_7_capture")
	# 7. Capture.
	var xp_before: int = SaveData.xp()
	CombatOps.eliminate_player(t.sim, bot.id, me.id)
	t.sim.advance_tick()
	await _frames(t, 2)
	t.hud.update_from_state()
	t.check(tut.step == Tutorial.Step.DONE and tut.card.current_text().contains("complete"), "taking the Crown completes the tutorial")
	t.check(bool(SaveData.data.profile.get("tutorial_done", false)), "...and it's remembered (won't start again on launch)")
	t.check(not t.hud.end_overlay.visible and SaveData.xp() == xp_before, "no end screen or XP in the tutorial — the card has Play / Main menu")
	await t.shot("tutorial_done")


func _lost_and_retry(t: SmokeTest) -> void:
	SaveData.data = SaveData.defaults()
	t.new_match_with(MatchConfig.tutorial(), MatchConfig.tutorial().seed_value)
	await _frames(t, 2)
	var tut: Tutorial = _tut(t)
	var spot: Vector2i = tut.get("_spot")
	t.sim.player_place_crown(1, spot.x, spot.y)
	t.ff(70.0, true)
	CombatOps.eliminate_player(t.sim, 1, 2)
	t.sim.advance_tick()
	await _frames(t, 2)
	t.check(tut.step == Tutorial.Step.LOST and (tut.card.get("_primary") as Button).text == "Try again", "if the bot takes your Crown: 'Try again'")
	t.check(not bool(SaveData.data.profile.get("tutorial_done", false)), "...and the tutorial isn't marked done")
	(tut.card.get("_primary") as Button).pressed.emit()
	await _frames(t, 2)
	t.check(t.sim.state.phase == Balance.PHASE_PLACEMENT and _tut(t).step == Tutorial.Step.PLACE, "Try again restarts the tutorial from Step 1")
	t.check((tut.card.get("_skip") as Button).visible, "a Skip button is always there while you play")
	# A normal match afterwards has no tutorial.
	t.new_match_with(MatchConfig.skirmish(Balance.MAP_SIZE_SMALL, 0, 2, 0), 5)
	await _frames(t, 2)
	t.check(_tut(t) == null and t.hud.tutorial_card == null, "other modes have no tutorial card")


func _rules(t: SmokeTest) -> void:
	t.new_match_with(MatchConfig.tutorial(), MatchConfig.tutorial().seed_value)
	var st: GameState = t.sim.state
	var tut: Tutorial = _tut(t)
	var spot: Vector2i = tut.get("_spot")
	t.sim.player_place_crown(1, spot.x, spot.y)
	t.ff(10.0, false)
	var me: Player = t.me()
	st.match_time = 700.0
	t.check(not st.is_final_siege(), "no Final Siege in the tutorial")
	me.land = int(0.8 * st.total_usable_tiles())
	st.match_time = 1000.0
	t.sim.advance_tick()
	t.check(st.phase == Balance.PHASE_MATCH, "no Dominion win or 15:00 limit in the tutorial (it ends when a Crown falls)")
	var near_crown: int = st.idx(me.crown_x + 2, me.crown_y)
	t.check(BotMoves._easy_spares_crown(st, me, near_crown), "the tutorial bot never goes for your Crown")
	t.new_match_with(MatchConfig.skirmish(Balance.MAP_SIZE_SMALL, 0, 2, 0), 6)


func _menus(t: SmokeTest) -> void:
	var menu: MenuRoot = (load("res://scenes/menu.tscn") as PackedScene).instantiate()
	var layer := CanvasLayer.new()
	t.add_child(layer)
	layer.add_child(menu)
	menu.show_screen("settings")
	var replay: Button = menu.screen("settings").find_child("ReplayTutorial", true, false)
	t.check(replay != null and replay.is_visible_in_tree(), "Settings has 'Replay tutorial'")
	layer.queue_free()
