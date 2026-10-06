class_name Targeting
extends RefCounted

# Targeting modes that take over map taps: drawing walls, picking a boat's
# landing coast, aiming Bombard (preview + confirm) and moving the Crown.
# The mode banner shows a hint, live feedback, and Done / Cancel / Fire!.

enum Mode { NORMAL, WALL, BOAT, BOMBARD, CROWN_MOVE, BREAK_TRUCE }

var mode: int = Mode.NORMAL
var _sim: Simulation
var _hud: HUD
var _overlay: WorldOverlay
var _boat_port: Vector2i = Vector2i(-1, -1)
var _bombard_target: Vector2i = Vector2i(-1, -1)
var _wall_last_tile: Vector2i = Vector2i(-1, -1)
var _wall_line_tiles: int = 0
# Attack waiting for "Attack anyway" because it would break a truce.
var _pending_attack_tile: Vector2i = Vector2i(-1, -1)
var _pending_attack_frac: float = 0.5


func _init(sim: Simulation, hud: HUD, overlay: WorldOverlay) -> void:
	_sim = sim
	_hud = hud
	_overlay = overlay
	_hud.mode_banner.cancel_pressed.connect(exit)
	_hud.mode_banner.confirm_pressed.connect(_on_confirm)


func is_active() -> bool:
	return mode != Mode.NORMAL


func enter(new_mode: int) -> void:
	_hud.close_panels()
	mode = new_mode
	match new_mode:
		Mode.WALL:
			_wall_line_tiles = 0
			_hud.mode_banner.show_mode(_wall_text(), "Done")
		Mode.BOMBARD:
			_bombard_target = Vector2i(-1, -1)
			_hud.mode_banner.show_mode("Bombard: tap an enemy spot within %d tiles of your border to preview the area" % Balance.BOMBARD_RANGE_TILES, "Cancel", "Fire!")
			_hud.mode_banner.set_confirm_enabled(false)
		Mode.CROWN_MOVE:
			_hud.mode_banner.show_mode("Move Crown: tap your own land at least %d tiles from any enemy" % Balance.CROWN_MOVE_MIN_DIST_FROM_ENEMY)
		_:
			_hud.mode_banner.hide_mode()


func enter_boat(port: Vector2i) -> void:
	enter(Mode.BOAT)
	_boat_port = port
	_hud.mode_banner.show_mode("Boat: tap a free or enemy coast across the water (sends %d%%)" % int(round(_hud.send_fraction() * 100.0)))


# Attacking a truce partner breaks the truce, so ask first.
func confirm_truce_break(tile: Vector2i, fraction: float, partner: Player) -> void:
	enter(Mode.BREAK_TRUCE)
	_pending_attack_tile = tile
	_pending_attack_frac = fraction
	_hud.mode_banner.show_mode("Break your truce with %s? You become an Oathbreaker: attacks cost +%d%% for %ds, and bots refuse your truces for the rest of the match." % [
		partner.display_name, int(Balance.OATHBREAKER_ATTACK_PENALTY * 100.0), int(Balance.OATHBREAKER_DURATION_SEC)], "Cancel", "Attack anyway")
	_hud.mode_banner.set_confirm_enabled(true)


func exit() -> void:
	mode = Mode.NORMAL
	_pending_attack_tile = Vector2i(-1, -1)
	_boat_port = Vector2i(-1, -1)
	_bombard_target = Vector2i(-1, -1)
	_overlay.bombard_preview = Vector2i(-1, -1)
	_overlay.move_preview = Vector2i(-1, -1)
	_hud.mode_banner.hide_mode()


# Keeps the overlay previews in sync and drops out of a mode if the match ends.
func sync_overlay() -> void:
	_overlay.boat_port = _boat_port if mode == Mode.BOAT else Vector2i(-1, -1)
	if is_active() and _sim.state.phase != Balance.PHASE_MATCH:
		exit()


func tap(tile: Vector2i) -> void:
	match mode:
		Mode.WALL:
			paint_wall_to(tile)
		Mode.BOAT:
			_tap_boat_target(tile)
		Mode.BOMBARD:
			_preview_bombard(tile)
		Mode.CROWN_MOVE:
			_tap_crown_move(tile)
		Mode.BREAK_TRUCE:
			exit()   # tapping the map instead of confirming cancels


# --- Walls -------------------------------------------------------------------

func begin_wall_stroke() -> void:
	_wall_last_tile = Vector2i(-1, -1)


func _wall_text() -> String:
	var me: Player = _sim.state.get_player(_sim.local_player_id)
	var walls: int = me.wall_count if me != null else 0
	return "Wall mode: drag along your land.  This line: %d tiles · %d troops.  Walls %d/%d" % [
		_wall_line_tiles, int(float(_wall_line_tiles) * Balance.WALL_COST_PER_TILE), walls, Balance.WALL_LIMIT]


# Builds walls on every tile of the straight line from the last painted tile
# to `tile`, so a fast drag doesn't leave gaps.
func paint_wall_to(tile: Vector2i) -> void:
	if tile.x < 0:
		return
	if _wall_last_tile.x < 0:
		_wall_line_tiles = 0
	var from: Vector2i = _wall_last_tile if _wall_last_tile.x >= 0 else tile
	for t: Vector2i in line_tiles(from, tile):
		if t == _wall_last_tile:
			continue
		if _sim.player_build_wall(_sim.local_player_id, t.x, t.y):
			_wall_line_tiles += 1
	_wall_last_tile = tile
	_hud.mode_banner.set_text(_wall_text())


static func line_tiles(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dx: int = absi(b.x - a.x)
	var dy: int = -absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var err: int = dx + dy
	var p: Vector2i = a
	while true:
		out.append(p)
		if p == b:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			p.x += sx
		if e2 <= dx:
			err += dx
			p.y += sy
	return out


# --- Boats -------------------------------------------------------------------

func _tap_boat_target(tile: Vector2i) -> void:
	var me: Player = _sim.state.get_player(_sim.local_player_id)
	if me == null:
		return
	var path := PackedInt32Array()
	var reason: String = BoatsOps.launch_block_reason(_sim, me, _boat_port.x, _boat_port.y, tile.x, tile.y, path)
	if reason != "":
		_hud.mode_banner.set_text("Boat: %s — tap another coast" % reason)
		return
	_sim.player_launch_boat(me.id, _boat_port.x, _boat_port.y, tile.x, tile.y, _hud.send_fraction())
	exit()


# --- Bombard -----------------------------------------------------------------

# First tap shows the blast area; Fire! confirms. Tapping elsewhere moves it.
func _preview_bombard(tile: Vector2i) -> void:
	var me: Player = _sim.state.get_player(_sim.local_player_id)
	if me == null:
		return
	_bombard_target = tile
	var in_range: bool = AbilitiesOps.bombard_in_range(_sim, me, tile.x, tile.y)
	var hits: int = AbilitiesOps.bombard_enemy_tiles(_sim.state, me.id, tile.x, tile.y)
	_overlay.bombard_preview = tile
	_overlay.bombard_preview_ok = in_range and hits > 0
	if not in_range:
		_hud.mode_banner.set_text("Out of range — pick a spot within %d tiles of your border" % Balance.BOMBARD_RANGE_TILES)
	elif hits == 0:
		_hud.mode_banner.set_text("No enemy land there — tap enemy territory")
	else:
		_hud.mode_banner.set_text("Bombard here? Hits %d enemy tiles for %ds: half defense, -%d troops per tile each second. Costs %d troops." % [
			hits, int(Balance.BOMBARD_DURATION_SEC), int(Balance.BOMBARD_DAMAGE_PER_TILE_PER_SEC), int(AbilitiesOps.cost_now(AbilitiesOps.ID_BOMBARD, me))])
	_hud.mode_banner.set_confirm_enabled(in_range and hits > 0)


func _on_confirm() -> void:
	if mode == Mode.BOMBARD and _bombard_target.x >= 0:
		if _sim.player_activate_bombard(_sim.local_player_id, _bombard_target.x, _bombard_target.y):
			exit()
	elif mode == Mode.BREAK_TRUCE and _pending_attack_tile.x >= 0:
		_sim.player_attack(_sim.local_player_id, _pending_attack_tile.x, _pending_attack_tile.y, _pending_attack_frac)
		exit()


# --- Crown move --------------------------------------------------------------

func _tap_crown_move(tile: Vector2i) -> void:
	var me: Player = _sim.state.get_player(_sim.local_player_id)
	if me == null:
		return
	var reason: String = CrownsOps.move_block_reason(_sim, me, tile.x, tile.y)
	_overlay.move_preview = tile
	_overlay.move_preview_ok = reason == ""
	if reason != "":
		_hud.mode_banner.set_text("Move Crown: %s — tap another spot" % reason)
		return
	_sim.player_move_crown(me.id, tile.x, tile.y)
	exit()
