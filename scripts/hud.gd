class_name HUD
extends CanvasLayer

# Thumb-friendly HUD built in code so there is one file to look at.
# Only reads from GameState; never mutates it.

const QUICK_BUTTONS: Array[float] = [0.25, 0.50, 0.75, 1.00]
const MARGIN: int = 16
const BAR_HEIGHT: int = 32
const BAR_WIDTH: int = 420
const COLOR_SWEET: Color = Color(0.40, 0.95, 0.50)
const COLOR_NORMAL: Color = Color(0.95, 0.85, 0.35)
const COLOR_OVER: Color = Color(0.95, 0.40, 0.35)
const COLOR_TEXT: Color = Color(0.95, 0.95, 0.95)
const LEADERBOARD_ROWS: int = 5
const LEADERBOARD_WIDTH: int = 260

signal new_map_pressed
signal play_again_pressed
signal jump_to_crown_pressed
signal build_fort_requested(x: int, y: int)
signal upgrade_fort_requested(x: int, y: int)
signal build_barracks_requested(x: int, y: int)
signal build_port_requested(x: int, y: int)
signal buy_keep_requested(level: int)
signal wall_mode_toggled(enabled: bool)
signal boat_launch_requested(port_x: int, port_y: int)
signal ability_pressed(ability_id: int)

var _sim: Simulation
var _state: GameState
var _send_fraction: float = 0.50
var _overlay_dismissed_for_phase_id: int = -1

var _bar_bg: ColorRect
var _bar_fill: ColorRect
var _troop_label: Label
var _per_sec_label: Label
var _land_label: Label
var _timer_label: Label
var _slider: HSlider
var _slider_label: Label
var _new_map_button: Button
var _placement_msg: Label
var _leaderboard: VBoxContainer
var _leader_rows: Array = []
var _attack_rows: Array = []
var _alert_button: Button
var _announcement_label: Label
var _end_overlay: ColorRect
var _end_title: Label
var _end_subtitle: Label
var _end_stats: Label
var _end_play_again: Button
var _end_watch: Button

# Context build menu (long-press target tile).
var _build_menu: PanelContainer
var _build_menu_vbox: VBoxContainer
var _build_menu_tile_label: Label
var _build_menu_tile: Vector2i = Vector2i(-1, -1)
var _build_menu_buttons: Array = []
var _wall_mode: bool = false
var _wall_mode_label: Label

# Keep upgrade panel (tap Crown).
var _keep_panel: PanelContainer
var _keep_vbox: VBoxContainer
var _keep_buttons: Array = []

# Status row above the slider (building counts + wall/boat mode banner).
var _status_label: Label

# Ability bar (4 buttons: Swift March / Crown Shield / Rally / Bombard).
var _ability_bar: PanelContainer
var _ability_buttons: Array = []
var _bombard_target_mode: bool = false
var _bombard_hint_label: Label


func _ready() -> void:
	layer = 10
	_build_top()
	_build_leaderboard()
	_build_attacks()
	_build_placement_message()
	_build_alerts()
	_build_bottom()
	_build_end_overlay()
	_build_build_menu()
	_build_keep_panel()
	_build_ability_bar()


func setup(sim: Simulation) -> void:
	_sim = sim
	_state = sim.state
	update_from_state()


func send_fraction() -> float:
	return _send_fraction


# --- Build (one-time) --------------------------------------------------------

func _build_top() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = MARGIN
	panel.offset_right = -MARGIN
	panel.offset_top = MARGIN
	panel.offset_bottom = MARGIN + BAR_HEIGHT + 16
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var bar_wrap := Control.new()
	bar_wrap.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar_wrap)

	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.08, 0.08, 0.10)
	_bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color = COLOR_NORMAL
	_bar_fill.anchor_left = 0.0
	_bar_fill.anchor_right = 0.0
	_bar_fill.anchor_top = 0.0
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_bar_fill)

	_troop_label = Label.new()
	_troop_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_troop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_troop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_label_style(_troop_label)
	_troop_label.text = "0 / 0"
	_troop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_troop_label)

	_per_sec_label = _make_stat_label("+0.0/s", 110)
	row.add_child(_per_sec_label)
	_land_label = _make_stat_label("0.0%", 90)
	row.add_child(_land_label)
	_timer_label = _make_stat_label("0:00", 160)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_timer_label)

	# Spacer so the New map button hugs the right.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_new_map_button = Button.new()
	_new_map_button.text = "New map"
	_new_map_button.custom_minimum_size = Vector2(110, BAR_HEIGHT)
	_new_map_button.pressed.connect(func() -> void: new_map_pressed.emit())
	row.add_child(_new_map_button)


func _build_leaderboard() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -(LEADERBOARD_WIDTH + MARGIN)
	panel.offset_right = -MARGIN
	panel.offset_top = MARGIN + BAR_HEIGHT + 24
	panel.offset_bottom = panel.offset_top + 24 + LEADERBOARD_ROWS * 26
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	_leaderboard = VBoxContainer.new()
	_leaderboard.add_theme_constant_override("separation", 4)
	_leaderboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_leaderboard)

	var header := Label.new()
	header.text = "Leaderboard"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_label_style(header)
	_leaderboard.add_child(header)

	for i in range(LEADERBOARD_ROWS):
		var row_box := HBoxContainer.new()
		row_box.add_theme_constant_override("separation", 8)
		row_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_leaderboard.add_child(row_box)

		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.color = Color(0.3, 0.3, 0.3)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_box.add_child(swatch)

		var name_label := Label.new()
		name_label.custom_minimum_size = Vector2(140, 20)
		name_label.text = ""
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_label_style(name_label)
		row_box.add_child(name_label)

		var land_label := Label.new()
		land_label.custom_minimum_size = Vector2(60, 20)
		land_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		land_label.text = ""
		land_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_label_style(land_label)
		row_box.add_child(land_label)

		_leader_rows.append({"row": row_box, "swatch": swatch, "name": name_label, "land": land_label})


func _build_attacks() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = MARGIN
	panel.offset_right = MARGIN + 280
	panel.offset_bottom = -(Balance.MIN_BUTTON_PX + 48)
	panel.offset_top = panel.offset_bottom - (Balance.MAX_SIMULTANEOUS_ATTACKS * 38 + 20)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "Attacks (tap to retreat 75%)"
	_apply_label_style(header)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(header)

	for i in range(Balance.MAX_SIMULTANEOUS_ATTACKS):
		var btn := Button.new()
		btn.text = ""
		btn.custom_minimum_size = Vector2(260, 34)
		btn.visible = false
		var local_i: int = i
		btn.pressed.connect(func() -> void: _on_attack_pressed(local_i))
		vbox.add_child(btn)
		_attack_rows.append(btn)


func _build_alerts() -> void:
	# Crown-under-attack button, anchored top-centre below the top panel.
	_alert_button = Button.new()
	_alert_button.text = "⚠ Crown under attack — tap to jump"
	_alert_button.anchor_left = 0.5
	_alert_button.anchor_right = 0.5
	_alert_button.anchor_top = 0.0
	_alert_button.anchor_bottom = 0.0
	_alert_button.offset_left = -220
	_alert_button.offset_right = 220
	_alert_button.offset_top = MARGIN + BAR_HEIGHT + 32
	_alert_button.offset_bottom = _alert_button.offset_top + 44
	_alert_button.visible = false
	_alert_button.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
	_alert_button.pressed.connect(func() -> void: jump_to_crown_pressed.emit())
	add_child(_alert_button)

	_announcement_label = Label.new()
	_announcement_label.anchor_left = 0.5
	_announcement_label.anchor_right = 0.5
	_announcement_label.anchor_top = 0.0
	_announcement_label.anchor_bottom = 0.0
	_announcement_label.offset_left = -340
	_announcement_label.offset_right = 340
	_announcement_label.offset_top = MARGIN + BAR_HEIGHT + 86
	_announcement_label.offset_bottom = _announcement_label.offset_top + 36
	_announcement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announcement_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_label_style(_announcement_label)
	_announcement_label.add_theme_font_size_override("font_size", 22)
	_announcement_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_announcement_label.visible = false
	add_child(_announcement_label)


func _build_end_overlay() -> void:
	_end_overlay = ColorRect.new()
	_end_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_overlay.color = Color(0, 0, 0, 0.55)
	_end_overlay.visible = false
	add_child(_end_overlay)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -260
	panel.offset_right = 260
	panel.offset_top = -170
	panel.offset_bottom = 170
	_end_overlay.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	_end_title = Label.new()
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(_end_title)
	_end_title.add_theme_font_size_override("font_size", 42)
	_end_title.text = ""
	vbox.add_child(_end_title)

	_end_subtitle = Label.new()
	_end_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(_end_subtitle)
	_end_subtitle.add_theme_font_size_override("font_size", 20)
	_end_subtitle.text = ""
	vbox.add_child(_end_subtitle)

	_end_stats = Label.new()
	_end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_stats.add_theme_font_size_override("font_size", 18)
	_apply_label_style(_end_stats)
	_end_stats.text = ""
	vbox.add_child(_end_stats)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	_end_play_again = Button.new()
	_end_play_again.text = "Play again"
	_end_play_again.custom_minimum_size = Vector2(140, Balance.MIN_BUTTON_PX)
	_end_play_again.pressed.connect(func() -> void: play_again_pressed.emit())
	btn_row.add_child(_end_play_again)

	_end_watch = Button.new()
	_end_watch.text = "Watch"
	_end_watch.custom_minimum_size = Vector2(140, Balance.MIN_BUTTON_PX)
	_end_watch.pressed.connect(_on_watch_pressed)
	btn_row.add_child(_end_watch)


func _on_watch_pressed() -> void:
	_overlay_dismissed_for_phase_id = _current_overlay_id()


func _current_overlay_id() -> int:
	# A unique id per (match-run, event) so that a new match or new elimination
	# event re-shows the overlay even after a previous "Watch" dismissal.
	var local: Player = _local_player()
	var state_id: int = int(_state.match_time * 10.0) if _state != null else 0
	state_id = _state.winner_id * 100000 if _state != null and _state.phase == Balance.PHASE_ENDED else 0
	if local != null and not local.is_alive:
		state_id = state_id | 1
	return state_id


func reset_overlay_dismissal() -> void:
	_overlay_dismissed_for_phase_id = -1


func _build_placement_message() -> void:
	_placement_msg = Label.new()
	_placement_msg.set_anchors_preset(Control.PRESET_CENTER)
	_placement_msg.offset_left = -260
	_placement_msg.offset_right = 260
	_placement_msg.offset_top = -32
	_placement_msg.offset_bottom = 32
	_placement_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placement_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placement_msg.text = "Tap a plains / forest / hill tile to place your Crown"
	_apply_label_style(_placement_msg)
	_placement_msg.add_theme_font_size_override("font_size", 20)
	_placement_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_placement_msg)


func _make_stat_label(initial: String, min_width: int) -> Label:
	var lbl := Label.new()
	lbl.custom_minimum_size = Vector2(min_width, BAR_HEIGHT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_label_style(lbl)
	lbl.text = initial
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _apply_label_style(lbl: Label) -> void:
	lbl.add_theme_color_override("font_color", COLOR_TEXT)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)


func _build_bottom() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = MARGIN
	panel.offset_right = -MARGIN
	panel.offset_bottom = -MARGIN
	panel.offset_top = -(Balance.MIN_BUTTON_PX + 32)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	_slider_label = Label.new()
	_slider_label.custom_minimum_size = Vector2(140, Balance.MIN_BUTTON_PX)
	_slider_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_apply_label_style(_slider_label)
	_slider_label.text = "Send 50%"
	_slider_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_slider_label)

	_slider = HSlider.new()
	_slider.custom_minimum_size = Vector2(240, Balance.MIN_BUTTON_PX)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.min_value = Balance.SEND_MIN_FRACTION * 100.0
	_slider.max_value = Balance.SEND_MAX_FRACTION * 100.0
	_slider.step = 1.0
	_slider.value = _send_fraction * 100.0
	_slider.value_changed.connect(_on_slider_changed)
	row.add_child(_slider)

	for i in range(QUICK_BUTTONS.size()):
		var frac: float = QUICK_BUTTONS[i]
		var btn := Button.new()
		btn.text = "%d%%" % int(frac * 100.0)
		btn.custom_minimum_size = Vector2(72, Balance.MIN_BUTTON_PX)
		var captured: float = frac
		btn.pressed.connect(func() -> void: _set_fraction(captured))
		row.add_child(btn)


# --- Updates (every frame) ---------------------------------------------------

func update_from_state() -> void:
	if _state == null:
		return
	_update_local(_local_player())
	_update_phase_display()
	_update_leaderboard()
	_update_attacks()
	_update_alerts()
	_update_announcement()
	_update_end_overlay()
	_update_ability_bar()


func _update_alerts() -> void:
	var local: Player = _local_player()
	if local == null:
		_alert_button.visible = false
		return
	var active: bool = local.is_alive and local.crown_alert_until > _state.match_time
	_alert_button.visible = active


func _update_announcement() -> void:
	var active: bool = _state.active_announcement_until > _state.match_time
	_announcement_label.visible = active and _state.active_announcement_text != ""
	if _announcement_label.visible:
		_announcement_label.text = _state.active_announcement_text


func _update_end_overlay() -> void:
	var local: Player = _local_player()
	var overlay_id: int = _current_overlay_id()
	var should_show: bool = false
	if _state.phase == Balance.PHASE_ENDED:
		should_show = true
	elif local != null and not local.is_alive:
		should_show = true
	if not should_show:
		_end_overlay.visible = false
		return
	if overlay_id == _overlay_dismissed_for_phase_id:
		_end_overlay.visible = false
		return
	_end_overlay.visible = true
	_populate_end_overlay(local)


func _populate_end_overlay(local: Player) -> void:
	var title: String = "Defeated"
	var subtitle: String = ""
	if _state.phase == Balance.PHASE_ENDED:
		if _state.winner_id == _sim.local_player_id:
			title = "Victory!"
		elif _state.winner_id == 0:
			title = "Match ended"
		else:
			var w: Player = _state.get_player(_state.winner_id)
			title = "%s wins" % (w.display_name if w != null else "Someone")
		subtitle = _state.win_reason
	else:
		subtitle = "Your Crown has fallen — you can watch the rest of the match."
	_end_title.text = title
	_end_subtitle.text = subtitle
	var usable: int = _state.total_usable_tiles()
	var denom: float = float(maxi(usable, 1))
	var peak_pct: float = 0.0
	var crowns_captured: int = 0
	if local != null:
		peak_pct = 100.0 * float(local.peak_land) / denom
		crowns_captured = local.crowns_captured
	_end_stats.text = "Time: %s   Peak land: %.1f%%   Crowns taken: %d" % [
		format_time(_state.match_time), peak_pct, crowns_captured,
	]


func _update_attacks() -> void:
	if _sim == null:
		return
	var attacks: Array = _sim.attacks_by(_sim.local_player_id)
	for i in range(_attack_rows.size()):
		var btn: Button = _attack_rows[i]
		if i < attacks.size():
			var a: Attack = attacks[i]
			var defender: Player = _state.get_player(a.defender_id)
			var defender_name: String = "???"
			if defender != null:
				defender_name = defender.display_name
			btn.visible = true
			btn.text = "⚔ %s  %d" % [defender_name, int(a.troops_remaining)]
		else:
			btn.visible = false


func _on_attack_pressed(idx: int) -> void:
	if _sim == null:
		return
	_sim.player_retreat(_sim.local_player_id, idx)


func _local_player() -> Player:
	if _state == null or _state.players.is_empty():
		return null
	return _state.players[0]


func _update_local(p: Player) -> void:
	if p == null:
		return
	var cap: float = p.troop_cap()
	_troop_label.text = "%d / %d" % [int(p.troops), int(cap)]
	var ratio: float = 0.0
	if cap > 0.0:
		ratio = p.troops / cap
	var fill_fraction: float = clampf(ratio, 0.0, 1.0)
	_bar_fill.anchor_right = fill_fraction
	var in_sweet: bool = ratio >= Balance.TROOP_BAR_SWEET_LOW and ratio <= Balance.TROOP_BAR_SWEET_HIGH
	if p.troops > cap:
		_bar_fill.color = COLOR_OVER
	elif in_sweet:
		_bar_fill.color = COLOR_SWEET
	else:
		_bar_fill.color = COLOR_NORMAL
	var tps: float = p.troops_per_second_at(cap)
	_per_sec_label.text = "%+.1f/s" % tps
	var usable: int = _state.total_usable_tiles()
	var denom: float = float(maxi(usable, 1))
	var land_pct: float = 100.0 * float(p.land) / denom
	_land_label.text = "%.1f%%" % land_pct


func _update_phase_display() -> void:
	match _state.phase:
		Balance.PHASE_PLACEMENT:
			_placement_msg.visible = true
			var t_left: int = maxi(0, ceili(_state.placement_time_left))
			_placement_msg.text = "Tap a plains / forest / hill tile to place your Crown  (%ds)" % t_left
			_timer_label.text = "Placement  0:%02d" % t_left
		Balance.PHASE_MATCH:
			_placement_msg.visible = false
			if _state.match_time < Balance.PEACE_PERIOD_SEC:
				var peace_left: float = Balance.PEACE_PERIOD_SEC - _state.match_time
				_timer_label.text = "Peace ends  %s" % format_time(peace_left)
			elif _state.match_time >= Balance.FINAL_SIEGE_START_SEC:
				_timer_label.text = "Final Siege  %s" % format_time(_state.match_time)
			else:
				_timer_label.text = format_time(_state.match_time)
		_:
			_placement_msg.visible = false
			_timer_label.text = format_time(_state.match_time)


func _update_leaderboard() -> void:
	var alive: Array = _state.players.duplicate()
	alive.sort_custom(func(a: Player, b: Player) -> bool: return a.land > b.land)
	var usable: int = _state.total_usable_tiles()
	var denom: float = float(maxi(usable, 1))
	for i in range(_leader_rows.size()):
		var row: Dictionary = _leader_rows[i]
		if i < alive.size():
			var p: Player = alive[i]
			row.row.visible = true
			if p.is_alive:
				row.swatch.color = p.color
			else:
				row.swatch.color = Color(0.25, 0.25, 0.25)
			var short_name: String = p.display_name
			if short_name.length() > 16:
				short_name = short_name.substr(0, 16)
			row.name.text = short_name
			row.land.text = "%.1f%%" % (100.0 * float(p.land) / denom)
		else:
			row.row.visible = false


static func format_time(seconds: float) -> String:
	var total: int = int(seconds)
	@warning_ignore("integer_division")
	var mm: int = total / 60
	var ss: int = total % 60
	return "%d:%02d" % [mm, ss]


func _on_slider_changed(v: float) -> void:
	_send_fraction = v / 100.0
	_update_slider_label()


func _set_fraction(frac: float) -> void:
	_send_fraction = frac
	_slider.value = frac * 100.0
	_update_slider_label()


func _update_slider_label() -> void:
	_slider_label.text = "Send %d%%" % int(round(_send_fraction * 100.0))


# --- Build menu --------------------------------------------------------------

func _build_build_menu() -> void:
	_build_menu = PanelContainer.new()
	_build_menu.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_build_menu.offset_left = 24
	_build_menu.offset_top = -180
	_build_menu.offset_right = 300
	_build_menu.offset_bottom = 220
	_build_menu.visible = false
	add_child(_build_menu)

	_build_menu_vbox = VBoxContainer.new()
	_build_menu_vbox.add_theme_constant_override("separation", 6)
	_build_menu.add_child(_build_menu_vbox)

	_build_menu_tile_label = Label.new()
	_build_menu_tile_label.text = "Build"
	_apply_label_style(_build_menu_tile_label)
	_build_menu_tile_label.add_theme_font_size_override("font_size", 18)
	_build_menu_vbox.add_child(_build_menu_tile_label)

	# 6 slots so we can re-use rows for Fort / Fort II / Barracks / Port / Wall-mode / Boat / Close.
	for i in range(7):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(260, 40)
		btn.visible = false
		_build_menu_vbox.add_child(btn)
		_build_menu_buttons.append(btn)

	_wall_mode_label = Label.new()
	_apply_label_style(_wall_mode_label)
	_wall_mode_label.text = ""
	_wall_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wall_mode_label.anchor_left = 0.0
	_wall_mode_label.anchor_right = 1.0
	_wall_mode_label.anchor_top = 1.0
	_wall_mode_label.anchor_bottom = 1.0
	_wall_mode_label.offset_top = -(Balance.MIN_BUTTON_PX + 70)
	_wall_mode_label.offset_bottom = -(Balance.MIN_BUTTON_PX + 40)
	_wall_mode_label.add_theme_font_size_override("font_size", 18)
	_wall_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wall_mode_label)


func _build_keep_panel() -> void:
	_keep_panel = PanelContainer.new()
	_keep_panel.set_anchors_preset(Control.PRESET_CENTER)
	_keep_panel.offset_left = -180
	_keep_panel.offset_right = 180
	_keep_panel.offset_top = -140
	_keep_panel.offset_bottom = 140
	_keep_panel.visible = false
	add_child(_keep_panel)

	_keep_vbox = VBoxContainer.new()
	_keep_vbox.add_theme_constant_override("separation", 10)
	_keep_panel.add_child(_keep_vbox)

	var header := Label.new()
	header.text = "Keep upgrades"
	_apply_label_style(header)
	header.add_theme_font_size_override("font_size", 22)
	_keep_vbox.add_child(header)

	for i in range(3):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(300, 40)
		var lvl: int = i + 1
		btn.pressed.connect(func() -> void: _on_keep_pressed(lvl))
		_keep_vbox.add_child(btn)
		_keep_buttons.append(btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(300, 40)
	close_btn.pressed.connect(func() -> void: _keep_panel.visible = false)
	_keep_vbox.add_child(close_btn)


func open_build_menu(tile_x: int, tile_y: int) -> void:
	if _sim == null or _state == null:
		return
	var local: Player = _local_player()
	if local == null or not local.is_alive:
		return
	var ti: int = _state.idx(tile_x, tile_y)
	if _state.owners[ti] != _sim.local_player_id:
		return
	_build_menu_tile = Vector2i(tile_x, tile_y)
	_build_menu_tile_label.text = "Build at (%d, %d)   troops %d" % [tile_x, tile_y, int(local.troops)]
	_populate_build_buttons(local, ti)
	_build_menu.visible = true


func close_build_menu() -> void:
	_build_menu.visible = false
	_build_menu_tile = Vector2i(-1, -1)


func is_build_menu_open() -> bool:
	return _build_menu != null and _build_menu.visible


func wall_mode_active() -> bool:
	return _wall_mode


func set_wall_mode(enabled: bool) -> void:
	_wall_mode = enabled
	_wall_mode_label.text = "Wall mode ON — tap or drag your land to build walls (tap again to cancel)" if enabled else ""


func _populate_build_buttons(local: Player, ti: int) -> void:
	for btn: Button in _build_menu_buttons:
		btn.visible = false
		for c in btn.pressed.get_connections():
			btn.pressed.disconnect(c.callable)
	var pos: Vector2i = _build_menu_tile
	var is_port_here: bool = false
	var is_fort_here: bool = false
	if _state.building_at_tile.has(ti):
		var b: Building = _state.building_at_tile[ti]
		if b.owner_id == local.id:
			is_port_here = b.type == Balance.BUILDING_PORT
			is_fort_here = b.type == Balance.BUILDING_FORT
	var buildable: bool = BuildingsOps.tile_is_buildable(_sim, local.id, ti)
	var row := 0
	# Fort or Fort II.
	if is_fort_here:
		var ub: Button = _build_menu_buttons[row]; row += 1
		ub.visible = true
		var afford: bool = local.troops >= Balance.FORT2_COST
		ub.text = "Upgrade to Fort II  %d%s" % [int(Balance.FORT2_COST), "" if afford else "  (need %d)" % int(Balance.FORT2_COST)]
		ub.disabled = not afford
		ub.pressed.connect(func() -> void: _on_upgrade_fort(pos.x, pos.y))
	elif buildable:
		var fb: Button = _build_menu_buttons[row]; row += 1
		fb.visible = true
		var fc: float = BuildingsOps.fort_cost_for(local)
		var afford2: bool = local.troops >= fc and local.fort_count < Balance.FORT_LIMIT
		fb.text = "Fort  %d  (%d/%d)" % [int(fc), local.fort_count, Balance.FORT_LIMIT]
		fb.disabled = not afford2
		fb.pressed.connect(func() -> void: _on_build_fort(pos.x, pos.y))
	# Barracks.
	if buildable and _state.match_time >= Balance.BARRACKS_UNLOCK_SEC:
		var bb: Button = _build_menu_buttons[row]; row += 1
		bb.visible = true
		var bc: float = BuildingsOps.barracks_cost_for(local)
		var afford3: bool = local.troops >= bc and local.barracks_count < Balance.BARRACKS_LIMIT
		bb.text = "Barracks  %d  (+10%% cap, %d/%d)" % [int(bc), local.barracks_count, Balance.BARRACKS_LIMIT]
		bb.disabled = not afford3
		bb.pressed.connect(func() -> void: _on_build_barracks(pos.x, pos.y))
	# Port (touches water).
	if buildable and _tile_touches_water(ti):
		var pb: Button = _build_menu_buttons[row]; row += 1
		pb.visible = true
		var afford4: bool = local.troops >= Balance.PORT_COST and local.port_count < Balance.PORT_LIMIT
		pb.text = "Port  %d  (%d/%d)" % [int(Balance.PORT_COST), local.port_count, Balance.PORT_LIMIT]
		pb.disabled = not afford4
		pb.pressed.connect(func() -> void: _on_build_port(pos.x, pos.y))
	# Wall mode toggle.
	var wb: Button = _build_menu_buttons[row]; row += 1
	wb.visible = true
	wb.text = "Wall mode OFF  (4/tile)" if not _wall_mode else "Wall mode ON — tap again to cancel"
	wb.disabled = false
	wb.pressed.connect(func() -> void: _on_wall_mode_pressed())
	# Launch boat (only if a Port here).
	if is_port_here:
		var lb: Button = _build_menu_buttons[row]; row += 1
		lb.visible = true
		lb.text = "Launch boat — then tap target"
		lb.disabled = false
		lb.pressed.connect(func() -> void: _on_launch_boat_pressed(pos.x, pos.y))
	# Close.
	var cb: Button = _build_menu_buttons[row]; row += 1
	cb.visible = true
	cb.text = "Close"
	cb.disabled = false
	cb.pressed.connect(func() -> void: close_build_menu())


func _tile_touches_water(ti: int) -> bool:
	var pos := _state.idx_to_xy(ti)
	for off in Simulation.NEIGHBOR_OFFSETS:
		var nx: int = pos.x + off.x
		var ny: int = pos.y + off.y
		if not _state.in_bounds(nx, ny):
			continue
		if _state.terrain[_state.idx(nx, ny)] == Balance.TERRAIN_WATER:
			return true
	return false


func _on_build_fort(x: int, y: int) -> void:
	build_fort_requested.emit(x, y)
	close_build_menu()


func _on_upgrade_fort(x: int, y: int) -> void:
	upgrade_fort_requested.emit(x, y)
	close_build_menu()


func _on_build_barracks(x: int, y: int) -> void:
	build_barracks_requested.emit(x, y)
	close_build_menu()


func _on_build_port(x: int, y: int) -> void:
	build_port_requested.emit(x, y)
	close_build_menu()


func _on_wall_mode_pressed() -> void:
	set_wall_mode(not _wall_mode)
	wall_mode_toggled.emit(_wall_mode)
	close_build_menu()


func _on_launch_boat_pressed(port_x: int, port_y: int) -> void:
	boat_launch_requested.emit(port_x, port_y)
	close_build_menu()


func _on_keep_pressed(level: int) -> void:
	buy_keep_requested.emit(level)


func open_keep_panel() -> void:
	if _sim == null:
		return
	var local: Player = _local_player()
	if local == null or local.crown_x < 0 or not local.is_alive:
		return
	for i in range(_keep_buttons.size()):
		var btn: Button = _keep_buttons[i]
		var lvl: int = i + 1
		var cost: float = Balance.KEEP_COST[lvl]
		var unlocked: bool = _state.match_time >= Balance.KEEP_UNLOCK_SEC[lvl]
		var owned: bool = local.keep_level >= lvl
		var is_next: bool = local.keep_level + 1 == lvl
		var afford: bool = local.troops >= cost
		if owned:
			btn.text = "Keep %d — owned" % lvl
			btn.disabled = true
		elif not unlocked:
			btn.text = "Keep %d — unlocks at %s" % [lvl, HUD.format_time(Balance.KEEP_UNLOCK_SEC[lvl])]
			btn.disabled = true
		elif not is_next:
			btn.text = "Keep %d — buy earlier levels first" % lvl
			btn.disabled = true
		else:
			btn.text = "Keep %d  %d troops   %s" % [lvl, int(cost), ("" if afford else "(need %d)" % int(cost))]
			btn.disabled = not afford
	_keep_panel.visible = true


func close_keep_panel() -> void:
	if _keep_panel != null:
		_keep_panel.visible = false


func is_keep_panel_open() -> bool:
	return _keep_panel != null and _keep_panel.visible


# --- Ability bar -------------------------------------------------------------

const ABILITY_LABELS: Array[String] = ["Swift March", "Crown Shield", "Rally", "Bombard"]

func _build_ability_bar() -> void:
	_ability_bar = PanelContainer.new()
	_ability_bar.anchor_left = 0.5
	_ability_bar.anchor_right = 0.5
	_ability_bar.anchor_top = 1.0
	_ability_bar.anchor_bottom = 1.0
	_ability_bar.offset_left = -260
	_ability_bar.offset_right = 260
	_ability_bar.offset_top = -(Balance.MIN_BUTTON_PX + 108)
	_ability_bar.offset_bottom = -(Balance.MIN_BUTTON_PX + 44)
	add_child(_ability_bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_ability_bar.add_child(row)

	for i in range(4):
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, Balance.MIN_BUTTON_PX)
		var local_id: int = i
		btn.pressed.connect(func() -> void: ability_pressed.emit(local_id))
		row.add_child(btn)
		_ability_buttons.append(btn)

	_bombard_hint_label = Label.new()
	_bombard_hint_label.anchor_left = 0.5
	_bombard_hint_label.anchor_right = 0.5
	_bombard_hint_label.anchor_top = 1.0
	_bombard_hint_label.anchor_bottom = 1.0
	_bombard_hint_label.offset_left = -260
	_bombard_hint_label.offset_right = 260
	_bombard_hint_label.offset_top = -(Balance.MIN_BUTTON_PX + 136)
	_bombard_hint_label.offset_bottom = -(Balance.MIN_BUTTON_PX + 110)
	_bombard_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_label_style(_bombard_hint_label)
	_bombard_hint_label.add_theme_font_size_override("font_size", 16)
	_bombard_hint_label.text = ""
	_bombard_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bombard_hint_label)


func set_bombard_target_mode(enabled: bool) -> void:
	_bombard_target_mode = enabled
	_bombard_hint_label.text = "Tap a target within 20 tiles of your border — tap outside to cancel" if enabled else ""


func is_bombard_target_mode() -> bool:
	return _bombard_target_mode


func _update_ability_bar() -> void:
	if _ability_bar == null:
		return
	var local: Player = _local_player()
	for i in range(_ability_buttons.size()):
		var btn: Button = _ability_buttons[i]
		if local == null or not local.is_alive:
			btn.disabled = true
			btn.text = ABILITY_LABELS[i]
			continue
		var cd_until: float = AbilitiesOps.cooldown_until(i, local)
		var now: float = _state.match_time
		var unlocked: bool = now >= AbilitiesOps.unlock_sec(i)
		var active: bool = false
		match i:
			AbilitiesOps.ID_SWIFT_MARCH:
				active = AbilitiesOps.is_swift_march_active(local, now)
			AbilitiesOps.ID_CROWN_SHIELD:
				active = AbilitiesOps.is_crown_shield_active(local, now)
			AbilitiesOps.ID_RALLY:
				active = AbilitiesOps.is_rally_active(local, now)
		var cost: float = AbilitiesOps.cost_now(i, local)
		var state_label: String
		if not unlocked:
			state_label = "unlocks %s" % HUD.format_time(AbilitiesOps.unlock_sec(i) - now)
		elif active:
			state_label = "ACTIVE"
		elif cd_until > now:
			state_label = "cd %ds" % int(ceilf(cd_until - now))
		elif cost > 0.0:
			state_label = "%d" % int(cost)
		else:
			state_label = "ready"
		btn.text = "%s\n%s" % [ABILITY_LABELS[i], state_label]
		btn.disabled = (not unlocked) or (cd_until > now) or (cost > 0.0 and local.troops < cost)
