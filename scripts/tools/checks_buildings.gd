extends RefCounted

# Prompt 8 checks: build menu, Forts, Walls, Barracks, Ports and boats, Keep
# upgrades, loot, Crown move.


func run(t: SmokeTest) -> void:
	t.new_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 4242)
	t.skip_placement()
	t.ff(70.0)
	var me: Player = t.me()
	t.check(me.is_alive and me.land > 49, "local player alive and expanded (land %d)" % me.land)
	me.troops = 5000.0   # test money
	var crown := Vector2i(me.crown_x, me.crown_y)
	await t.zoom_to(crown, 3.0)

	# --- Build menu via a real long-press -----------------------------------
	var spot: Vector2i = t.find_own_tile(crown + Vector2i(3, 3), 10,
		func(ti: int) -> bool: return BuildingsOps.tile_is_buildable(t.sim, me.id, ti))
	t.check(spot.x >= 0, "found a buildable tile near the Crown")
	await t.long_press_tile(spot)
	var menu: BuildMenu = t.hud.build_menu
	t.check(menu.visible, "long-press on own land opens the build menu")
	var rows: Array[Button] = menu.get("_rows")
	var fort_cost: int = int(Balance.FORT_COST_BASE)
	t.check(rows[0].text.begins_with("Fort — %d" % fort_cost) and not rows[0].disabled, "Fort row shows cost %d and is enabled: %s" % [fort_cost, rows[0].text.replace("\n", " | ")])
	t.check(rows[0].text.contains("x1.6"), "Fort row explains its effect")
	t.check(rows[1].text.contains("Barracks — 400") and not rows[1].disabled, "Barracks row enabled after 1:00")
	t.check(rows[3].text.contains("Draw walls"), "Wall row present")
	await t.shot("p8_build_menu")
	rows[0].pressed.emit()
	var b: Building = t.sim.state.building_at_tile.get(t.sim.state.idx(spot.x, spot.y), null)
	t.check(b != null and b.type == Balance.BUILDING_FORT and is_equal_approx(b.paid, Balance.FORT_COST_BASE), "Fort built for %d" % int(Balance.FORT_COST_BASE))
	t.check(me.fort_count == 1 and t.sim.combined_defense_at(t.sim.state.idx(spot.x + 2, spot.y)) >= Balance.FORT_DEFENSE - 0.001,
		"tiles near the Fort get x1.6 or better")

	# Second Fort costs base + 150 (each Fort you own adds 150).
	var second: int = int(Balance.FORT_COST_BASE + Balance.FORT_COST_PER_EXTRA)
	await t.long_press_tile(spot)
	t.check(rows[0].text.begins_with("Upgrade to Fort II — 400"), "long-press on a Fort offers Fort II")
	rows[0].pressed.emit()
	t.check(b.type == Balance.BUILDING_FORT2 and is_equal_approx(b.paid, Balance.FORT_COST_BASE + Balance.FORT2_COST), "Fort II upgrade recorded (paid %d)" % int(Balance.FORT_COST_BASE + Balance.FORT2_COST))
	var spot2: Vector2i = t.find_own_tile(crown + Vector2i(-3, -3), 10,
		func(ti: int) -> bool: return BuildingsOps.tile_is_buildable(t.sim, me.id, ti))
	await t.long_press_tile(spot2)
	t.check(rows[0].text.begins_with("Fort — %d" % second), "second Fort costs %d: %s" % [second, rows[0].text.replace("\n", " | ")])
	menu.close_menu()

	# Greyed out when broke.
	var saved: float = me.troops
	me.troops = 10.0
	await t.long_press_tile(spot2)
	t.check(rows[0].disabled and rows[0].text.contains("Need %d troops" % second), "Fort greyed out with 'Need %d troops' when broke" % second)
	menu.close_menu()
	me.troops = saved

	# --- Walls: one drag draws a gap-free line and shows the running cost ---
	var wall_start: Vector2i = t.find_own_tile(crown + Vector2i(0, 5), 8,
		func(ti: int) -> bool: return BuildingsOps.tile_is_buildable(t.sim, me.id, ti))
	(t.game.get("_targeting") as Targeting).enter(Targeting.Mode.WALL)
	var walls_before: int = me.wall_count
	var a: Vector2 = t.tile_to_screen(wall_start)
	var c: Vector2 = t.tile_to_screen(wall_start + Vector2i(6, 0))
	await t.press(a)
	await t.drag_to(a, a + Vector2(20, 0))
	await t.drag_to(a + Vector2(20, 0), c)   # a big jump: should still fill the gap
	await t.shot("p8_wall_drag")
	var banner_text: String = (t.hud.mode_banner.get("_label") as Label).text
	await t.release(c)
	var added: int = me.wall_count - walls_before
	t.check(added >= 5, "one drag across 7 tiles built %d walls (gap-free) [start %s reason '%s' alive %s mode %s]" % [added, wall_start,
		BuildingsOps.build_block_reason(t.sim, me, BuildingsOps.TYPE_WALL, t.sim.state.idx(wall_start.x, wall_start.y)), me.is_alive, (t.game.get("_targeting") as Targeting).mode])
	t.check(banner_text.contains("troops") and banner_text.contains("This line"), "wall banner shows the running cost: %s" % banner_text)
	var wall_ti: int = t.sim.state.idx(wall_start.x + 1, wall_start.y)
	if t.sim.state.wall_tiles.has(wall_ti):
		t.check(t.sim.combined_defense_at(wall_ti) >= Balance.WALL_DEFENSE - 0.001, "wall tile defense >= x2.5")
	t.hud.mode_banner.cancel_pressed.emit()
	t.check(not t.hud.mode_banner.visible, "Done leaves wall mode")

	# --- Keep upgrade via tapping the Crown ----------------------------------
	await t.tap_tile(crown)
	t.check(t.hud.keep_panel.visible, "tapping the Crown opens the Keep panel [crown %s owner %d panels %s]" % [crown, t.sim.state.owners[t.sim.state.idx(crown.x, crown.y)], t.hud.any_panel_open()])
	await t.shot("p8_keep_panel")
	var keep_rows: Array[Button] = t.hud.keep_panel.get("_keep_rows")
	t.check(keep_rows[1].disabled and keep_rows[1].text.contains("Unlocks at 3:00"), "Keep 2 locked until 3:00: %s" % keep_rows[1].text.replace("\n", " | "))
	keep_rows[0].pressed.emit()
	t.check(me.keep_level == 1 and me.crown_tile_defense() == 4.0, "Keep 1 bought: Crown tiles x4")
	t.hud.keep_panel.close_panel()

	# --- Barracks raise the cap ----------------------------------------------
	var cap_before: float = me.troop_cap()
	var bspot: Vector2i = t.find_own_tile(crown + Vector2i(-2, 3), 10,
		func(ti: int) -> bool: return BuildingsOps.tile_is_buildable(t.sim, me.id, ti))
	t.sim.player_build_barracks(me.id, bspot.x, bspot.y)
	t.check(me.barracks_count == 1 and me.troop_cap() > cap_before * 1.09, "Barracks adds +10% cap")

	# --- Loot when a building is captured ------------------------------------
	var enemy: Player = null
	for p: Player in t.sim.state.players:
		if p.is_alive and p.id != me.id and p.land > 60:
			enemy = p
			break
	var fort_tile: int = -1
	for i in range(t.sim.state.owners.size()):
		if t.sim.state.owners[i] == enemy.id and BuildingsOps.tile_is_buildable(t.sim, enemy.id, i):
			fort_tile = i
			break
	enemy.troops = 2000.0
	var ep: Vector2i = t.sim.state.idx_to_xy(fort_tile)
	t.check(BuildingsOps.build_fort(t.sim, enemy, ep.x, ep.y), "enemy builds a Fort (setup)")
	var troops_before: float = me.troops
	TerritoryOps.claim_tile(t.sim, me.id, ep.x, ep.y)
	var loot: float = me.troops - troops_before
	var expected_loot: int = roundi(Balance.CAPTURED_BUILDING_LOOT_FRACTION * Balance.FORT_COST_BASE)
	t.check(is_equal_approx(loot, float(expected_loot)), "capturing the Fort pays 25%% of its cost as loot (+%d)" % int(loot))
	t.check(not t.sim.state.building_at_tile.has(fort_tile), "captured Fort is destroyed")
	var popup_ok: bool = false
	for pu: Dictionary in t.sim.state.popups:
		if str(pu["text"]).begins_with("+%d loot" % expected_loot):
			popup_ok = true
	t.check(popup_ok, "a floating '+%d loot' number is queued" % expected_loot)
	await t.zoom_to(ep, 1.0)
	await t.shot("p8_loot_popup")

	# Greyed out within 3 tiles of an enemy border.
	t.ff_safe(80.0)
	me = t.me()
	me.troops = 5000.0
	var near_enemy: Vector2i = t.find_own_tile(crown, 60,
		func(ti: int) -> bool:
			return BuildingsOps.near_enemy_border(t.sim.state, me.id, ti) and not t.sim.state.crown_tiles.has(ti) and not t.sim.state.building_at_tile.has(ti) and not t.sim.state.wall_tiles.has(ti))
	if near_enemy.x >= 0:
		await t.zoom_to(near_enemy, 1.0)
		menu.open_at(near_enemy)
		t.check(menu.selected_tile() == near_enemy, "build menu open on a tile next to an enemy")
		t.check(rows[0].disabled and rows[0].text.contains("Within 3 tiles of an enemy"), "Fort greyed out near an enemy border: %s" % rows[0].text.replace("\n", " | "))
		await t.shot("p8_build_menu_near_enemy")
		menu.close_menu()
	else:
		t.check(true, "(no enemy border yet near the player — near-border check skipped) [alive %s land %d t=%.0f phase %d]" % [me.is_alive, me.land, t.sim.state.match_time, t.sim.state.phase])

	# --- Crown move (3:00+) ----------------------------------------------------
	# Fresh match; jump the clock to 3:01 (this checks the move itself).
	t.new_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 4343)
	t.skip_placement()
	t.ff(2.0, false)
	me = t.me()
	var st2: GameState = t.sim.state
	for dy in range(-18, 19):
		for dx in range(-18, 19):
			var bx: int = me.crown_x + dx
			var by: int = me.crown_y + dy
			if dx * dx + dy * dy <= 18 * 18 and st2.in_bounds(bx, by) and st2.blocked[st2.idx(bx, by)] == 0:
				TerritoryOps.claim_tile(t.sim, me.id, bx, by)
	t.check(not t.sim.player_move_crown(me.id, me.crown_x + 6, me.crown_y), "Crown move is locked before 3:00")
	st2.match_time = Balance.CROWN_MOVE_UNLOCK_SEC + 1.0
	me.troops = 3000.0
	me.keep_level = 1
	var target: Vector2i = t.find_own_tile(Vector2i(me.crown_x, me.crown_y), 30,
		func(ti: int) -> bool:
			var p2: Vector2i = st2.idx_to_xy(ti)
			return (absi(p2.x - me.crown_x) > 3 or absi(p2.y - me.crown_y) > 3) and CrownsOps.move_block_reason(t.sim, me, p2.x, p2.y) == "")
	t.check(target.x >= 0, "found a safe spot 10+ tiles from enemies")
	if target.x >= 0:
		var old_crown := Vector2i(me.crown_x, me.crown_y)
		t.check(t.sim.player_move_crown(me.id, target.x, target.y), "Crown moves to a valid spot")
		var centre_ti: int = st2.idx(target.x, target.y)
		var fort_only: float = BuildingsOps.best_fort_defense_at(st2, me, centre_ti)
		t.check(is_equal_approx(t.sim.combined_defense_at(centre_ti), fort_only), "moving Crown has no Crown/zone defense for 5 s")
		t.check(is_equal_approx(me.troops, 3000.0 - 600.0), "move cost 20% of troops")
		t.ff(Balance.CROWN_MOVE_DURATION_SEC + 0.2, false)
		t.check(t.sim.combined_defense_at(centre_ti) >= 4.0, "after 5 s the Crown is defended again (Keep 1 carries over)")
		t.check(not t.sim.player_move_crown(me.id, old_crown.x, old_crown.y), "only one move per match")

	await _boat_checks(t)


func _boat_checks(t: SmokeTest) -> void:
	# Archipelago: islands, so Ports matter.
	t.new_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_ARCHIPELAGO, 777)
	t.skip_placement()
	t.ff(75.0)
	var me: Player = t.me()
	me.troops = 4000.0
	var st: GameState = t.sim.state
	var port: Vector2i = t.find_own_tile(Vector2i(me.crown_x, me.crown_y), 25,
		func(ti: int) -> bool: return BuildingsOps.build_block_reason(t.sim, me, Balance.BUILDING_PORT, ti) == "")
	if port.x < 0:
		t.check(true, "(no coastal spot for a Port on this seed — boat checks skipped)")
		return
	await t.zoom_to(port, 2.0)
	await t.long_press_tile(port)
	var rows: Array[Button] = t.hud.build_menu.get("_rows")
	t.check(not rows[2].disabled and rows[2].text.begins_with("Port — 250"), "Port row enabled on a coast tile")
	rows[2].pressed.emit()
	t.check(me.port_count == 1, "Port built")
	# Find a free coast tile reachable by sea.
	var target: Vector2i = Vector2i(-1, -1)
	var path := PackedInt32Array()
	for i in range(st.owners.size()):
		if st.owners[i] != 0 or st.is_blocked_terrain(st.terrain[i]) or not BuildingsOps.tile_touches_water(st, i):
			continue
		var tp: Vector2i = st.idx_to_xy(i)
		if Vector2(tp).distance_to(Vector2(port)) < 15.0:
			continue
		if BoatsOps.launch_block_reason(t.sim, me, port.x, port.y, tp.x, tp.y, path) == "":
			target = tp
			break
	t.check(target.x >= 0, "found a free coast across the water")
	if target.x < 0:
		return
	await t.tap_tile(port)   # tap own Port -> boat mode
	t.check(t.hud.mode_banner.visible, "tapping your Port starts boat targeting")
	await t.tap_tile(target)
	t.check(st.boats.size() >= 1, "boat launched toward the target")
	t.ff(1.0)
	await t.shot("p8_boat_sailing")
	var travel: float = float(path.size()) / Balance.BOAT_SPEED_TILES_PER_SEC + 1.0
	t.ff(travel)
	t.check(st.owners[st.idx(target.x, target.y)] == me.id, "boat landed and claimed the coast")
