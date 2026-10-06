extends RefCounted

# Prompt 13 checks: capture flashes, pulsing fronts, plunder/loot numbers,
# Crown-fall shake + slow-mo + fanfare, vibration, music, settings, and that
# none of it costs much frame time.


func run(t: SmokeTest) -> void:
	var feel: GameFeel = t.game.get("_feel")
	Settings.sound = true
	Settings.music = true
	Settings.vibration = true
	Settings.colorblind = false
	t.new_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 1313)
	t.skip_placement()
	t.ff_safe(60.0, true)
	_flashes_and_fronts(t)
	_crown_fall(t, feel)
	_abilities_and_alarm(t, feel)
	_settings(t, feel)
	await _colorblind(t)
	_music(t, feel)
	_frame_cost(t, feel)
	Settings.sound = true
	Settings.music = true
	Settings.vibration = true
	Settings.colorblind = false
	Settings.save_settings()


# Ticks the sim and feeds its events to GameFeel, like game.gd does.
func _tick(t: SmokeTest, feel: GameFeel, ticks: int) -> Array:
	var seen: Array = []
	for i in range(ticks):
		t.sim.advance_tick()
		seen.append_array(t.sim.state.events)
		feel.consume(t.sim.state.events)
		t.sim.state.events.clear()
	return seen


func _flashes_and_fronts(t: SmokeTest) -> void:
	var st: GameState = t.sim.state
	var me: Player = t.me()
	var target: Player = null
	for p: Player in st.players:
		if p.id != me.id and p.is_alive and _touches(st, me, p.id):
			target = p
			break
	if target == null:
		t.check(false, "found a neighbour to attack")
		return
	var tile: Vector2i = _enemy_border_tile(st, me, target.id)
	me.troops = me.troop_cap()
	t.sim.player_attack(me.id, tile.x, tile.y, 0.5)
	var feel: GameFeel = t.game.get("_feel")
	var counts_before: int = int(Audio.play_counts.get("sfx_attack_drum", 0))
	var events: Array = []
	var flashed: bool = false
	for i in range(30):
		events.append_array(_tick(t, feel, 1))
		if not st.flash_tiles.is_empty():
			flashed = true
	t.check(flashed, "captured tiles flash")
	t.check(events.any(func(e: Dictionary) -> bool: return e.type == "attack_ring"), "attack rings send an event")
	t.check(int(Audio.play_counts.get("sfx_attack_drum", 0)) > counts_before, "drums play during my attack")
	var overlay: WorldOverlay = t.game.get("_overlay")
	overlay.call("_rebuild_fronts")
	var fronts: Array = overlay.get("_fronts")
	var mine: bool = fronts.any(func(f: Array) -> bool: return f[2])
	t.check(mine and fronts.size() == st.attacks.size() - st.attacks.filter(func(a: Attack) -> bool: return a.front.is_empty()).size(), "every active attack front is drawn (mine highlighted)")
	# Fronts are rebuilt once per tick, not every frame.
	var tick_before: int = overlay.get("_fronts_tick")
	overlay.queue_redraw()
	t.check(tick_before == st.tick_count, "front cache follows the sim tick")


func _crown_fall(t: SmokeTest, feel: GameFeel) -> void:
	var st: GameState = t.sim.state
	var me: Player = t.me()
	var victim: Player = null
	for p: Player in st.players:
		if p.id != me.id and p.is_alive:
			victim = p
	victim.troops = 2000.0
	var vib_before: int = Settings.vibrations_sent
	var big_before: int = int(Audio.play_counts.get("sfx_crown_fall_big", 0))
	CombatOps.eliminate_player(t.sim, victim.id, me.id)
	var popup: bool = st.popups.any(func(p: Dictionary) -> bool: return str(p.text).contains("plunder") and str(p.text).begins_with("+"))
	t.check(popup, "a floating '+N plunder' number appears when I take a Crown")
	t.check(st.popups.any(func(p: Dictionary) -> bool: return str(p.text) == "+%s plunder" % GameState.format_int(int(2000.0 * Balance.CROWN_PLUNDER_FRACTION))), "plunder number uses thousands separators (e.g. +1,240)")
	feel.consume(st.events)
	st.events.clear()
	t.check(feel.time_scale() < 0.5, "taking a Crown starts a strong slow-motion moment (x%.2f)" % feel.time_scale())
	var cam: CameraRig = t.game.get("_camera")
	t.check(float(cam.get("_shake_left")) > 0.5 and float(cam.get("_shake_strength")) >= 12.0, "taking a Crown shakes the screen hard")
	t.check(int(Audio.play_counts.get("sfx_crown_fall_big", 0)) > big_before, "big fanfare when I take a Crown")
	t.check(Settings.vibrations_sent > vib_before, "phone vibrates when a Crown falls")
	# Slow-mo wears off on its own (real time, not sim time).
	feel._process(1.0)
	t.check(feel.time_scale() == 1.0, "slow motion ends after a moment")
	# Someone else's Crown: smaller effect.
	var a: Player = null
	var b: Player = null
	for p: Player in st.players:
		if p.id != me.id and p.is_alive:
			if a == null:
				a = p
			elif b == null:
				b = p
	if a != null and b != null:
		cam.set("_shake_left", 0.0)
		cam.set("_shake_strength", 0.0)
		var small_before: int = int(Audio.play_counts.get("sfx_crown_fall", 0))
		Audio.set("_last_played", {})
		CombatOps.eliminate_player(t.sim, a.id, b.id)
		feel.consume(st.events)
		st.events.clear()
		t.check(feel.time_scale() > 0.4 and feel.time_scale() < 1.0, "another player's Crown: gentler slow motion (x%.2f)" % feel.time_scale())
		t.check(float(cam.get("_shake_strength")) < 12.0 and float(cam.get("_shake_strength")) > 0.0, "another player's Crown: smaller shake")
		t.check(int(Audio.play_counts.get("sfx_crown_fall", 0)) > small_before, "fanfare when any Crown falls")
		feel._process(1.0)
	# Loot number + coins when I capture a building.
	var coins_before: int = int(Audio.play_counts.get("sfx_loot", 0))
	BuildingsOps._pay_loot(t.sim, me.id, 75.0, st.idx(me.crown_x, me.crown_y))
	feel.consume(st.events)
	st.events.clear()
	t.check(st.popups.any(func(p: Dictionary) -> bool: return str(p.text) == "+75 loot"), "a floating '+75 loot' number appears")
	t.check(int(Audio.play_counts.get("sfx_loot", 0)) > coins_before, "coins sound for loot")


func _abilities_and_alarm(t: SmokeTest, feel: GameFeel) -> void:
	var st: GameState = t.sim.state
	var me: Player = t.me()
	# Crown alarm: horn + vibration once when it starts.
	var horn_before: int = int(Audio.play_counts.get("sfx_crown_alarm_horn", 0))
	var vib_before: int = Settings.vibrations_sent
	me.crown_alert_until = st.match_time + 5.0
	feel._process(0.016)
	feel._process(0.016)
	t.check(int(Audio.play_counts.get("sfx_crown_alarm_horn", 0)) == horn_before + 1, "horn plays once when my Crown is attacked")
	t.check(Settings.vibrations_sent == vib_before + 1, "phone vibrates once when my Crown is attacked")
	me.crown_alert_until = 0.0
	feel._process(0.016)
	# Ability ready: chime + buzz when a cooldown runs out.
	st.match_time = maxf(st.match_time, AbilitiesOps.unlock_sec(AbilitiesOps.ID_SWIFT_MARCH) + 1.0)
	me.swift_march_cd_until = st.match_time + 0.05
	feel._process(0.016)
	var chime_before: int = int(Audio.play_counts.get("sfx_ability_ready", 0))
	vib_before = Settings.vibrations_sent
	st.match_time += 0.1
	feel._process(0.016)
	t.check(int(Audio.play_counts.get("sfx_ability_ready", 0)) == chime_before + 1, "chime when an ability is ready")
	t.check(Settings.vibrations_sent == vib_before + 1, "phone vibrates when an ability is ready")


func _settings(t: SmokeTest, feel: GameFeel) -> void:
	var st: GameState = t.sim.state
	var me: Player = t.me()
	Settings.set_value("sound", false)
	Settings.set_value("vibration", false)
	var total_before: int = _total_plays()
	var vib_before: int = Settings.vibrations_sent
	me.crown_alert_until = st.match_time + 5.0
	feel._process(0.016)
	Audio.play("sfx_build")
	t.check(_total_plays() == total_before, "Sound off: no sound effects")
	t.check(Settings.vibrations_sent == vib_before, "Vibration off: no vibration")
	me.crown_alert_until = 0.0
	feel._process(0.016)
	Settings.set_value("sound", true)
	Settings.set_value("vibration", true)
	# The in-match menu has a toggle for each setting.
	var list: SettingsList = t.hud.menu_panel.settings_list
	var ok: bool = true
	for key: String in ["left_handed", "sound", "music", "vibration", "colorblind"]:
		ok = ok and list.button_for(key) != null
	t.check(ok, "menu has Layout, Sound, Music, Vibration and Colour-blind toggles")
	list.button_for("music").pressed.emit()
	t.check(not Settings.music and list.button_for("music").text.ends_with("Off"), "tapping Music turns music off and the button says so")
	list.button_for("music").pressed.emit()
	t.check(Settings.music, "tapping Music again turns it back on")


func _colorblind(t: SmokeTest) -> void:
	var st: GameState = t.sim.state
	var me: Player = t.me()
	var map: Map = t.game.get_node("Map")
	st.flash_tiles.clear()
	map.render()
	var ti: int = -1
	for i in range(st.owners.size()):
		if st.owners[i] == me.id and not st.crown_tiles.has(i) and not st.flash_tiles.has(i):
			ti = i
			break
	var xy: Vector2i = st.idx_to_xy(ti)
	var before: Color = (map.get("_image") as Image).get_pixelv(xy)
	var normal: Color = Palette.player(me.id)
	Settings.set_value("colorblind", true)
	await t.get_tree().process_frame
	var after: Color = (map.get("_image") as Image).get_pixelv(xy)
	t.check(Palette.player(me.id) != normal, "colour-blind palette swaps player colours")
	t.check(not before.is_equal_approx(after) and map.uses_colorblind(), "map repaints when the colour-blind palette is turned on")
	var distinct: bool = true
	var cols: PackedColorArray = Balance.PLAYER_COLORS_COLORBLIND
	for i in range(1, cols.size()):
		for j in range(i + 1, cols.size()):
			var c1: Color = cols[i]
			var c2: Color = cols[j]
			var d: float = absf(c1.r - c2.r) + absf(c1.g - c2.g) + absf(c1.b - c2.b) + absf(c1.v - c2.v)
			distinct = distinct and d > 0.25
	t.check(distinct, "colour-blind colours are all clearly different from each other")
	for k in range(3):
		await t.get_tree().process_frame
	await t.shot("feel_colorblind")
	Settings.set_value("colorblind", false)
	await t.get_tree().process_frame
	t.check((map.get("_image") as Image).get_pixelv(xy).is_equal_approx(before), "turning it off restores the normal colours")


func _music(t: SmokeTest, feel: GameFeel) -> void:
	feel.setup(t.sim, t.game.get("_camera"))
	t.check(Audio.current_music() == "music_calm_loop", "calm music during the match")
	feel.consume([{"type": "final_siege"}])
	t.check(Audio.current_music() == "music_siege_loop", "music switches to the intense track in the Final Siege")
	feel.consume([{"type": "match_end", "winner_id": t.sim.local_player_id}])
	t.check(Audio.current_music() == "" and int(Audio.play_counts.get("sfx_victory", 0)) > 0, "music stops and a victory sting plays at the end")
	feel.setup(t.sim, t.game.get("_camera"))


# Average cost per frame of the game-feel work at a busy moment.
func _frame_cost(t: SmokeTest, feel: GameFeel) -> void:
	t.new_match(Balance.MAP_SIZE_LARGE, Balance.MAP_TYPE_CONTINENT, 1314)
	t.skip_placement()
	t.ff(150.0, true)
	var overlay: WorldOverlay = t.game.get("_overlay")
	var frames: int = 120
	var t0: int = Time.get_ticks_usec()
	for i in range(frames):
		t.sim.advance_tick()
		feel.consume(t.sim.state.events)
		t.sim.state.events.clear()
		feel._process(0.016)
		overlay.call("_rebuild_fronts")
	var feel_us: float = float(Time.get_ticks_usec() - t0) / frames
	var t1: int = Time.get_ticks_usec()
	for i in range(frames):
		t.sim.advance_tick()
		t.sim.state.events.clear()
	var sim_us: float = float(Time.get_ticks_usec() - t1) / frames
	var extra_ms: float = maxf(0.0, feel_us - sim_us) / 1000.0
	print("[smoke] feel cost: %.2f ms/frame on top of a %.2f ms tick (%d attacks)" % [extra_ms, sim_us / 1000.0, t.sim.state.attacks.size()])
	t.check(extra_ms < 2.0, "game feel adds under 2 ms per frame at a busy moment (%.2f ms)" % extra_ms)


func _total_plays() -> int:
	var n: int = 0
	for k: String in Audio.play_counts.keys():
		n += int(Audio.play_counts[k])
	return n


func _touches(st: GameState, me: Player, other_id: int) -> bool:
	return _enemy_border_tile(st, me, other_id).x >= 0


func _enemy_border_tile(st: GameState, me: Player, other_id: int) -> Vector2i:
	for ti: int in me.border.keys():
		var xy: Vector2i = st.idx_to_xy(ti)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = xy + d
			if n.x >= 0 and n.y >= 0 and n.x < st.width and n.y < st.height and st.owners[st.idx(n.x, n.y)] == other_id:
				return n
	return Vector2i(-1, -1)
