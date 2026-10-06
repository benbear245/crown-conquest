extends RefCounted

# Prompt 12 checks: layout at phone sizes (no overlaps, 56 px buttons),
# tap vs long-press vs drag vs pinch, minimap, Crown button, first-time hints,
# banner queue, left-handed layout.

const SIZES: Array[Vector2i] = [Vector2i(1920, 1080), Vector2i(2400, 1080)]


func run(t: SmokeTest) -> void:
	Settings.reset_hints()
	Settings.left_handed = false
	t.new_match(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 1212)
	t.skip_placement()
	t.ff(70.0, true)
	await _gestures(t)
	await _navigation(t)
	_hints_and_banners(t)
	await _layouts(t)
	Settings.left_handed = false
	Settings.save_settings()


func _gestures(t: SmokeTest) -> void:
	var me: Player = t.me()
	var crown := Vector2i(me.crown_x, me.crown_y)
	await t.zoom_to(crown, 2.5)
	var free_tile: Vector2i = _free_tile_next_to_me(t)
	var pos: Vector2 = t.tile_to_screen(free_tile)
	var touch: TouchInput = t.game.get("_touch")
	me.troops = 1000.0
	var before: float = me.expansion_troops
	await t.press(pos)
	await t.release(pos + Vector2(6, 4))   # a little finger jitter is still a tap
	t.check(me.expansion_troops > before, "a quick tap (with 7 px of jitter) expands")
	# Android also sends a fake mouse click for every touch: it must be ignored.
	before = me.expansion_troops
	var ev := InputEventMouseButton.new()
	ev.device = InputEvent.DEVICE_ID_EMULATION
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = pos
	ev.pressed = true
	t.get_viewport().push_input(ev, true)
	ev = ev.duplicate()
	ev.pressed = false
	t.get_viewport().push_input(ev, true)
	await t.get_tree().process_frame
	t.check(is_equal_approx(me.expansion_troops, before), "emulated mouse events from touch don't double a tap")
	# Long-press: no tap, the build menu opens; the ring shows while holding.
	var own: Vector2i = crown + Vector2i(2, 1)
	var own_pos: Vector2 = t.tile_to_screen(own)
	await t.press(own_pos)
	touch.process(0.2)
	t.check(touch.long_press_progress() > 0.3 and touch.long_press_progress() < 1.0, "a ring fills while you hold (%.2f)" % touch.long_press_progress())
	touch.process(0.4)
	await t.release(own_pos)
	t.check(t.hud.build_menu.visible, "holding 0.45 s opens the build menu (long-press)")
	t.hud.close_panels()
	# Drag: pans the camera, no tap.
	var cam: CameraRig = t.game.get_node("Camera2D")
	var cam_before: Vector2 = cam.position
	before = me.expansion_troops
	await t.press(pos)
	await t.drag_to(pos, pos + Vector2(60, 0))
	await t.drag_to(pos + Vector2(60, 0), pos + Vector2(140, 0))
	await t.release(pos + Vector2(140, 0))
	t.check(cam.position.x < cam_before.x - 1.0 and is_equal_approx(me.expansion_troops, before), "a drag pans the map and doesn't tap")
	# Two fingers: pinch zooms, never taps.
	var z: float = cam.zoom.x
	before = me.expansion_troops
	await _touch_event(t, 0, pos, true)
	await _touch_event(t, 1, pos + Vector2(100, 0), true)
	await _drag_event(t, 1, pos + Vector2(100, 0), pos + Vector2(220, 0))
	await _touch_event(t, 1, pos + Vector2(220, 0), false)
	await _touch_event(t, 0, pos, false)
	t.check(cam.zoom.x > z * 1.3 and is_equal_approx(me.expansion_troops, before), "two-finger pinch zooms (x%.2f) and doesn't tap" % (cam.zoom.x / z))


func _touch_event(t: SmokeTest, index: int, pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	t.get_viewport().push_input(ev, true)
	await t.get_tree().process_frame


func _drag_event(t: SmokeTest, index: int, from: Vector2, to: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = to
	ev.relative = to - from
	t.get_viewport().push_input(ev, true)
	await t.get_tree().process_frame


func _free_tile_next_to_me(t: SmokeTest) -> Vector2i:
	var st: GameState = t.sim.state
	var me: Player = t.me()
	var best := Vector2i(-1, -1)
	var best_d: float = INF
	for i: int in me.border.keys():
		var p: Vector2i = st.idx_to_xy(i)
		for off in TerritoryOps.NEIGHBOR_OFFSETS:
			var n: Vector2i = p + off
			if st.in_bounds(n.x, n.y) and st.owners[st.idx(n.x, n.y)] == 0 and st.blocked[st.idx(n.x, n.y)] == 0:
				var d: float = Vector2(n).distance_squared_to(Vector2(me.crown_x, me.crown_y))
				if d < best_d:
					best_d = d
					best = n
	return best


func _navigation(t: SmokeTest) -> void:
	var cam: CameraRig = t.game.get_node("Camera2D")
	var mm: Minimap = t.hud.minimap
	var view: Control = mm.get_child(0)
	var r: Rect2 = mm.call("_map_rect")
	var target_local: Vector2 = r.position + r.size * Vector2(0.9, 0.1)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = target_local
	view.gui_input.emit(ev)
	await t.get_tree().process_frame
	var expect: Vector2 = Vector2(t.sim.state.width, t.sim.state.height) * Vector2(0.9, 0.1)
	t.check(cam.position.distance_to(expect) < 40.0 or cam.position.x > t.sim.state.width * 0.6, "tapping the minimap jumps the camera there")
	ev = ev.duplicate()
	ev.pressed = false
	view.gui_input.emit(ev)
	# Crown button: one tap = tip, two quick taps = jump home.
	var crown_btn: Button = t.hud.top_bar.get("_crown_button")
	crown_btn.pressed.emit()
	t.check(t.hud.alerts.has_banner("hint_crown_button"), "one tap on the Crown button explains double-tap")
	crown_btn.pressed.emit()
	await t.get_tree().process_frame
	var me: Player = t.me()
	t.check(cam.position.distance_to(Vector2(me.crown_x, me.crown_y)) < 30.0, "double-tapping the Crown button jumps home")


func _hints_and_banners(t: SmokeTest) -> void:
	t.check(Settings.hints_seen.has("hint_expand"), "the expand tip was shown the first time you expanded")
	t.hud.alerts.clear_all()
	t.hud.hint("expand")
	t.check(not t.hud.alerts.has_banner("hint_expand"), "...and not again the second time")
	for i in range(5):
		t.hud.alerts.push("Banner %d" % i, "event", 5.0)
	t.check((t.hud.alerts.get("_banners") as Array).size() == AlertQueue.MAX_BANNERS, "banners queue up to %d at a time (oldest drop off)" % AlertQueue.MAX_BANNERS)


# Fill every panel, then check nothing overlaps at phone sizes, both hands.
func _layouts(t: SmokeTest) -> void:
	_fill_panels(t)
	var window: Window = t.get_window()
	var headless: bool = DisplayServer.get_name() == "headless"
	for size: Vector2i in SIZES:
		if not headless:
			window.size = size
		for lh: bool in [false, true]:
			Settings.left_handed = lh
			t.hud.apply_layout()
			for _f in range(3):
				await t.get_tree().process_frame
			var vp: Vector2 = t.get_viewport().get_visible_rect().size
			var label: String = "%dx%d %s" % [int(vp.x), int(vp.y), "left-handed" if lh else "right-handed"]
			_check_no_overlaps(t, label, vp)
			_check_button_sizes(t, label)
			_check_mirrored(t, label, lh)
			await t.shot("p12_layout_%dx%d_%s" % [int(vp.x), int(vp.y), "LH" if lh else "RH"])
		if headless:
			break


func _fill_panels(t: SmokeTest) -> void:
	var st: GameState = t.sim.state
	var me: Player = t.me()
	for p: Player in st.players:
		if p.id != me.id and p.is_alive and not TrucesOps.has_truce(me, p.id, st.match_time):
			TrucesOps.accept(t.sim, me.id, p.id)
			break
	var other: Player = st.players[3]
	TrucesOps.offer(t.sim, other.id, me.id)
	for i in range(3):
		var atk := Attack.new()
		atk.attacker_id = me.id
		atk.defender_id = st.players[4].id
		atk.troops_remaining = 300.0
		atk.front = {0: true}
		atk.advance_timer = 99.0
		st.attacks.append(atk)
	t.hud.alerts.clear_all()
	for i in range(3):
		t.hud.alerts.push("A long announcement banner number %d to fill the queue" % i, "event", 30.0)
	t.hud.update_from_state()


func _rect(c: Control) -> Rect2:
	return c.get_global_rect()


func _check_no_overlaps(t: SmokeTest, label: String, vp: Vector2) -> void:
	var parts: Dictionary = {
		"top bar": t.hud.top_bar, "left column": t.hud.get("_left_column"), "leaderboard": t.hud.leaderboard,
		"banners": t.hud.get("_alert_column"), "bottom bar": t.hud.get("_bottom_bar"),
		"attack list": t.hud.attack_list, "minimap": t.hud.minimap,
	}
	var names: Array = parts.keys()
	var problems: Array[String] = []
	for i in range(names.size()):
		var a: Control = parts[names[i]]
		if not a.visible:
			continue
		var ra: Rect2 = _rect(a)
		if ra.position.x < -0.5 or ra.position.y < -0.5 or ra.end.x > vp.x + 0.5 or ra.end.y > vp.y + 0.5:
			problems.append("%s off screen %s" % [names[i], ra])
		for j in range(i + 1, names.size()):
			var b: Control = parts[names[j]]
			if b.visible and ra.grow(-1.0).intersects(_rect(b).grow(-1.0)):
				problems.append("%s overlaps %s" % [names[i], names[j]])
	t.check(problems.is_empty(), "%s: nothing overlaps or leaves the screen %s" % [label, problems])


func _check_button_sizes(t: SmokeTest, label: String) -> void:
	var small: Array[String] = []
	for b: Node in t.hud.find_children("*", "Button", true, false):
		var btn: Button = b
		if btn.is_visible_in_tree() and btn.size.y < Balance.MIN_BUTTON_PX - 0.5:
			small.append("%s (%d px)" % [btn.text.left(16), int(btn.size.y)])
	t.check(small.is_empty(), "%s: every visible button is at least %d px tall %s" % [label, Balance.MIN_BUTTON_PX, small])


func _check_mirrored(t: SmokeTest, label: String, lh: bool) -> void:
	var slider_x: float = _rect(t.hud.send_slider).get_center().x
	var abil_x: float = _rect(t.hud.ability_bar).get_center().x
	var mm_x: float = _rect(t.hud.minimap).get_center().x
	var vp_w: float = t.get_viewport().get_visible_rect().size.x
	var ok: bool = (slider_x > abil_x) == lh and (mm_x < vp_w * 0.5) == lh
	t.check(ok, "%s: slider, abilities and minimap are on the %s side" % [label, "mirrored" if lh else "default"])
