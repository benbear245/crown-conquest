class_name HUD
extends CanvasLayer

# Thumb-friendly HUD built in code. Reads GameState; never mutates it. The
# bigger panels live in scripts/ui/ and are created and laid out here.

const QUICK_BUTTONS: Array[float] = [0.25, 0.50, 0.75, 1.00]
const MARGIN: int = 16
const BAR_HEIGHT: int = 32
const BAR_WIDTH: int = 420
const COLOR_SWEET: Color = Color(0.40, 0.95, 0.50)
const COLOR_NORMAL: Color = Color(0.95, 0.85, 0.35)
const COLOR_OVER: Color = Color(0.95, 0.40, 0.35)
const LEADERBOARD_ROWS: int = 5
const LEADERBOARD_WIDTH: int = 280

signal new_map_pressed
signal jump_to_crown_pressed

var _sim: Simulation
var _state: GameState
var _send_fraction: float = 0.50

var _bar_fill: ColorRect
var _troop_label: Label
var _per_sec_label: Label
var _land_label: Label
var _timer_label: Label
var _slider: HSlider
var _slider_label: Label
var _placement_msg: Label
var _leader_rows: Array[Dictionary] = []
var _attack_rows: Array[Button] = []
var _alert_button: Button
var _announcement_label: Label
var _modifier_label: Label

# Component panels (scripts/ui/). game.gd connects their signals.
var build_menu: BuildMenu
var keep_panel: KeepPanel
var ability_bar: AbilityBar
var enemy_panel: EnemyPanel
var mode_banner: ModeBanner
var popup_layer: PopupLayer
var end_overlay: EndOverlay


func _ready() -> void:
	layer = 10
	popup_layer = PopupLayer.new()
	add_child(popup_layer)
	_build_top()
	_build_modifier_label()
	_build_leaderboard()
	_build_attacks()
	_build_placement_message()
	_build_alerts()
	_build_bottom()
	_build_panels()


func setup(sim: Simulation) -> void:
	_sim = sim
	_state = sim.state
	for c: Variant in [build_menu, keep_panel, ability_bar, enemy_panel, end_overlay]:
		c.setup(sim)
	popup_layer.setup(sim.state, sim.local_player_id)
	update_from_state()


func send_fraction() -> float:
	return _send_fraction


func any_panel_open() -> bool:
	return build_menu.visible or keep_panel.visible or enemy_panel.visible


func close_panels() -> void:
	build_menu.close_menu()
	keep_panel.close_panel()
	enemy_panel.close_panel()


# --- Build (one-time) --------------------------------------------------------

func _build_top() -> void:
	var panel := UIStyle.panel()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = MARGIN
	panel.offset_right = -MARGIN
	panel.offset_top = MARGIN
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
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.08, 0.08, 0.10)
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = COLOR_NORMAL
	_bar_fill.anchor_bottom = 1.0
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_wrap.add_child(_bar_fill)
	_troop_label = UIStyle.label("0 / 0")
	_troop_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_troop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_troop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_wrap.add_child(_troop_label)
	_per_sec_label = _stat_label("+0.0/s", 110)
	row.add_child(_per_sec_label)
	_land_label = _stat_label("0.0%", 90)
	row.add_child(_land_label)
	_timer_label = _stat_label("0:00", 200)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_timer_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var new_map := UIStyle.button("New map", 120)
	new_map.custom_minimum_size.y = BAR_HEIGHT
	new_map.alignment = HORIZONTAL_ALIGNMENT_CENTER
	new_map.pressed.connect(func() -> void: new_map_pressed.emit())
	row.add_child(new_map)


func _stat_label(initial: String, min_width: int) -> Label:
	var lbl := UIStyle.label(initial)
	lbl.custom_minimum_size = Vector2(min_width, BAR_HEIGHT)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


func _build_modifier_label() -> void:
	_modifier_label = UIStyle.label("", UIStyle.FONT_SMALL)
	_modifier_label.position = Vector2(MARGIN + 12, MARGIN + BAR_HEIGHT + 30)
	_modifier_label.size = Vector2(900, 24)
	add_child(_modifier_label)


func _build_leaderboard() -> void:
	var panel := UIStyle.panel()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -(LEADERBOARD_WIDTH + MARGIN)
	panel.offset_right = -MARGIN
	panel.offset_top = MARGIN + BAR_HEIGHT + 34
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)
	vbox.add_child(UIStyle.label("Leaderboard", UIStyle.FONT_NORMAL))
	for i in range(LEADERBOARD_ROWS):
		var row_box := HBoxContainer.new()
		row_box.add_theme_constant_override("separation", 8)
		row_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(row_box)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_box.add_child(swatch)
		var name_label := UIStyle.label("", UIStyle.FONT_SMALL + 1)
		name_label.custom_minimum_size = Vector2(170, 20)
		row_box.add_child(name_label)
		var land_label := UIStyle.label("", UIStyle.FONT_SMALL + 1)
		land_label.custom_minimum_size = Vector2(56, 20)
		land_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row_box.add_child(land_label)
		_leader_rows.append({"row": row_box, "swatch": swatch, "name": name_label, "land": land_label})


func _build_attacks() -> void:
	var panel := UIStyle.panel()
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = MARGIN
	panel.offset_right = MARGIN + 300
	panel.offset_bottom = -(Balance.MIN_BUTTON_PX * 2 + 64)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)
	vbox.add_child(UIStyle.label("Attacks (tap to retreat 75%)", UIStyle.FONT_SMALL))
	for i in range(Balance.MAX_SIMULTANEOUS_ATTACKS):
		var btn := UIStyle.button("", 280)
		btn.visible = false
		var local_i: int = i
		btn.pressed.connect(func() -> void: _sim.player_retreat(_sim.local_player_id, local_i))
		vbox.add_child(btn)
		_attack_rows.append(btn)


func _build_alerts() -> void:
	_alert_button = UIStyle.button("⚠ Crown under attack — tap to jump", 0)
	_alert_button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alert_button.anchor_left = 0.5
	_alert_button.anchor_right = 0.5
	_alert_button.offset_left = -240
	_alert_button.offset_right = 240
	_alert_button.offset_top = MARGIN + BAR_HEIGHT + 64
	_alert_button.visible = false
	_alert_button.add_theme_color_override("font_color", UIStyle.COLOR_WARN)
	_alert_button.pressed.connect(func() -> void: jump_to_crown_pressed.emit())
	add_child(_alert_button)
	_announcement_label = UIStyle.label("", 22)
	_announcement_label.anchor_left = 0.5
	_announcement_label.anchor_right = 0.5
	_announcement_label.offset_left = -420
	_announcement_label.offset_right = 420
	_announcement_label.offset_top = MARGIN + BAR_HEIGHT + 128
	_announcement_label.offset_bottom = _announcement_label.offset_top + 36
	_announcement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announcement_label.visible = false
	add_child(_announcement_label)


func _build_placement_message() -> void:
	_placement_msg = UIStyle.label("", 22)
	_placement_msg.set_anchors_preset(Control.PRESET_CENTER)
	_placement_msg.offset_left = -360
	_placement_msg.offset_right = 360
	_placement_msg.offset_top = -32
	_placement_msg.offset_bottom = 32
	_placement_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placement_msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_placement_msg)


func _build_bottom() -> void:
	var panel := UIStyle.panel()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = MARGIN
	panel.offset_right = -MARGIN
	panel.offset_bottom = -MARGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	_slider_label = UIStyle.label("Send 50%")
	_slider_label.custom_minimum_size = Vector2(130, Balance.MIN_BUTTON_PX)
	_slider_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_slider_label)
	_slider = HSlider.new()
	_slider.custom_minimum_size = Vector2(240, Balance.MIN_BUTTON_PX)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.min_value = Balance.SEND_MIN_FRACTION * 100.0
	_slider.max_value = Balance.SEND_MAX_FRACTION * 100.0
	_slider.step = 1.0
	_slider.value = _send_fraction * 100.0
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.value_changed.connect(_on_slider_changed)
	row.add_child(_slider)
	for frac: float in QUICK_BUTTONS:
		var btn := UIStyle.button("%d%%" % int(frac * 100.0), 76)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.pressed.connect(func() -> void: _set_fraction(frac))
		row.add_child(btn)


func _build_panels() -> void:
	ability_bar = AbilityBar.new()
	ability_bar.anchor_left = 0.5
	ability_bar.anchor_right = 0.5
	ability_bar.anchor_top = 1.0
	ability_bar.anchor_bottom = 1.0
	ability_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ability_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ability_bar.offset_bottom = -(Balance.MIN_BUTTON_PX + 56)
	add_child(ability_bar)
	build_menu = BuildMenu.new()
	build_menu.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	build_menu.grow_vertical = Control.GROW_DIRECTION_BOTH
	build_menu.offset_left = MARGIN
	add_child(build_menu)
	keep_panel = KeepPanel.new()
	keep_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	keep_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	keep_panel.offset_left = MARGIN
	add_child(keep_panel)
	enemy_panel = EnemyPanel.new()
	enemy_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	enemy_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	enemy_panel.offset_left = MARGIN
	add_child(enemy_panel)
	mode_banner = ModeBanner.new()
	mode_banner.anchor_left = 0.5
	mode_banner.anchor_right = 0.5
	mode_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mode_banner.offset_top = MARGIN + BAR_HEIGHT + 64
	add_child(mode_banner)
	end_overlay = EndOverlay.new()
	add_child(end_overlay)


# --- Updates (every frame) ---------------------------------------------------

func update_from_state() -> void:
	if _state == null:
		return
	_update_local(_state.get_player(_sim.local_player_id))
	_update_phase_display()
	_update_leaderboard()
	_update_attacks()
	_update_alerts()
	_update_modifier_label()
	ability_bar.update_view()
	end_overlay.update_view()


func _update_local(p: Player) -> void:
	if p == null:
		return
	var cap: float = p.troop_cap()
	_troop_label.text = "%d / %d" % [int(p.troops), int(cap)]
	var ratio: float = p.troops / cap if cap > 0.0 else 0.0
	_bar_fill.anchor_right = clampf(ratio, 0.0, 1.0)
	if p.troops > cap:
		_bar_fill.color = COLOR_OVER
	elif ratio >= Balance.TROOP_BAR_SWEET_LOW and ratio <= Balance.TROOP_BAR_SWEET_HIGH:
		_bar_fill.color = COLOR_SWEET
	else:
		_bar_fill.color = COLOR_NORMAL
	var tps: float = p.troops_per_second_at(cap)
	if tps > 0.0:
		tps *= _sim.growth_multiplier(p)
	_per_sec_label.text = "%+.1f/s" % tps
	_land_label.text = "%.1f%%" % (100.0 * _state.land_fraction(p))


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
				_timer_label.text = "Peace ends  %s" % GameState.format_time(Balance.PEACE_PERIOD_SEC - _state.match_time)
			elif _state.is_final_siege():
				_timer_label.text = "Final Siege  %s" % GameState.format_time(_state.match_time)
			else:
				_timer_label.text = GameState.format_time(_state.match_time)
		_:
			_placement_msg.visible = false
			_timer_label.text = GameState.format_time(_state.match_time)


func _update_leaderboard() -> void:
	var ranked: Array[Player] = _state.players.duplicate()
	ranked.sort_custom(func(a: Player, b: Player) -> bool: return a.land > b.land)
	var me: Player = _state.get_player(_sim.local_player_id)
	var rising_id: int = _sim.rising_empire_id()
	for i in range(_leader_rows.size()):
		var row: Dictionary = _leader_rows[i]
		if i >= ranked.size():
			row.row.visible = false
			continue
		var p: Player = ranked[i]
		row.row.visible = true
		row.swatch.color = p.color if p.is_alive else Color(0.25, 0.25, 0.25)
		var markers: String = ""
		if rising_id > 0 and p.id == rising_id:
			markers += " ★"
		if me != null and p.id != me.id and TrucesOps.has_truce(me, p.id, _state.match_time):
			markers += " ⚑"
		row.name.text = p.display_name.left(16) + markers
		row.land.text = "%.1f%%" % (100.0 * _state.land_fraction(p))


func _update_attacks() -> void:
	var attacks: Array[Attack] = _sim.attacks_by(_sim.local_player_id)
	for i in range(_attack_rows.size()):
		var btn: Button = _attack_rows[i]
		if i < attacks.size():
			var a: Attack = attacks[i]
			var defender: Player = _state.get_player(a.defender_id)
			btn.visible = true
			btn.text = "⚔ %s  %d" % [(defender.display_name if defender != null else "???"), int(a.troops_remaining)]
		else:
			btn.visible = false


func _update_alerts() -> void:
	var me: Player = _state.get_player(_sim.local_player_id)
	_alert_button.visible = me != null and me.is_alive and me.crown_alert_until > _state.match_time and not mode_banner.visible
	var active: bool = _state.active_announcement_until > _state.match_time and _state.active_announcement_text != ""
	_announcement_label.visible = active
	if active:
		_announcement_label.text = _state.active_announcement_text


func _update_modifier_label() -> void:
	var me: Player = _state.get_player(_sim.local_player_id)
	if me == null:
		_modifier_label.text = ""
		return
	var parts: Array[String] = []
	if _sim.is_underdog(me):
		parts.append("UNDERDOG +25% growth / -25% claim")
	var upkeep: float = _sim.empire_upkeep(me)
	if upkeep < 0.0:
		parts.append("EMPIRE UPKEEP %d%% growth" % int(upkeep * 100.0))
	if TrucesOps.is_oathbreaker(me, _state.match_time):
		parts.append("OATHBREAKER +20% attack cost")
	_modifier_label.text = "   ".join(parts)


# --- Slider ------------------------------------------------------------------

func _on_slider_changed(v: float) -> void:
	_send_fraction = v / 100.0
	_slider_label.text = "Send %d%%" % int(round(_send_fraction * 100.0))


func _set_fraction(frac: float) -> void:
	_slider.value = frac * 100.0
