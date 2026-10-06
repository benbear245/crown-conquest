extends Node2D

# Root of the game scene. Owns the Simulation, drives it at fixed ticks,
# tells the Map to render dirty tiles, and routes gestures (TouchInput) into
# the sim, the HUD panels or the camera. Targeting modes (walls, boats,
# Bombard, Crown move) live in Targeting. The match settings come from the
# menus (Session.config); the pause menu pauses the whole tree.

const MAX_TICKS_PER_FRAME: int = 5

@onready var _map: Map = $Map
@onready var _overlay: WorldOverlay = $Overlay
@onready var _hud: HUD = $HUD
@onready var _camera: CameraRig = $Camera2D
@onready var _feel: GameFeel = $GameFeel

# Pause automatically when the app goes to the background (tests turn it off).
var auto_pause: bool = true
var _simulation: Simulation
var _config: MatchConfig
var _result_recorded: bool = false
var _tracker: MatchTracker
var _tutorial: Tutorial
var _match_achievements: Array[String] = []   # earned this match (shown at the end)
var _targeting: Targeting
var _touch: TouchInput = TouchInput.new()
var _tick_accumulator: float = 0.0
var _was_in_sweet_spot: bool = false


func _ready() -> void:
	_simulation = Simulation.new()
	_config = Session.current_config()
	_simulation.start_with(_config, _config.next_seed())
	_targeting = Targeting.new(_simulation, _hud, _overlay)
	_touch.tapped.connect(_on_tap)
	_touch.long_pressed.connect(_on_long_press)
	_touch.drag_started.connect(_on_drag_started)
	_touch.dragged.connect(_on_drag)
	_touch.pinched.connect(func(f: float, c: Vector2) -> void: _camera.zoom_at(f, c); _hud.hint("pan_zoom"))
	_hud.pause_requested.connect(pause_game)
	_hud.pause_menu.resume_pressed.connect(resume_game)
	_hud.pause_menu.restart_pressed.connect(_start_new_match)
	_hud.pause_menu.quit_pressed.connect(_quit_to_menu)
	_hud.end_overlay.play_again_pressed.connect(_start_new_match)
	_hud.end_overlay.menu_pressed.connect(_quit_to_menu)
	_hud.ally_panel.send_pressed.connect(func() -> void: _simulation.player_send_to_ally(_simulation.local_player_id))
	_hud.jump_to_crown_pressed.connect(_jump_to_crown)
	_hud.jump_to_world.connect(func(w: Vector2) -> void: _camera.look_at_tile(Vector2i(w)))
	_hud.build_menu.build_requested.connect(_on_build_requested)
	_hud.build_menu.wall_mode_requested.connect(func() -> void: _targeting.enter(Targeting.Mode.WALL); _hud.hint("wall"))
	_hud.build_menu.boat_requested.connect(func(x: int, y: int) -> void: _targeting.enter_boat(Vector2i(x, y)); _hud.hint("boat"))
	_hud.keep_panel.buy_keep_requested.connect(func(lvl: int) -> void: _simulation.player_buy_keep(_simulation.local_player_id, lvl))
	_hud.keep_panel.move_crown_requested.connect(func() -> void: _targeting.enter(Targeting.Mode.CROWN_MOVE))
	_hud.ability_bar.ability_pressed.connect(_on_ability_pressed)
	_hud.enemy_panel.offer_truce_requested.connect(_on_offer_truce)
	_hud.truce_panel.respond.connect(func(from_id: int, ok: bool) -> void: _simulation.player_respond_truce(_simulation.local_player_id, from_id, ok))
	Settings.changed.connect(_on_settings_changed)
	_bind_match()


func _bind_match() -> void:
	_apply_cosmetics()
	_map.setup(_simulation.state)
	_overlay.state = _simulation.state
	_overlay.local_player_id = _simulation.local_player_id
	_hud.setup(_simulation, _map)
	_camera.fit_to_world(_map.world_size())
	_feel.setup(_simulation, _camera)
	_tracker = MatchTracker.new(_simulation)
	_match_achievements.clear()
	_result_recorded = false
	_targeting.exit()
	_setup_tutorial()
	_hud.hint("placement")


func _process(delta: float) -> void:
	# Slow motion (a Crown just fell) only slows the simulation clock.
	_tick_accumulator += delta * _feel.time_scale()
	var ticks_this_frame: int = 0
	while _tick_accumulator >= Balance.TICK_DELTA and ticks_this_frame < MAX_TICKS_PER_FRAME:
		_tick_accumulator -= Balance.TICK_DELTA
		_simulation.advance_tick()
		ticks_this_frame += 1
	if ticks_this_frame == MAX_TICKS_PER_FRAME:
		_tick_accumulator = 0.0
	_feel.consume(_simulation.state.events)
	_hud.consume_events(_simulation.state.events)
	_observe_achievements(_simulation.state.events)
	_simulation.state.events.clear()
	_map.render()
	_record_result_once()
	_hud.update_from_state()
	_sync_overlay()
	_watch_local_player()
	_touch.process(delta)
	_hud.set_long_press(_touch.press_position(), _touch.long_press_progress() if _simulation.state.phase == Balance.PHASE_MATCH else -1.0)


func _sync_overlay() -> void:
	var sel: Vector2i = _hud.build_menu.selected_tile()
	_overlay.selected_tile = sel
	_overlay.selected_radius = 0
	if sel.x >= 0:
		var b: Building = _simulation.state.building_at_tile.get(_simulation.state.idx(sel.x, sel.y), null)
		_overlay.selected_radius = b.radius() if b != null and b.radius() > 0 else Balance.FORT_RADIUS
	_targeting.sync_overlay()


# Tip about the sweet spot (Crown alarm sound/vibration live in GameFeel).
func _watch_local_player() -> void:
	var me: Player = _simulation.state.get_player(_simulation.local_player_id)
	if me != null and me.is_alive and _simulation.state.phase == Balance.PHASE_MATCH:
		var ratio: float = me.troops / maxf(me.troop_cap(), 1.0)
		var sweet: bool = ratio >= Balance.TROOP_BAR_SWEET_LOW and ratio <= Balance.TROOP_BAR_SWEET_HIGH
		if sweet and not _was_in_sweet_spot:
			_hud.hint("sweet_spot")
		_was_in_sweet_spot = sweet


# --- Gestures ------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _touch.handle(event):
		get_viewport().set_input_as_handled()


func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var world: Vector2 = get_canvas_transform().affine_inverse() * screen_pos
	var st: GameState = _simulation.state
	if world.x < 0.0 or world.y < 0.0 or world.x >= float(st.width) or world.y >= float(st.height):
		return Vector2i(-1, -1)
	return Vector2i(int(world.x), int(world.y))


func _on_drag_started(press_pos: Vector2) -> void:
	if _targeting.mode == Targeting.Mode.WALL:
		_targeting.begin_wall_stroke()
		_targeting.paint_wall_to(_screen_to_tile(press_pos))


func _on_drag(pos: Vector2, relative: Vector2) -> void:
	if _targeting.mode == Targeting.Mode.WALL:
		_targeting.paint_wall_to(_screen_to_tile(pos))
		return
	_camera.pan_screen(relative)
	_hud.hint("pan_zoom")


func _on_long_press(screen_pos: Vector2) -> void:
	var tile: Vector2i = _screen_to_tile(screen_pos)
	var st: GameState = _simulation.state
	if tile.x < 0 or st.phase != Balance.PHASE_MATCH or _targeting.is_active():
		return
	_hud.close_panels()
	var owner_id: int = st.owners[st.idx(tile.x, tile.y)]
	if owner_id == _simulation.local_player_id:
		Settings.vibrate(25)
		_hud.build_menu.open_at(tile)
		_hud.hint("long_press_own")
	elif owner_id > 0 and owner_id != GameState.RUINS_OWNER_ID:
		Settings.vibrate(25)
		_hud.enemy_panel.open_for(owner_id)
		_hud.hint("long_press_enemy")


func _on_tap(screen_pos: Vector2) -> void:
	var tile: Vector2i = _screen_to_tile(screen_pos)
	if tile.x < 0:
		return
	var st: GameState = _simulation.state
	if st.phase == Balance.PHASE_PLACEMENT:
		_simulation.player_place_crown(_simulation.local_player_id, tile.x, tile.y)
		return
	if st.phase != Balance.PHASE_MATCH:
		return
	# A tap on the map closes any open panel first.
	if _hud.any_panel_open():
		_hud.close_panels()
		return
	if _targeting.is_active():
		_targeting.tap(tile)
	else:
		_tap_normal(tile)


func _tap_normal(tile: Vector2i) -> void:
	var st: GameState = _simulation.state
	var me: Player = st.get_player(_simulation.local_player_id)
	if me == null or not me.is_alive:
		return
	var ti: int = st.idx(tile.x, tile.y)
	var owner_id: int = st.owners[ti]
	if owner_id == me.id:
		if me.crown_x >= 0 and absi(tile.x - me.crown_x) <= 1 and absi(tile.y - me.crown_y) <= 1:
			_hud.keep_panel.open_panel()
			_hud.hint("keep")
			return
		var b: Building = st.building_at_tile.get(ti, null)
		if b != null and b.type == Balance.BUILDING_PORT:
			_targeting.enter_boat(tile)
			_hud.hint("boat")
		return
	var frac: float = _hud.send_fraction()
	if me.ally_id > 0 and owner_id == me.ally_id:
		_hud.alerts.push("That's your ally — allies can't attack each other.", "info", 2.5, "ally_tap")
		return
	if owner_id == 0 or owner_id == GameState.RUINS_OWNER_ID:
		if _simulation.player_expand(me.id, tile.x, tile.y, frac):
			_hud.hint("expand")
	elif TrucesOps.has_truce(me, owner_id, st.match_time):
		_targeting.confirm_truce_break(tile, frac, st.get_player(owner_id))
	elif _simulation.player_attack(me.id, tile.x, tile.y, frac):
		_hud.hint("attack")


# --- HUD actions -------------------------------------------------------------

func _on_build_requested(type: int, x: int, y: int) -> void:
	var id: int = _simulation.local_player_id
	match type:
		Balance.BUILDING_FORT:
			_simulation.player_build_fort(id, x, y)
		Balance.BUILDING_FORT2:
			_simulation.player_upgrade_fort(id, x, y)
		Balance.BUILDING_BARRACKS:
			_simulation.player_build_barracks(id, x, y)
		Balance.BUILDING_PORT:
			_simulation.player_build_port(id, x, y)


func _on_offer_truce(target_id: int) -> void:
	if _simulation.player_offer_truce(_simulation.local_player_id, target_id):
		_hud.hint("truce")


func _on_ability_pressed(ability_id: int) -> void:
	var pid: int = _simulation.local_player_id
	match ability_id:
		AbilitiesOps.ID_SWIFT_MARCH:
			_simulation.player_activate_swift_march(pid)
		AbilitiesOps.ID_CROWN_SHIELD:
			_simulation.player_activate_crown_shield(pid)
		AbilitiesOps.ID_RALLY:
			_simulation.player_activate_rally(pid)
		AbilitiesOps.ID_BOMBARD:
			_targeting.enter(Targeting.Mode.BOMBARD)
			_hud.hint("bombard")


func _jump_to_crown() -> void:
	var me: Player = _simulation.state.get_player(_simulation.local_player_id)
	if me != null and me.crown_x >= 0:
		_camera.look_at_tile(Vector2i(me.crown_x, me.crown_y))


func _start_new_match() -> void:
	get_tree().paused = false
	_hud.pause_menu.close()
	_simulation.start_with(_config, _config.next_seed())
	_hud.end_overlay.reset()
	_bind_match()


func _quit_to_menu() -> void:
	var screen: String = "daily" if _config.mode == MatchConfig.Mode.DAILY else ""
	Session.to_menu(screen)


# --- Pause -------------------------------------------------------------------

func pause_game() -> void:
	if get_tree().paused:
		return
	_targeting.exit()
	_hud.close_panels()
	get_tree().paused = true
	var subtitle: String = _config.describe()
	if _config.mode == MatchConfig.Mode.DAILY:
		subtitle = "Daily Challenge " + _config.daily_date
	elif _config.mode == MatchConfig.Mode.TUTORIAL:
		subtitle = "Tutorial"
	_hud.pause_menu.open(subtitle)


func resume_game() -> void:
	_hud.pause_menu.close()
	get_tree().paused = false
	_tick_accumulator = 0.0


# The game pauses when the app goes to the background (or loses focus).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if auto_pause and _simulation != null and _simulation.state.phase != Balance.PHASE_ENDED and not get_tree().paused:
			pause_game()


func _unhandled_key_input(event: InputEvent) -> void:
	# Android back button / Escape opens the pause menu (or closes it).
	if event.is_action_pressed("ui_cancel"):
		if get_tree().paused:
			resume_game()
		else:
			pause_game()
		get_viewport().set_input_as_handled()


# --- Results -------------------------------------------------------------------

# Once per match, when it's over for you (you won, lost, or your Crown fell):
# the Daily Challenge score is saved.
func _record_result_once() -> void:
	if _result_recorded:
		return
	var st: GameState = _simulation.state
	var me: Player = st.get_player(_simulation.local_player_id)
	var over_for_me: bool = st.phase == Balance.PHASE_ENDED or (me != null and not me.is_alive and not _team_still_alive(me))
	if not over_for_me:
		return
	_result_recorded = true
	if _mode() == MatchConfig.Mode.TUTORIAL:
		return
	var summary: Dictionary = SaveData.record_match(_tracker.result())
	for id: String in summary.new_achievements:
		_match_achievements.append(id)
		_hud.show_achievement(id)
	_hud.end_overlay.show_progress(summary, _match_achievements)
	if _mode() == MatchConfig.Mode.DAILY:
		var score: int = _simulation.daily_score()
		var bonus: int = _simulation.daily_time_bonus()
		var new_best: bool = SaveData.submit_daily(_config.daily_date, score)
		var text: String = "Daily score %d  (peak land %d + time bonus %d)" % [score, score - bonus, bonus]
		text += "\nNew best today!" if new_best else "\nBest today: %d" % SaveData.daily_best(_config.daily_date)
		_hud.end_overlay.extra_text = text


# The tutorial runs only in tutorial matches.
func _setup_tutorial() -> void:
	if _mode() == MatchConfig.Mode.TUTORIAL:
		if _tutorial == null:
			_tutorial = Tutorial.new()
			add_child(_tutorial)
		_tutorial.setup(self, _simulation, _hud, _camera)
	elif _tutorial != null:
		_tutorial.teardown()
		_tutorial.queue_free()
		_tutorial = null


# The mode of the match being played (Skirmish when started without a config).
func _mode() -> int:
	return _simulation.config.mode if _simulation.config != null else MatchConfig.Mode.SKIRMISH


# Achievements that can happen mid-match (Kingslayer, Siege Lord) pop up
# right away.
func _observe_achievements(events: Array) -> void:
	if _tracker == null or _mode() == MatchConfig.Mode.TUTORIAL:
		return
	for id: String in _tracker.observe(events):
		if SaveData.unlock_achievement(id):
			_match_achievements.append(id)
			_hud.show_achievement(id)


# Your colour, pattern and Crown icon from Customize.
func _apply_cosmetics() -> void:
	Palette.configure(_simulation.local_player_id, SaveData.custom_color(), _simulation.state.players.size())
	var pattern: int = int(SaveData.cosmetic("pattern"))
	_map.pattern = pattern if SaveData.pattern_unlocked(pattern) else 0
	_map.pattern_owner = _simulation.local_player_id
	var crown: int = int(SaveData.cosmetic("crown"))
	_overlay.local_crown_style = crown if SaveData.crown_unlocked(crown) else 0


func _team_still_alive(me: Player) -> bool:
	var ally: Player = _simulation.ally_of(me)
	return ally != null and ally.is_alive and _simulation.state.phase != Balance.PHASE_ENDED


func _on_settings_changed() -> void:
	if _map.uses_colorblind() != Settings.colorblind:
		_map.repaint_all()

