extends Node2D

# Root of the game scene. Plays a match through a GameSession (local or
# online), turns taps into commands, and hands match events to GameFeel
# (banners, sounds, vibration, screen shake). Starting and joining matches
# lives in PlayModes.

const SLOW_MO_SCALE: float = 0.35
const SLOW_MO_REAL_SEC: float = 0.5

@onready var _map: Map = $Map
@onready var _overlay: MapOverlay = $MapOverlay
@onready var _hud: HUD = $HUD
@onready var _camera: CameraRig = $Camera2D
@onready var _input: MapInput = $MapInput
@onready var _audio: GameAudio = $Audio
@onready var _modes: PlayModes = $PlayModes

var _session: GameSession
var _slow_mo_left: float = 0.0
# Tap-target modes: "", "wall", "bombard", "boat", "crown_move".
var _mode: String = ""
var _boat_port: Vector2i = Vector2i(-1, -1)
var _last_wall_tile: Vector2i = Vector2i(-1, -1)
var _colorblind_shown: bool = false


func _ready() -> void:
	_input.tapped.connect(_on_tap)
	_input.long_pressed.connect(_on_long_press)
	_input.dragged.connect(_on_drag)
	_input.pinched.connect(func(f: float, c: Vector2) -> void: _camera.zoom_by(f, c))
	_input.wheel_zoomed.connect(func(f: float, p: Vector2) -> void: _camera.zoom_by(f, p))
	_hud.command.connect(func(cmd: String, args: Array) -> void: _send(cmd, args))
	_hud.crown_jump_requested.connect(_jump_home)
	_hud.minimap_jump.connect(func(p: Vector2) -> void: _camera.jump_to(p))
	_hud.ability_became_ready.connect(_on_ability_ready)
	_hud.target_mode_requested.connect(_set_mode)
	_hud.menu_toggled.connect(func(open: bool) -> void:
		if _session != null:
			_session.paused = open)
	_modes.session_changed.connect(_on_session_changed)
	Settings.changed.connect(_on_settings_changed)
	_colorblind_shown = Settings.colorblind
	_modes.setup(_hud)


func _on_session_changed(session: GameSession) -> void:
	_session = session
	if _session != null:
		_session.match_ready.connect(_on_match_ready)


# A new match is ready to draw (local start, or the host's first update).
func _on_match_ready() -> void:
	var cur: Simulation = _session.sim()
	_map.setup(cur.state)
	_overlay.setup(cur.state, cur.local_player_id)
	_hud.setup(cur, _map.texture())
	_hud.menu.set_online(_session.online)
	_camera.fit_world(_map.world_size())
	_set_mode("", Vector2i.ZERO)
	Engine.time_scale = 1.0
	_audio.set_siege_music(false)


func _process(delta: float) -> void:
	_update_slow_mo(delta)
	if _session == null:
		return
	var events: Array = _session.update(delta)
	if _session == null or _session.sim() == null:
		return
	for e: Dictionary in events:
		GameFeel.handle(self, e)
	_map.render()
	_hud.update_from_state(_camera.visible_world_rect())


# Slow motion uses Engine.time_scale, so it is timed in real seconds.
func _update_slow_mo(delta: float) -> void:
	if _slow_mo_left <= 0.0:
		return
	_slow_mo_left -= delta / maxf(Engine.time_scale, 0.01)
	if _slow_mo_left <= 0.0:
		Engine.time_scale = 1.0


func _notification(what: int) -> void:
	# Android back button: close a panel, else open the menu, else (on the
	# start screen) leave the app.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and _hud != null:
		if _hud.start_menu.visible:
			get_tree().quit()
		elif _hud.any_panel_open():
			_hud.close_panels()
			_hud.set_menu_open(false)
		else:
			_hud.set_menu_open(true)
		return
	# Pause (or, online, open the menu) when the app goes to the background.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _hud != null and _session != null and _session.sim() != null \
				and _session.sim().state.phase == Balance.PHASE_MATCH:
			_hud.set_menu_open(true)


func _send(cmd: String, args: Array, on_result: Callable = Callable()) -> void:
	if _session == null:
		return
	_session.send(cmd, args, func(ok: bool) -> void:
		if ok:
			_audio.play("tap", -6.0)
		if on_result.is_valid():
			on_result.call(ok))


# --- Input --------------------------------------------------------------------

func _on_tap(screen_pos: Vector2) -> void:
	if _session == null or _session.sim() == null or _hud.start_menu.visible:
		return
	if _hud.any_panel_open():
		_hud.close_panels()
		return
	var cur: Simulation = _session.sim()
	var state: GameState = cur.state
	var tile: Vector2i = _screen_to_tile(screen_pos)
	if state.phase == Balance.PHASE_PLACEMENT:
		if tile.x >= 0:
			_send("place_crown", [tile.x, tile.y], func(ok: bool) -> void:
				if ok:
					_hud.hints.done("place")
					_jump_home())
		return
	if state.phase != Balance.PHASE_MATCH:
		return
	if tile.x < 0:
		_set_mode("", Vector2i.ZERO)
		return
	if _mode != "":
		_tap_in_mode(tile)
		return
	var local: Player = state.get_player(cur.local_player_id)
	if local != null and local.crown_x >= 0 and absi(tile.x - local.crown_x) <= 1 and absi(tile.y - local.crown_y) <= 1:
		_hud.keep_panel.visible = true
		return
	var owner_id: int = state.owners[state.idx(tile.x, tile.y)]
	var frac: float = _hud.send_fraction()
	if not state.is_player_owner(owner_id):
		_send("expand", [tile.x, tile.y, frac], func(ok: bool) -> void:
			if ok:
				_audio.play("expand")
				_hud.hints.done("expand"))
	elif owner_id != local.id:
		_send("attack", [tile.x, tile.y, frac], func(ok: bool) -> void:
			if ok:
				_audio.play("attack")
				_hud.hints.done("attack")
			elif state.is_peace():
				_hud.banners.push_text("Peace — no attacks until %s" % GameState.format_time(Balance.PEACE_PERIOD_SEC), UI.COLOR_WARN, 2.0))


func _tap_in_mode(tile: Vector2i) -> void:
	var cur: Simulation = _session.sim()
	match _mode:
		"wall":
			_send("build_wall", [tile.x, tile.y])
			return            # wall mode stays on until tapped off the map or toggled
		"bombard":
			_send("ability", [AbilitiesOps.ID_BOMBARD, tile.x, tile.y], func(ok: bool) -> void:
				if not ok:
					_hud.banners.push_text("Bombard target must be within %d tiles of your border" % Balance.BOMBARD_RANGE_TILES, UI.COLOR_WARN, 2.5))
		"boat":
			_send("launch_boat", [_boat_port.x, _boat_port.y, tile.x, tile.y, _hud.send_fraction()], func(ok: bool) -> void:
				if not ok:
					_hud.banners.push_text("No sea route there (max %d tiles of water)" % Balance.BOAT_RANGE_TILES, UI.COLOR_WARN, 2.5))
		"crown_move":
			var local: Player = cur.state.get_player(cur.local_player_id)
			var why: String = MatchOps.crown_move_blocker(cur, local, tile.x, tile.y)
			if why != "":
				_hud.banners.push_text("Can't move there: %s" % why, UI.COLOR_WARN, 2.5)
				return
			_send("move_crown", [tile.x, tile.y])
	_set_mode("", Vector2i.ZERO)


func _on_long_press(screen_pos: Vector2) -> void:
	if _session == null or _session.sim() == null:
		return
	var cur: Simulation = _session.sim()
	var state: GameState = cur.state
	var tile: Vector2i = _screen_to_tile(screen_pos)
	if tile.x < 0 or state.phase != Balance.PHASE_MATCH or _mode != "":
		return
	var local: Player = state.get_player(cur.local_player_id)
	if local == null or not local.is_alive:
		return
	_hud.close_panels()
	var owner_id: int = state.owners[state.idx(tile.x, tile.y)]
	Settings.vibrate(15)
	if owner_id == local.id:
		_hud.build_menu.open_at(cur, local, tile.x, tile.y)
		_hud.hints.done("build")
	elif state.is_player_owner(owner_id):
		_hud.enemy_panel.open_for(owner_id)
		_hud.hints.done("spy")


func _on_drag(screen_pos: Vector2, relative: Vector2) -> void:
	if _mode == "wall":
		var tile: Vector2i = _screen_to_tile(screen_pos)
		if tile.x >= 0 and tile != _last_wall_tile:
			_last_wall_tile = tile
			_send("build_wall", [tile.x, tile.y])
		return
	_camera.pan_screen(relative)


func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var state: GameState = _session.sim().state
	var world := _camera.screen_to_world(screen_pos)
	if world.x < 0.0 or world.y < 0.0 or world.x >= float(state.width) or world.y >= float(state.height):
		return Vector2i(-1, -1)
	return Vector2i(int(world.x), int(world.y))


func _set_mode(mode: String, data: Vector2i) -> void:
	# Pressing wall mode again turns it off.
	if mode == "wall" and _mode == "wall":
		mode = ""
	_mode = mode
	_boat_port = data if mode == "boat" else Vector2i(-1, -1)
	_last_wall_tile = Vector2i(-1, -1)
	match mode:
		"wall":
			_hud.set_mode_text("Wall mode — tap or drag your land (tap outside the map to stop)")
		"bombard":
			_hud.set_mode_text("Bombard — tap a target within %d tiles of your border" % Balance.BOMBARD_RANGE_TILES)
		"boat":
			_hud.set_mode_text("Boat — tap a coast across the water")
		"crown_move":
			_hud.set_mode_text("Move Crown — tap your own land %d+ tiles from any enemy" % Balance.CROWN_MOVE_MIN_DIST_FROM_ENEMY)
		_:
			_hud.set_mode_text("")


func _jump_home() -> void:
	if _session == null or _session.sim() == null:
		return
	var cur: Simulation = _session.sim()
	var local: Player = cur.state.get_player(cur.local_player_id)
	if local != null and local.crown_x >= 0:
		_camera.jump_to(Vector2(local.crown_x + 0.5, local.crown_y + 0.5))


func _on_ability_ready(_ability_id: int) -> void:
	_audio.play("ability_ready", -4.0)
	Settings.vibrate(30)


func _on_settings_changed() -> void:
	if Settings.colorblind != _colorblind_shown:
		_colorblind_shown = Settings.colorblind
		if _session != null and _session.sim() != null:
			_map.repaint_all()


# Small accessors GameFeel uses (keeps that file free of node paths).
func sim() -> Simulation:
	return _session.sim()


func hud() -> HUD:
	return _hud


func audio() -> GameAudio:
	return _audio


func camera() -> CameraRig:
	return _camera


func overlay() -> MapOverlay:
	return _overlay


# Slow motion only offline: online, the match keeps running on the host.
func start_slow_mo() -> void:
	if _session != null and _session.online:
		return
	Engine.time_scale = SLOW_MO_SCALE
	_slow_mo_left = SLOW_MO_REAL_SEC
