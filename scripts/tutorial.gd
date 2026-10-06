class_name Tutorial
extends Node

# The interactive tutorial (MatchConfig.Mode.TUTORIAL): a small map, one Easy
# bot, no timers. One step at a time; each waits until you've done it, and
# an arrow points at what to tap. Skip leaves at any time.

enum Step { PLACE, EXPAND, SWEET_SPOT, ATTACK, FORT, SHIELD, CAPTURE, DONE, LOST }

const STEP_COUNT: int = 7
const EXPAND_TILES: int = 25            # grow this many tiles to finish "expand"
const SWEET_MIN_SEC: float = 3.0        # read time before the sweet-spot step can pass

var step: int = Step.PLACE
var _game: Node
var _sim: Simulation
var _hud: HUD
var _camera: CameraRig
var card: TutorialCard
var arrow: TutorialArrow
var _step_time: float = 0.0
var _step_land: int = 0
var _spot: Vector2i = Vector2i(-1, -1)
var _target_tick: int = -100        # sim tick the arrow was last aimed on
var _target_world: Vector2i = Vector2i(-1, -1)


func setup(game: Node, sim: Simulation, hud: HUD, camera: CameraRig) -> void:
	_game = game
	_sim = sim
	_hud = hud
	_camera = camera
	if card == null:
		card = TutorialCard.new()
		card.skip_pressed.connect(_skip)
		card.menu_pressed.connect(func() -> void: _finish(); Session.to_menu())
		card.primary_pressed.connect(_on_primary)
		arrow = TutorialArrow.new()
		_hud.add_tutorial(card, arrow)
	step = Step.PLACE
	_spot = _suggest_spot()
	_enter(Step.PLACE)


func _process(delta: float) -> void:
	if _sim == null:
		return
	_step_time += delta
	var st: GameState = _sim.state
	var me: Player = st.get_player(_sim.local_player_id)
	var bot: Player = _bot()
	if step < Step.DONE and st.phase == Balance.PHASE_ENDED:
		_enter(Step.DONE if _sim.local_won() else Step.LOST)
	elif step < Step.DONE and me != null and not me.is_alive:
		_enter(Step.LOST)
	match step:
		Step.PLACE:
			if me.crown_x >= 0:
				_enter(Step.EXPAND)
		Step.EXPAND:
			if me.land >= _step_land + EXPAND_TILES:
				_enter(Step.SWEET_SPOT)
		Step.SWEET_SPOT:
			var ratio: float = me.troops / maxf(me.troop_cap(), 1.0)
			if _step_time >= SWEET_MIN_SEC and ratio >= Balance.TROOP_BAR_SWEET_LOW and ratio <= Balance.TROOP_BAR_SWEET_HIGH:
				_enter(Step.ATTACK)
		Step.ATTACK:
			if not _sim.attacks_by(me.id).is_empty():
				_enter(Step.FORT)
		Step.FORT:
			if int(me.buildings_built.get(Balance.BUILDING_FORT, 0)) > 0:
				_enter(Step.SHIELD)
		Step.SHIELD:
			if int(me.abilities_used.get(AbilitiesOps.ID_CROWN_SHIELD, 0)) > 0:
				_enter(Step.CAPTURE)
	_update_text(me, bot)
	_update_arrow(me, bot)


func _enter(s: int) -> void:
	step = s
	_step_time = 0.0
	var me: Player = _sim.state.get_player(_sim.local_player_id)
	_step_land = me.land if me != null else 0
	_target_tick = -100
	if s > Step.PLACE:
		Audio.play("sfx_ability_ready", -6.0)
	var bot: Player = _bot()
	match s:
		Step.CAPTURE:
			if bot != null and bot.crown_x >= 0:
				_camera.look_at_tile(Vector2i(bot.crown_x, bot.crown_y))
		Step.DONE:
			_finish()
			Audio.play("sfx_victory")
		Step.LOST:
			Audio.play("sfx_defeat")


func _update_text(me: Player, bot: Player) -> void:
	var st: GameState = _sim.state
	var n: String = "Tutorial · Step %d of %d" % [mini(step + 1, STEP_COUNT), STEP_COUNT]
	var t: String = ""
	match step:
		Step.PLACE:
			t = "Tap a spot on plains, forest or hills to place your Crown. The arrow shows a good spot near the bot."
		Step.EXPAND:
			t = "Tap free land next to your border to grow. Each tap sends troops (set how many with the Send slider). Grow by %d more tiles." % maxi(0, _step_land + EXPAND_TILES - me.land)
		Step.SWEET_SPOT:
			t = "Watch your troop bar: troops grow fastest while it glows green, in the sweet spot. Too empty or too full grows slowly. Wait until it's green."
		Step.ATTACK:
			if st.match_time < Balance.PEACE_PERIOD_SEC:
				t = "Next you'll attack the bot. Attacks open when the 1:00 peace period ends (%s left) — keep growing towards the bot meanwhile." % GameState.format_time(Balance.PEACE_PERIOD_SEC - st.match_time)
			elif _enemy_tile_next_to_me(me, bot) < 0:
				t = "Grow towards the bot until your land touches theirs, then tap their land to attack."
			else:
				t = "Tap the bot's land to attack it. Attacks cost more than free land, so send a good share."
		Step.FORT:
			var cost: int = int(BuildingsOps.fort_cost_for(me))
			t = "Long-press your own land near the bot (hold your finger down) to open the build menu, then tap Fort. Forts make the land around them much harder to take."
			if me.troops < cost:
				t += "  (A Fort costs %d troops — wait a moment.)" % cost
		Step.SHIELD:
			t = "When a big attack heads for your Crown, use Crown Shield: tap it at the bottom right. It blocks attacks on your Crown for a few seconds."
		Step.CAPTURE:
			t = "Last step: take the bot's Crown! Attack their land towards the gold Crown and capture its centre tile. Send 75–100% and keep pushing."
		Step.DONE:
			t = "You took the bot's Crown — tutorial complete! In a real match there are up to 11 rivals, more buildings and powers, and truces. Good luck!"
		Step.LOST:
			t = "The bot took your Crown this time. Try again?"
	match step:
		Step.DONE:
			card.show_step("Tutorial complete", t, true, "Play a Skirmish")
		Step.LOST:
			card.show_step("Tutorial", t, true, "Try again")
		_:
			card.show_step(n, t, false)


func _update_arrow(me: Player, bot: Player) -> void:
	# Re-aim every half second of game time (and right after a step change).
	var tick: int = _sim.state.tick_count
	if tick - _target_tick >= 5 or tick < _target_tick:
		_target_tick = tick
		_target_world = _world_target(me, bot)
	var screen := Vector2(-1, -1)
	arrow.ring_radius = 34.0
	match step:
		Step.SWEET_SPOT:
			var r: Rect2 = _hud.top_bar.troop_bar_rect()
			screen = Vector2(r.get_center().x, r.end.y + 8.0)
			arrow.ring_radius = 0.0
		Step.SHIELD:
			var b: Control = _hud.ability_bar.button(AbilitiesOps.ID_CROWN_SHIELD)
			screen = b.get_global_rect().get_center()
			arrow.ring_radius = 60.0
		Step.FORT:
			if _hud.build_menu.visible:
				var fb: Button = _hud.build_menu.row_button(BuildMenu.ROW_FORT)
				var fr: Rect2 = fb.get_global_rect()
				screen = Vector2(fr.end.x - 30.0, fr.get_center().y)
				arrow.ring_radius = 0.0
			elif _target_world.x >= 0:
				screen = _to_screen(_target_world)
		Step.DONE, Step.LOST:
			screen = Vector2(-1, -1)
		_:
			if _target_world.x >= 0:
				screen = _to_screen(_target_world)
	arrow.target = screen


func _world_target(me: Player, bot: Player) -> Vector2i:
	var st: GameState = _sim.state
	match step:
		Step.PLACE:
			return _spot
		Step.EXPAND:
			return _free_tile_towards(me, bot)
		Step.ATTACK:
			var ti: int = _enemy_tile_next_to_me(me, bot)
			if ti >= 0:
				return st.idx_to_xy(ti)
			return _free_tile_towards(me, bot)
		Step.FORT:
			return _my_tile_facing(me, bot)
		Step.CAPTURE:
			return Vector2i(bot.crown_x, bot.crown_y) if bot != null and bot.is_alive else Vector2i(-1, -1)
	return Vector2i(-1, -1)


func _to_screen(t: Vector2i) -> Vector2:
	return _game.get_viewport().canvas_transform * (Vector2(t) + Vector2(0.5, 0.5))


func _bot() -> Player:
	for p: Player in _sim.state.players:
		if p.id != _sim.local_player_id:
			return p
	return null


# A good Crown spot: not too far from the bot, so borders meet soon.
func _suggest_spot() -> Vector2i:
	var bot: Player = _bot()
	var st: GameState = _sim.state
	if bot != null and bot.crown_x < 0:
		_sim.advance_tick()   # let the bot place first (it does on the first tick)
		st.events.clear()
	if bot != null and bot.crown_x >= 0:
		var near: Vector2i = CrownsOps.find_valid_crown_position_near(st, bot.crown_x, bot.crown_y)
		if near.x >= 0:
			return near
	return CrownsOps.find_valid_crown_position(st)


# Your border tile closest to the bot's Crown, stepped onto free land.
func _free_tile_towards(me: Player, bot: Player) -> Vector2i:
	var st: GameState = _sim.state
	var goal := Vector2(bot.crown_x, bot.crown_y) if bot != null and bot.crown_x >= 0 else Vector2(st.width * 0.5, st.height * 0.5)
	var best := Vector2i(-1, -1)
	var best_d: float = INF
	for ti: int in me.border.keys():
		var xy: Vector2i = st.idx_to_xy(ti)
		for d: Vector2i in TerritoryOps.NEIGHBOR_OFFSETS:
			var n: Vector2i = xy + d
			if not st.in_bounds(n.x, n.y):
				continue
			var ni: int = st.idx(n.x, n.y)
			if st.owners[ni] != 0 or st.is_blocked_terrain(st.terrain[ni]):
				continue
			var dist: float = Vector2(n).distance_to(goal)
			if dist < best_d:
				best_d = dist
				best = n
	return best


func _enemy_tile_next_to_me(me: Player, bot: Player) -> int:
	if bot == null or not bot.is_alive:
		return -1
	var st: GameState = _sim.state
	var best: int = -1
	var best_d: float = INF
	for ti: int in me.border.keys():
		var xy: Vector2i = st.idx_to_xy(ti)
		for d: Vector2i in TerritoryOps.NEIGHBOR_OFFSETS:
			var n: Vector2i = xy + d
			if st.in_bounds(n.x, n.y) and st.owners[st.idx(n.x, n.y)] == bot.id:
				var dist: float = Vector2(n).distance_to(Vector2(me.crown_x, me.crown_y))
				if dist < best_d:
					best_d = dist
					best = st.idx(n.x, n.y)
	return best


# One of your own tiles on the side facing the bot (for the Fort).
func _my_tile_facing(me: Player, bot: Player) -> Vector2i:
	var st: GameState = _sim.state
	var goal := Vector2(bot.crown_x, bot.crown_y) if bot != null and bot.crown_x >= 0 else Vector2(me.crown_x, me.crown_y)
	var best := Vector2i(-1, -1)
	var best_d: float = INF
	for ti: int in me.border.keys():
		var xy: Vector2i = st.idx_to_xy(ti)
		# A few tiles back from the border, on buildable ground.
		var back: Vector2i = xy + Vector2i((Vector2(me.crown_x, me.crown_y) - Vector2(xy)).normalized() * 3.0)
		if not st.in_bounds(back.x, back.y) or st.owners[st.idx(back.x, back.y)] != me.id:
			continue
		if BuildingsOps.build_block_reason(_sim, me, Balance.BUILDING_FORT, st.idx(back.x, back.y)) != "" and me.troops >= BuildingsOps.fort_cost_for(me):
			continue
		var dist: float = Vector2(back).distance_to(goal)
		if dist < best_d:
			best_d = dist
			best = back
	return best


func teardown() -> void:
	_hud.remove_tutorial()
	card = null
	arrow = null
	_sim = null


func _on_primary() -> void:
	if step == Step.LOST:
		_game.call("_start_new_match")
	else:
		Session.to_menu("skirmish")


func _skip() -> void:
	_finish()
	Session.to_menu()


func _finish() -> void:
	SaveData.data.profile["tutorial_done"] = true
	SaveData.save()
