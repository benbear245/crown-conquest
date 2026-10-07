extends Node2D

# Root of the game scene. Owns the Simulation and drives it at fixed ticks,
# turns taps into commands, and hands sim events to GameFeel (banners,
# sounds, vibration, screen shake).

const SLOW_MO_SCALE: float = 0.35
const SLOW_MO_REAL_SEC: float = 0.5
const MAX_TICKS_PER_FRAME: int = 5

@onready var _map: Map = $Map
@onready var _overlay: MapOverlay = $MapOverlay
@onready var _hud: HUD = $HUD
@onready var _camera: CameraRig = $Camera2D
@onready var _input: MapInput = $MapInput
@onready var _audio: GameAudio = $Audio

var _simulation: Simulation
var _tick_accumulator: float = 0.0
var _paused: bool = false
var _slow_mo_left: float = 0.0
# Tap-target modes: "", "wall", "bombard", "boat", "crown_move".
var _mode: String = ""
var _boat_port: Vector2i = Vector2i(-1, -1)
var _last_wall_tile: Vector2i = Vector2i(-1, -1)
var _colorblind_shown: bool = false


func _ready() -> void:
	_simulation = Simulation.new()
	_input.tapped.connect(_on_tap)
	_input.long_pressed.connect(_on_long_press)
	_input.dragged.connect(_on_drag)
	_input.pinched.connect(func(f: float, c: Vector2) -> void: _camera.zoom_by(f, c))
	_input.wheel_zoomed.connect(func(f: float, p: Vector2) -> void: _camera.zoom_by(f, p))
	_hud.command.connect(_on_hud_command)
	_hud.crown_jump_requested.connect(_jump_home)
	_hud.minimap_jump.connect(func(p: Vector2) -> void: _camera.jump_to(p))
	_hud.ability_became_ready.connect(_on_ability_ready)
	_hud.target_mode_requested.connect(_set_mode)
	_hud.menu_toggled.connect(func(open: bool) -> void: _paused = open)
	_hud.new_map_requested.connect(_start_new_match)
	Settings.changed.connect(_on_settings_changed)
	_colorblind_shown = Settings.colorblind
	_start_new_match()


func _start_new_match() -> void:
	_simulation.start_default_match(_random_seed())
	_map.setup(_simulation.state)
	_overlay.setup(_simulation.state, _simulation.local_player_id)
	_hud.setup(_simulation, _map.texture())
	_camera.fit_world(_map.world_size())
	_set_mode("", Vector2i.ZERO)
	_paused = false
	Engine.time_scale = 1.0
	_audio.set_siege_music(false)


func _random_seed() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0) ^ randi()


func _process(delta: float) -> void:
	_update_slow_mo(delta)
	if not _paused:
		_tick_accumulator += delta
		var ticks := 0
		while _tick_accumulator >= Balance.TICK_DELTA and ticks < MAX_TICKS_PER_FRAME:
			_tick_accumulator -= Balance.TICK_DELTA
			_simulation.advance_tick()
			ticks += 1
		if ticks == MAX_TICKS_PER_FRAME:
			_tick_accumulator = 0.0
	_drain_events()
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
	# Pause when the app goes to the background.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _hud != null and _simulation != null and _simulation.state.phase == Balance.PHASE_MATCH:
			_hud.set_menu_open(true)


# --- Input --------------------------------------------------------------------

func _on_tap(screen_pos: Vector2) -> void:
	if _hud.any_panel_open():
		_hud.close_panels()
		return
	var tile: Vector2i = _screen_to_tile(screen_pos)
	var state: GameState = _simulation.state
	var me: int = _simulation.local_player_id
	if state.phase == Balance.PHASE_PLACEMENT:
		if tile.x >= 0 and _simulation.player_place_crown(me, tile.x, tile.y):
			_hud.hints.done("place")
			_jump_home()
		return
	if state.phase != Balance.PHASE_MATCH:
		return
	if tile.x < 0:
		_set_mode("", Vector2i.ZERO)
		return
	if _mode != "":
		_tap_in_mode(tile)
		return
	var local: Player = state.get_player(me)
	if local != null and local.crown_x >= 0 and absi(tile.x - local.crown_x) <= 1 and absi(tile.y - local.crown_y) <= 1:
		_hud.keep_panel.visible = true
		return
	var owner_id: int = state.owners[state.idx(tile.x, tile.y)]
	var frac: float = _hud.send_fraction()
	if not state.is_player_owner(owner_id):
		if _simulation.player_expand(me, tile.x, tile.y, frac):
			_audio.play("expand")
			_hud.hints.done("expand")
	elif owner_id != me:
		if _simulation.player_attack(me, tile.x, tile.y, frac):
			_audio.play("attack")
			_hud.hints.done("attack")
		elif state.is_peace():
			_hud.banners.push_text("Peace — no attacks until %s" % GameState.format_time(Balance.PEACE_PERIOD_SEC), UI.COLOR_WARN, 2.0)


func _tap_in_mode(tile: Vector2i) -> void:
	var me: int = _simulation.local_player_id
	match _mode:
		"wall":
			_simulation.player_build_wall(me, tile.x, tile.y)
			return            # wall mode stays on until tapped off the map or toggled
		"bombard":
			if not _simulation.player_activate_ability(me, AbilitiesOps.ID_BOMBARD, tile.x, tile.y):
				_hud.banners.push_text("Bombard target must be within %d tiles of your border" % Balance.BOMBARD_RANGE_TILES, UI.COLOR_WARN, 2.5)
				return
		"boat":
			if not _simulation.player_launch_boat(me, _boat_port.x, _boat_port.y, tile.x, tile.y, _hud.send_fraction()):
				_hud.banners.push_text("No sea route there (max %d tiles of water)" % Balance.BOAT_RANGE_TILES, UI.COLOR_WARN, 2.5)
				return
		"crown_move":
			var local: Player = _simulation.state.get_player(me)
			var why: String = MatchOps.crown_move_blocker(_simulation, local, tile.x, tile.y)
			if why != "":
				_hud.banners.push_text("Can't move there: %s" % why, UI.COLOR_WARN, 2.5)
				return
			_simulation.player_move_crown(me, tile.x, tile.y)
	_set_mode("", Vector2i.ZERO)


func _on_long_press(screen_pos: Vector2) -> void:
	var tile: Vector2i = _screen_to_tile(screen_pos)
	var state: GameState = _simulation.state
	if tile.x < 0 or state.phase != Balance.PHASE_MATCH or _mode != "":
		return
	var local: Player = state.get_player(_simulation.local_player_id)
	if local == null or not local.is_alive:
		return
	_hud.close_panels()
	var owner_id: int = state.owners[state.idx(tile.x, tile.y)]
	Settings.vibrate(15)
	if owner_id == local.id:
		_hud.build_menu.open_at(_simulation, local, tile.x, tile.y)
		_hud.hints.done("build")
	elif state.is_player_owner(owner_id):
		_hud.enemy_panel.open_for(owner_id)
		_hud.hints.done("spy")


func _on_drag(screen_pos: Vector2, relative: Vector2) -> void:
	if _mode == "wall":
		var tile: Vector2i = _screen_to_tile(screen_pos)
		if tile.x >= 0 and tile != _last_wall_tile:
			_last_wall_tile = tile
			_simulation.player_build_wall(_simulation.local_player_id, tile.x, tile.y)
		return
	_camera.pan_screen(relative)


func _screen_to_tile(screen_pos: Vector2) -> Vector2i:
	var world := _camera.screen_to_world(screen_pos)
	if world.x < 0.0 or world.y < 0.0 or world.x >= float(_simulation.state.width) or world.y >= float(_simulation.state.height):
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
	var local: Player = _simulation.state.get_player(_simulation.local_player_id)
	if local != null and local.crown_x >= 0:
		_camera.jump_to(Vector2(local.crown_x + 0.5, local.crown_y + 0.5))


# --- HUD commands -------------------------------------------------------------

func _on_hud_command(cmd: String, args: Array) -> void:
	var me: int = _simulation.local_player_id
	var ok: bool = false
	match cmd:
		"retreat":
			ok = _simulation.player_retreat(me, int(args[0]))
		"build":
			ok = _simulation.player_build(me, int(args[0]), int(args[1]), int(args[2]))
		"upgrade_fort":
			ok = _simulation.player_upgrade_fort(me, int(args[0]), int(args[1]))
		"buy_keep":
			ok = _simulation.player_buy_keep(me, int(args[0]))
		"ability":
			ok = _simulation.player_activate_ability(me, int(args[0]))
		"offer_truce":
			ok = _simulation.player_offer_truce(me, int(args[0]))
			if ok:
				_hud.banners.push_text("Truce offered…", UI.COLOR_DIM, 2.0)
		"answer_truce":
			ok = _simulation.player_answer_truce(me, int(args[0]), bool(args[1]))
		"spy":
			ok = _simulation.player_spy(me, int(args[0]), int(args[1]))
		"disinformation":
			ok = _simulation.player_disinformation(me, bool(args[0]))
	if ok:
		_audio.play("tap", -6.0)


func _on_ability_ready(_ability_id: int) -> void:
	_audio.play("ability_ready", -4.0)
	Settings.vibrate(30)


func _on_settings_changed() -> void:
	if Settings.colorblind != _colorblind_shown:
		_colorblind_shown = Settings.colorblind
		_map.repaint_all()


# --- Sim events -> GameFeel ---------------------------------------------------

func _drain_events() -> void:
	var state: GameState = _simulation.state
	if state.events.is_empty():
		return
	var events: Array = state.events
	state.events = []
	for e: Dictionary in events:
		GameFeel.handle(self, e)


# Small accessors GameFeel uses (keeps that file free of node paths).
func sim() -> Simulation:
	return _simulation


func hud() -> HUD:
	return _hud


func audio() -> GameAudio:
	return _audio


func camera() -> CameraRig:
	return _camera


func overlay() -> MapOverlay:
	return _overlay


func start_slow_mo() -> void:
	Engine.time_scale = SLOW_MO_SCALE
	_slow_mo_left = SLOW_MO_REAL_SEC
