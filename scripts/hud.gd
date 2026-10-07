class_name HUD
extends CanvasLayer

# Builds the HUD out of small panels (scripts/ui/) and forwards their
# signals to the game. Only reads from the Simulation; never mutates it.

signal command(name: String, args: Array)
signal crown_jump_requested
signal minimap_jump(world_pos: Vector2)
signal ability_became_ready(ability_id: int)
signal target_mode_requested(mode: String, data: Vector2i)
signal menu_toggled(open: bool)
signal new_map_requested

var top_bar: HudTopBar
var leaderboard: HudLeaderboard
var minimap: HudMinimap
var bottom_bar: HudBottomBar
var attacks: HudAttacks
var banners: HudBanners
var hints: HudHints
var build_menu: HudBuildMenu
var keep_panel: HudKeepPanel
var enemy_panel: HudEnemyPanel
var menu: HudMenu
var end_overlay: HudEndOverlay

var _sim: Simulation
var _mode_label: Label
var _placement_label: Label


func _ready() -> void:
	layer = 10
	top_bar = _add(HudTopBar.new())
	leaderboard = _add(HudLeaderboard.new())
	minimap = _add(HudMinimap.new())
	attacks = _add(HudAttacks.new())
	bottom_bar = _add(HudBottomBar.new())
	hints = _add(HudHints.new())
	banners = _add(HudBanners.new())
	_mode_label = _add(UI.label("", 20, UI.COLOR_WARN))
	_mode_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mode_label.offset_left = -400
	_mode_label.offset_right = 400
	_mode_label.offset_top = UI.TOP_BAR_H + 44 + HudBanners.MAX_VISIBLE * 60
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placement_label = _add(UI.label("", 26))
	UI.centre(_placement_label, 900, 60)
	_placement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_menu = _add(HudBuildMenu.new())
	keep_panel = _add(HudKeepPanel.new())
	enemy_panel = _add(HudEnemyPanel.new())
	end_overlay = _add(HudEndOverlay.new())
	menu = _add(HudMenu.new())
	_connect_signals()
	apply_layout()
	Settings.changed.connect(apply_layout)


func _add(c: Control) -> Variant:
	add_child(c)
	return c


func _connect_signals() -> void:
	top_bar.menu_pressed.connect(func() -> void: set_menu_open(not menu.visible))
	menu.resume_pressed.connect(func() -> void: set_menu_open(false))
	menu.new_map_pressed.connect(func() -> void:
		set_menu_open(false)
		new_map_requested.emit())
	end_overlay.play_again_pressed.connect(func() -> void: new_map_requested.emit())
	minimap.jump_requested.connect(func(p: Vector2) -> void: minimap_jump.emit(p))
	attacks.retreat_pressed.connect(func(i: int) -> void: command.emit("retreat", [i]))
	bottom_bar.crown_tapped.connect(func() -> void:
		close_panels()
		keep_panel.visible = true
		hints.done("crown"))
	bottom_bar.crown_double_tapped.connect(func() -> void:
		keep_panel.visible = false
		crown_jump_requested.emit())
	bottom_bar.ability_pressed.connect(_on_ability_pressed)
	bottom_bar.ability_ready.connect(func(i: int) -> void: ability_became_ready.emit(i))
	banners.crown_alert_tapped.connect(func() -> void: crown_jump_requested.emit())
	banners.truce_answered.connect(func(from_id: int, yes: bool) -> void: command.emit("answer_truce", [from_id, yes]))
	build_menu.build_requested.connect(func(t: int, x: int, y: int) -> void: command.emit("build", [t, x, y]))
	build_menu.upgrade_fort_requested.connect(func(x: int, y: int) -> void: command.emit("upgrade_fort", [x, y]))
	build_menu.wall_mode_requested.connect(func() -> void: target_mode_requested.emit("wall", Vector2i.ZERO))
	build_menu.boat_mode_requested.connect(func(x: int, y: int) -> void: target_mode_requested.emit("boat", Vector2i(x, y)))
	keep_panel.buy_keep_requested.connect(func(lvl: int) -> void: command.emit("buy_keep", [lvl]))
	keep_panel.move_crown_requested.connect(func() -> void: target_mode_requested.emit("crown_move", Vector2i.ZERO))
	keep_panel.disinformation_requested.connect(func(strong: bool) -> void: command.emit("disinformation", [strong]))
	enemy_panel.offer_truce_requested.connect(func(id: int) -> void: command.emit("offer_truce", [id]))
	enemy_panel.spy_requested.connect(func(id: int, action: int) -> void: command.emit("spy", [id, action]))


func _on_ability_pressed(ability_id: int) -> void:
	if ability_id == AbilitiesOps.ID_BOMBARD:
		target_mode_requested.emit("bombard", Vector2i.ZERO)
	else:
		command.emit("ability", [ability_id])


func setup(sim: Simulation, map_texture: Texture2D) -> void:
	_sim = sim
	minimap.setup(sim.state, map_texture)
	end_overlay.reset()
	banners.clear_all()
	close_panels()
	set_mode_text("")
	apply_layout()


func apply_layout() -> void:
	var lh: bool = Settings.left_handed
	leaderboard.apply_side(lh)
	minimap.apply_side(lh)
	attacks.apply_side(lh)
	bottom_bar.apply_side(lh)
	build_menu.apply_side(lh)


func send_fraction() -> float:
	return bottom_bar.send_fraction


func set_mode_text(text: String) -> void:
	_mode_label.text = text
	_mode_label.visible = text != ""


func set_menu_open(open: bool) -> void:
	if open:
		close_panels()
		menu.open()
	else:
		menu.visible = false
	menu_toggled.emit(open)


func close_panels() -> void:
	build_menu.close()
	keep_panel.visible = false
	enemy_panel.visible = false


func any_panel_open() -> bool:
	return build_menu.visible or keep_panel.visible or enemy_panel.visible or menu.visible


func update_from_state(camera_view: Rect2) -> void:
	if _sim == null:
		return
	var state: GameState = _sim.state
	var local: Player = state.get_player(_sim.local_player_id)
	top_bar.refresh(_sim, local)
	leaderboard.refresh(_sim, local)
	attacks.refresh(_sim, local)
	bottom_bar.refresh(_sim, local)
	keep_panel.refresh(_sim, local)
	enemy_panel.refresh(_sim, local)
	end_overlay.refresh(_sim, local)
	minimap.set_view(camera_view)
	# Panels are modal: banners and tips step aside until they close.
	var modal: bool = any_panel_open() or end_overlay.visible
	banners.visible = not modal
	hints.suppressed = modal
	_placement_label.visible = state.phase == Balance.PHASE_PLACEMENT
	if _placement_label.visible:
		_placement_label.text = "Tap a plains, forest or hill tile to place your Crown  (%ds)" % maxi(0, ceili(state.placement_time_left))
	_offer_hints(state, local)


func _offer_hints(state: GameState, local: Player) -> void:
	if local == null or not local.is_alive:
		return
	var t: float = state.match_time
	if state.phase == Balance.PHASE_PLACEMENT:
		hints.offer("place")
	elif t < 20.0:
		hints.offer("expand")
	elif t < 45.0:
		hints.offer("sweet_spot")
	elif t >= Balance.PEACE_PERIOD_SEC and t < Balance.PEACE_PERIOD_SEC + 20.0:
		hints.offer("attack")
	elif t >= 85.0 and t < 110.0:
		hints.offer("build")
	elif t >= 120.0 and t < 140.0:
		hints.offer("spy")
	elif t >= 150.0 and t < 170.0 and not state.shrines.is_empty():
		hints.offer("shrine")
	elif t >= 190.0 and t < 210.0:
		hints.offer("crown")
