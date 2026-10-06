class_name HUD
extends CanvasLayer

# Thumb-friendly HUD, laid out with anchors and containers inside the phone's
# safe area (notches). The pieces live in scripts/ui/; this file builds them,
# lays them out (mirrored for left-handed players) and feeds them each frame.
#
#   Top: Crown button, troop bar, troops/s, land %, timer, Menu
#   Top left: bonus / penalty badges, truces      Top right: leaderboard
#   Top centre: banner queue (never over the controls)
#   Bottom: send slider + ability bar             Above it: attacks, minimap

signal jump_to_crown_pressed
signal jump_to_world(world_pos: Vector2)
signal pause_requested

const MARGIN: int = 12
const LEFT_COLUMN_W: int = 440
const RIGHT_COLUMN_W: int = 360

var _sim: Simulation
var _state: GameState
var _safe: Control
var _placement_msg: Label
var _left_column: VBoxContainer
var _bottom_bar: HBoxContainer
var _alert_column: VBoxContainer
var _press_ring: Control
var _press_pos: Vector2 = Vector2.ZERO
var _press_progress: float = -1.0

var top_bar: TopBar
var send_slider: SendSlider
var attack_list: AttackList
var minimap: Minimap
var alerts: AlertQueue
var build_menu: BuildMenu
var keep_panel: KeepPanel
var ability_bar: AbilityBar
var enemy_panel: EnemyPanel
var mode_banner: ModeBanner
var popup_layer: PopupLayer
var end_overlay: EndOverlay
var modifier_badges: ModifierBadges
var truce_panel: TrucePanel
var leaderboard: Leaderboard
var ally_panel: AllyPanel
var pause_menu: PauseMenu
# Tutorial pieces (only in the tutorial). First-time tips stay quiet meanwhile.
var tutorial_card: TutorialCard
var tutorial_arrow: TutorialArrow


func _ready() -> void:
	layer = 10
	popup_layer = PopupLayer.new()
	add_child(popup_layer)
	_safe = Control.new()
	_safe.set_anchors_preset(Control.PRESET_FULL_RECT)
	_safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_safe)
	_build()
	_press_ring = Control.new()
	_press_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_press_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_press_ring.draw.connect(_draw_press_ring)
	add_child(_press_ring)
	end_overlay = EndOverlay.new()
	add_child(end_overlay)
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	Settings.changed.connect(apply_layout)
	get_viewport().size_changed.connect(apply_layout)
	apply_layout()


func setup(sim: Simulation, map: Map) -> void:
	_sim = sim
	_state = sim.state
	for c: Variant in [build_menu, keep_panel, ability_bar, enemy_panel, end_overlay, modifier_badges, truce_panel, leaderboard, top_bar, attack_list, ally_panel]:
		c.setup(sim)
	popup_layer.setup(sim.state, sim.local_player_id)
	minimap.setup(map, sim.state, sim.local_player_id)
	alerts.clear_all()
	update_from_state()


func send_fraction() -> float:
	return send_slider.fraction


func any_panel_open() -> bool:
	return build_menu.visible or keep_panel.visible or enemy_panel.visible


func close_panels() -> void:
	build_menu.close_menu()
	keep_panel.close_panel()
	enemy_panel.close_panel()


func add_tutorial(card: TutorialCard, arrow: TutorialArrow) -> void:
	tutorial_card = card
	tutorial_arrow = arrow
	_alert_column.add_child(card)
	_alert_column.move_child(card, 0)
	add_child(arrow)
	move_child(arrow, end_overlay.get_index())   # under the end screen and pause menu


func remove_tutorial() -> void:
	for n: Node in [tutorial_card, tutorial_arrow]:
		if n != null:
			n.queue_free()
	tutorial_card = null
	tutorial_arrow = null


# Gold banner + sound when an achievement is earned.
func show_achievement(id: String) -> void:
	var a: Dictionary = Progression.achievement(id)
	if a.is_empty():
		return
	alerts.push("Achievement: %s — %s" % [a.name, a.desc], "achievement", 5.0, "ach_" + id)
	Audio.play("sfx_victory", -10.0, 1.3)
	Settings.vibrate(80)


# Shows a short tip the first time an action happens.
func hint(id: String) -> void:
	if tutorial_card != null:
		return
	if Hints.TEXT.has(id) and Settings.first_time("hint_" + id):
		alerts.push(Hints.TEXT[id], "info", 6.0, "hint_" + id)


func set_long_press(pos: Vector2, progress: float) -> void:
	if progress != _press_progress or pos != _press_pos:
		_press_pos = pos
		_press_progress = progress
		_press_ring.queue_redraw()


# --- Build ---------------------------------------------------------------------

func _build() -> void:
	top_bar = TopBar.new()
	top_bar.crown_double_tapped.connect(func() -> void: jump_to_crown_pressed.emit())
	top_bar.crown_tapped_once.connect(func() -> void: hint("crown_button"))
	top_bar.menu_pressed.connect(func() -> void: pause_requested.emit())
	_safe.add_child(top_bar)
	_left_column = VBoxContainer.new()
	_left_column.add_theme_constant_override("separation", 8)
	_left_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_left_column)
	modifier_badges = ModifierBadges.new()
	modifier_badges.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_left_column.add_child(modifier_badges)
	truce_panel = TrucePanel.new()
	_left_column.add_child(truce_panel)
	ally_panel = AllyPanel.new()
	_left_column.add_child(ally_panel)
	leaderboard = Leaderboard.new()
	_safe.add_child(leaderboard)
	_alert_column = VBoxContainer.new()
	_alert_column.add_theme_constant_override("separation", 6)
	_alert_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_alert_column)
	mode_banner = ModeBanner.new()
	_alert_column.add_child(mode_banner)
	alerts = AlertQueue.new()
	alerts.action_pressed.connect(_on_alert_action)
	_alert_column.add_child(alerts)
	_bottom_bar = HBoxContainer.new()
	_bottom_bar.add_theme_constant_override("separation", 12)
	_bottom_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_bottom_bar)
	send_slider = SendSlider.new()
	send_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_slider.size_flags_vertical = Control.SIZE_SHRINK_END
	_bottom_bar.add_child(send_slider)
	ability_bar = AbilityBar.new()
	ability_bar.ability_pressed.connect(func(_id: int) -> void: hint("ability"))
	_bottom_bar.add_child(ability_bar)
	attack_list = AttackList.new()
	_safe.add_child(attack_list)
	minimap = Minimap.new()
	minimap.jump_to.connect(_on_minimap_jump)
	_safe.add_child(minimap)
	_placement_msg = UIStyle.label("", 24)
	_placement_msg.set_anchors_preset(Control.PRESET_CENTER)
	_placement_msg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_placement_msg.grow_vertical = Control.GROW_DIRECTION_BOTH
	_placement_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_safe.add_child(_placement_msg)
	build_menu = BuildMenu.new()
	keep_panel = KeepPanel.new()
	enemy_panel = EnemyPanel.new()
	for panel: Control in [build_menu, keep_panel, enemy_panel]:
		_safe.add_child(panel)


func _on_alert_action(id: String) -> void:
	if id == "crown_alert":
		jump_to_crown_pressed.emit()


func _on_minimap_jump(world_pos: Vector2) -> void:
	hint("minimap")
	jump_to_world.emit(world_pos)


# --- Layout --------------------------------------------------------------------

# Anchors everything inside the safe area. Left-handed mirrors the controls:
# slider, abilities, attack list, minimap and the pop-up panels swap sides.
func apply_layout() -> void:
	if top_bar == null:
		return
	var insets: Rect2 = _safe_insets()
	_safe.offset_left = insets.position.x
	_safe.offset_top = insets.position.y
	_safe.offset_right = -insets.size.x
	_safe.offset_bottom = -insets.size.y
	var lh: bool = Settings.left_handed
	_anchor(top_bar, 0.0, 0.0, 1.0, 0.0, MARGIN, MARGIN, -MARGIN, 0)
	var y0: int = MARGIN + int(top_bar.get_combined_minimum_size().y) + 8
	_anchor(_left_column, 0.0, 0.0, 0.0, 0.0, MARGIN, y0, MARGIN + LEFT_COLUMN_W, y0)
	_anchor(leaderboard, 1.0, 0.0, 1.0, 0.0, -MARGIN - RIGHT_COLUMN_W, y0, -MARGIN, y0)
	leaderboard.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_anchor(_alert_column, 0.0, 0.0, 1.0, 0.0, MARGIN + LEFT_COLUMN_W + 12, y0, -(MARGIN + RIGHT_COLUMN_W + 12), y0)
	_anchor(_bottom_bar, 0.0, 1.0, 1.0, 1.0, MARGIN, 0, -MARGIN, -MARGIN)
	_bottom_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bottom_bar.move_child(send_slider, 1 if lh else 0)
	var bottom_h: int = int(_bottom_bar.get_combined_minimum_size().y)
	var above: int = -(MARGIN + bottom_h + 8)
	var near_x: float = 1.0 if lh else 0.0      # the slider's side
	var far_x: float = 0.0 if lh else 1.0       # the abilities' side
	_corner(attack_list, near_x, above)
	_corner(minimap, far_x, above)
	var panel_inset: int = -MARGIN if lh else MARGIN
	for panel: Control in [build_menu, keep_panel, enemy_panel]:
		_anchor(panel, near_x, 0.5, near_x, 0.5, panel_inset, 0, panel_inset, 0)
		panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN if lh else Control.GROW_DIRECTION_END
		panel.grow_vertical = Control.GROW_DIRECTION_BOTH


func _anchor(c: Control, al: float, at: float, ar: float, ab: float, ol: int, ot: int, o_r: int, ob: int) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = o_r
	c.offset_bottom = ob


# Bottom corner on side x (0 = left, 1 = right), with its bottom edge at `bottom`.
func _corner(c: Control, x: float, bottom: int) -> void:
	var inset: int = MARGIN if x == 0.0 else -MARGIN
	_anchor(c, x, 1.0, x, 1.0, inset, bottom, inset, bottom)
	c.grow_horizontal = Control.GROW_DIRECTION_END if x == 0.0 else Control.GROW_DIRECTION_BEGIN
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN


# Notch / rounded-corner insets on phones (left, top, right, bottom in HUD
# pixels). Desktop windows don't have a meaningful safe area.
func _safe_insets() -> Rect2:
	if not OS.has_feature("mobile"):
		return Rect2()
	var win: Vector2 = Vector2(DisplayServer.window_get_size())
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if win.x <= 0.0 or safe.size.x <= 0:
		return Rect2()
	var k: float = get_viewport().get_visible_rect().size.x / win.x
	return Rect2(Vector2(safe.position) * k, (win - Vector2(safe.end)) * k)


# --- Every frame -----------------------------------------------------------------

func update_from_state() -> void:
	if _state == null:
		return
	top_bar.update_view()
	attack_list.update_view()
	leaderboard.update_view()
	modifier_badges.update_view()
	truce_panel.update_view()
	ally_panel.update_view()
	ability_bar.update_view()
	end_overlay.update_view()
	_update_placement()
	_update_crown_alert()


# Announcements from the simulation become banners.
func consume_events(events: Array) -> void:
	for e: Dictionary in events:
		if e.type == "announce":
			alerts.push(str(e.text), "event", float(e.get("seconds", 4.0)))
		elif e.type == "ally_send" and int(e.to_id) == _sim.local_player_id:
			var from_p: Player = _state.get_player(int(e.from_id))
			alerts.push("%s sent you %s troops" % [from_p.display_name if from_p != null else "Your ally", GameState.format_int(int(e.amount))], "info", 3.0)


func _update_placement() -> void:
	_placement_msg.visible = _state.phase == Balance.PHASE_PLACEMENT and tutorial_card == null
	if _placement_msg.visible:
		var text: String = "Tap plains, forest or hills to place your Crown"
		if not _state.tutorial_rules:
			text += "  (%ds)" % maxi(0, ceili(_state.placement_time_left))
		var ally: Player = _sim.ally_of(_state.get_player(_sim.local_player_id))
		if ally != null:
			text += "\nYour ally %s will settle next to you" % ally.display_name
		_placement_msg.text = text


func _update_crown_alert() -> void:
	var me: Player = _state.get_player(_sim.local_player_id)
	var active: bool = me != null and me.is_alive and me.crown_alert_until > _state.match_time
	if active:
		alerts.push("Your Crown is under attack!", "warning", 1.0, "crown_alert", "Jump")
	elif alerts.has_banner("crown_alert"):
		alerts.dismiss("crown_alert")


func _draw_press_ring() -> void:
	if _press_progress < 0.0:
		return
	var r: float = 34.0
	_press_ring.draw_arc(_press_pos, r, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 8.0, true)
	_press_ring.draw_arc(_press_pos, r, -PI * 0.5, -PI * 0.5 + TAU * _press_progress, 40, Color(1, 1, 1, 0.9), 5.0, true)
