extends RefCounted

# Prompt 18 checks: Android settings and export preset, the screen staying on
# during matches, attack rings spread over ticks, and tick time at a busy
# moment of a Large 12-player match.


func run(t: SmokeTest) -> void:
	_settings(t)
	_preset(t)
	_rings(t)
	_ruins_repaint(t)
	_tick_time(t)


func _settings(t: SmokeTest) -> void:
	t.check(ProjectSettings.get_setting("application/config/name") == "Crown Conquest", "app name is 'Crown Conquest'")
	t.check(int(ProjectSettings.get_setting("display/window/handheld/orientation")) == 4, "landscape (turns with the phone, never portrait)")
	t.check(not bool(ProjectSettings.get_setting("display/window/energy_saving/keep_screen_on")), "the screen may sleep in the menus...")
	var src: String = FileAccess.get_file_as_string("res://scripts/game.gd")
	t.check(src.contains("DisplayServer.screen_set_keep_on(true)"), "...and the game scene keeps it on during a match")
	var icon: String = ProjectSettings.get_setting("application/config/icon")
	t.check(ResourceLoader.exists(icon), "placeholder app icon exists (%s)" % icon)


func _preset(t: SmokeTest) -> void:
	var cfg := ConfigFile.new()
	var ok: bool = cfg.load("res://export_presets.cfg") == OK
	t.check(ok and cfg.get_value("preset.0", "platform", "") == "Android", "export_presets.cfg has an Android preset")
	if not ok:
		return
	t.check(cfg.get_value("preset.0.options", "package/name", "") == "Crown Conquest", "Android app label is 'Crown Conquest'")
	t.check(bool(cfg.get_value("preset.0.options", "permissions/vibrate", false)), "vibration permission is on")
	t.check(bool(cfg.get_value("preset.0.options", "architectures/arm64-v8a", false)), "builds for 64-bit ARM phones")
	var icons_ok: bool = true
	for key: String in ["launcher_icons/main_192x192", "launcher_icons/adaptive_foreground_432x432", "launcher_icons/adaptive_background_432x432"]:
		var path: String = cfg.get_value("preset.0.options", key, "")
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		var want: int = 192 if key.ends_with("192x192") else 432
		icons_ok = icons_ok and img != null and img.get_width() == want and img.get_height() == want
	t.check(icons_ok, "launcher icons exist at 192 and 432 px")


# A huge front is eaten a slice per tick, never all in one tick.
func _rings(t: SmokeTest) -> void:
	var sim := Simulation.new()
	sim.headless = true
	sim.start_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 77)
	while sim.state.phase == Balance.PHASE_PLACEMENT:
		sim.advance_tick()
	var st: GameState = sim.state
	# Give player 2 a long strip next to player 1 so the front is wide.
	var me: Player = st.get_player(1)
	var front: Dictionary = {}
	for ti in range(st.tile_count()):
		if st.blocked[ti] == 0 and st.owners[ti] == 0 and front.size() < 900:
			var xy: Vector2i = st.idx_to_xy(ti)
			TerritoryOps.claim_tile(sim, 2, xy.x, xy.y)
			front[ti] = true
	var atk := Attack.new()
	atk.attacker_id = me.id
	atk.defender_id = 2
	atk.troops_remaining = 1.0e9
	atk.front = front
	atk.advance_timer = 0.0
	st.attacks.append(atk)
	var budget: int = CombatOps.attack_tile_budget(st)
	var max_step: int = 0
	var ticks: int = 0
	CombatOps.tick_attacks(sim)
	max_step = atk.ring_pos
	while atk.ring_active and ticks < 20:
		var before: int = atk.ring_pos
		CombatOps.tick_attacks(sim)
		max_step = maxi(max_step, atk.ring_pos - before)
		ticks += 1
	t.check(max_step <= budget and ticks >= 2, "a %d-tile ring is eaten at most %d tiles per tick (took %d ticks)" % [front.size(), budget, ticks + 1])


# When a Crown falls the map repaints over a few frames (no hitch) and ends up
# showing the Ruins.
func _ruins_repaint(t: SmokeTest) -> void:
	t.new_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 909)
	t.skip_placement()
	t.ff(70.0, true)
	var st: GameState = t.sim.state
	var map: Map = t.game.get_node("Map")
	map.render()
	var victim: Player = st.get_player(3)
	var tile: int = st.owners.find(victim.id)
	CombatOps.eliminate_player(t.sim, victim.id, 1)
	t.check(st.repaint_all and st.owners[tile] == GameState.RUINS_OWNER_ID, "a fallen Crown's land turns to Ruins and asks for a repaint")
	var frames: int = 0
	map.render()
	while map.get("_sweep_row") != -1 and frames < 200:
		map.render()
		frames += 1
	var img: Image = map.get("_image")
	var xy: Vector2i = st.idx_to_xy(tile)
	var got: Color = img.get_pixelv(xy)
	var want: Color = map.call("_color_for_tile", tile)
	var close: bool = absf(got.r - want.r) < 0.006 and absf(got.g - want.g) < 0.006 and absf(got.b - want.b) < 0.006   # 8-bit image
	t.check(frames >= 3 and close, "the map repaints the Ruins over %d frames, %d pixels at a time" % [frames + 1, Map.MAX_PIXELS_PER_FRAME])


# The busiest stretch of a Large 12-player match, run the way the game runs.
func _tick_time(t: SmokeTest) -> void:
	var sim := Simulation.new()
	sim.headless = false
	sim.start_match(Balance.MAP_SIZE_LARGE, Balance.MAP_TYPE_CONTINENT, 4)
	var mix: Array[int] = [0, 0, 0, 1, 1, 1, 2, 1]
	for i in range(sim.state.players.size()):
		var p: Player = sim.state.players[i]
		p.is_bot = true
		p.difficulty = mix[i % mix.size()]
		p.personality = sim.state.rng.randi() % 4
	var times := PackedInt32Array()
	while sim.state.phase != Balance.PHASE_ENDED and sim.state.match_time < 360.0:
		var t0: int = Time.get_ticks_usec()
		sim.advance_tick()
		var dt: int = Time.get_ticks_usec() - t0
		sim.state.events.clear()
		sim.state.dirty_tiles.clear()
		if sim.state.match_time >= 120.0:
			times.append(dt)
	times.sort()
	var n: int = times.size()
	if n == 0:
		t.check(false, "Large match reached the busy stretch")
		return
	var p99: float = times[int(n * 0.99)] / 1000.0
	var worst: float = times[n - 1] / 1000.0
	print("[smoke] Large 12-player match, 2:00-6:00: median %.2f ms, p99 %.2f ms, worst %.2f ms per tick" % [times[n >> 1] / 1000.0, p99, worst])
	t.check(p99 < 10.0, "ticks stay well under 10 ms on a busy Large map (p99 %.2f ms, worst %.2f ms)" % [p99, worst])
