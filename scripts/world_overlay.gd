class_name WorldOverlay
extends Node2D

# Things drawn on top of the map in world (tile) coordinates every frame:
# Crown icons, boats, selection and range previews. Only reads GameState;
# game.gd sets the preview fields.

const CROWN_GOLD: Color = Color(0.98, 0.84, 0.25)
const CROWN_EDGE: Color = Color(0.25, 0.16, 0.02)

var state: GameState
var local_player_id: int = 1
# Build menu selection: tile outline and the range of the Fort there (0 = none).
var selected_tile: Vector2i = Vector2i(-1, -1)
var selected_radius: int = 0
# Port chosen for a boat launch (-1 = none).
var boat_port: Vector2i = Vector2i(-1, -1)
# Crown-move preview: centre tile and whether it's a valid spot.
var move_preview: Vector2i = Vector2i(-1, -1)
var move_preview_ok: bool = false
# Bombard targeting preview: centre tile and whether it's in range.
var bombard_preview: Vector2i = Vector2i(-1, -1)
var bombard_preview_ok: bool = false

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if state == null:
		return
	_draw_bombards()
	_draw_rally_fronts()
	_draw_crowns()
	_draw_shields()
	_draw_boats()
	_draw_selection()


func _draw_crowns() -> void:
	for p: Player in state.players:
		if not p.is_alive or p.crown_x < 0:
			continue
		var c := Vector2(float(p.crown_x) + 0.5, float(p.crown_y) + 0.5)
		if p.crown_move_until > state.match_time:
			# Moving: no special defense yet — a pulsing ring warns everyone.
			var pulse: float = 0.5 + 0.5 * sin(_time * 8.0)
			draw_arc(c, 2.2, 0.0, TAU, 32, Color(1, 0.3, 0.2, 0.5 + 0.4 * pulse), 0.35)
		_draw_crown_icon(c, 1.15)
		# Rising Empire: a star above their Crown. Your truce partners: a white flag.
		if p.id == state.rising_empire_id:
			var bob: float = 0.15 * sin(_time * 3.0)
			Icons.star(self, c + Vector2(0, -2.6 + bob), 1.1, Color(1.0, 0.55, 0.25))
		var me: Player = state.get_player(local_player_id)
		if me != null and p.id != me.id and TrucesOps.has_truce(me, p.id, state.match_time):
			Icons.white_flag(self, c + Vector2(1.9, -2.2), 1.0)


func _draw_crown_icon(c: Vector2, s: float) -> void:
	var pts := PackedVector2Array([
		c + Vector2(-1.0, 0.65) * s, c + Vector2(-1.0, -0.35) * s, c + Vector2(-0.5, 0.1) * s,
		c + Vector2(0.0, -0.75) * s, c + Vector2(0.5, 0.1) * s, c + Vector2(1.0, -0.35) * s,
		c + Vector2(1.0, 0.65) * s,
	])
	draw_colored_polygon(pts, CROWN_GOLD)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, CROWN_EDGE, 0.12)


# Crown Shield: a pulsing bubble over the whole Crown zone.
func _draw_shields() -> void:
	for p: Player in state.players:
		if not p.is_alive or p.crown_x < 0 or not AbilitiesOps.is_crown_shield_active(p, state.match_time):
			continue
		var c := Vector2(float(p.crown_x) + 0.5, float(p.crown_y) + 0.5)
		var r: float = float(p.crown_zone_radius()) + 0.5
		var pulse: float = 0.5 + 0.5 * sin(_time * 4.0)
		draw_circle(c, r, Color(0.45, 0.85, 1.0, 0.16 + 0.06 * pulse))
		draw_arc(c, r, 0.0, TAU, 64, Color(0.70, 0.95, 1.0, 0.75 + 0.25 * pulse), 0.35)
		draw_arc(c, r * 0.55, -2.4, -1.2, 16, Color(1, 1, 1, 0.45), 0.3)   # glint


# Rally: the attacker's fronts glow while the discount is active.
func _draw_rally_fronts() -> void:
	var pulse: float = 0.5 + 0.5 * sin(_time * 9.0)
	for a: Attack in state.attacks:
		var attacker: Player = state.get_player(a.attacker_id)
		if attacker == null or not AbilitiesOps.is_rally_active(attacker, state.match_time):
			continue
		var col := Color(1.0, 0.78, 0.25, 0.45 + 0.35 * pulse)
		for ti: int in a.front.keys():
			var t: Vector2i = state.idx_to_xy(ti)
			draw_rect(Rect2(Vector2(t) - Vector2(0.15, 0.15), Vector2(1.3, 1.3)), col)


# Bombard: cracked ground and a ring around the area while it lasts.
func _draw_bombards() -> void:
	for b: Dictionary in state.bombards:
		if state.match_time >= float(b["until"]):
			continue
		var c := Vector2(float(b["target_x"]) + 0.5, float(b["target_y"]) + 0.5)
		var r: float = float(Balance.BOMBARD_AREA_RADIUS_TILES) + 0.5
		draw_arc(c, r, 0.0, TAU, 48, Color(0.15, 0.05, 0.05, 0.9), 0.3)
		_draw_cracks(c, r, int(b["target_x"]) * 92821 + int(b["target_y"]) * 68917)


func _draw_cracks(c: Vector2, r: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var col := Color(0.05, 0.03, 0.03, 0.85)
	for k in range(9):
		var ang: float = TAU * float(k) / 9.0 + rng.randf_range(-0.3, 0.3)
		var pts := PackedVector2Array([c])
		var p: Vector2 = c
		for step in range(4):
			ang += rng.randf_range(-0.5, 0.5)
			p += Vector2(cos(ang), sin(ang)) * r * 0.25
			pts.append(p)
			if step == 1 and rng.randf() < 0.6:
				var side: float = ang + rng.randf_range(0.6, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0)
				draw_line(p, p + Vector2(cos(side), sin(side)) * r * 0.3, col, 0.12)
		draw_polyline(pts, col, 0.18)


func _draw_boats() -> void:
	for b: Boat in state.boats:
		if b.path.size() < 2:
			continue
		var i: int = clampi(int(b.progress), 0, b.path.size() - 2)
		var f: float = b.progress - float(i)
		var a: Vector2i = state.idx_to_xy(b.path[i])
		var n: Vector2i = state.idx_to_xy(b.path[i + 1])
		var pos: Vector2 = Vector2(a).lerp(Vector2(n), f) + Vector2(0.5, 0.5)
		var col: Color = Balance.color_for_player(b.owner_id)
		if b.owner_id == local_player_id:
			# Show our own boat's remaining route.
			var route := PackedVector2Array([pos])
			for k in range(i + 1, b.path.size()):
				route.append(Vector2(state.idx_to_xy(b.path[k])) + Vector2(0.5, 0.5))
			draw_polyline(route, Color(1, 1, 1, 0.35), 0.15)
		draw_circle(pos, 0.9, Color(0.05, 0.05, 0.08))
		draw_circle(pos, 0.7, col)


func _draw_selection() -> void:
	if selected_tile.x >= 0:
		var r := Rect2(Vector2(selected_tile), Vector2.ONE)
		draw_rect(r, Color(1, 1, 1, 0.9), false, 0.15)
		if selected_radius > 0:
			draw_arc(Vector2(selected_tile) + Vector2(0.5, 0.5), float(selected_radius), 0.0, TAU, 64, Color(1, 1, 1, 0.55), 0.2)
	if boat_port.x >= 0:
		var pulse: float = 0.5 + 0.5 * sin(_time * 6.0)
		draw_arc(Vector2(boat_port) + Vector2(0.5, 0.5), 1.4 + 0.4 * pulse, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 0.2)
	if bombard_preview.x >= 0:
		var bc := Vector2(bombard_preview) + Vector2(0.5, 0.5)
		var ok_col: Color = Color(1.0, 0.55, 0.2) if bombard_preview_ok else Color(1.0, 0.25, 0.25)
		var pulse: float = 0.5 + 0.5 * sin(_time * 6.0)
		var br: float = float(Balance.BOMBARD_AREA_RADIUS_TILES) + 0.5
		draw_circle(bc, br, Color(0, 0, 0, 0.22 + 0.08 * pulse))
		draw_arc(bc, br, 0.0, TAU, 48, Color(0, 0, 0, 0.8), 0.5)
		draw_arc(bc, br, 0.0, TAU, 48, Color(1, 1, 1, 0.9), 0.22)
		draw_arc(bc, br - 0.45, 0.0, TAU, 48, ok_col, 0.25)
		draw_line(bc - Vector2(1.2, 0), bc + Vector2(1.2, 0), ok_col, 0.25)
		draw_line(bc - Vector2(0, 1.2), bc + Vector2(0, 1.2), ok_col, 0.25)
	if move_preview.x >= 0:
		var col: Color = Color(0.4, 1.0, 0.5, 0.9) if move_preview_ok else Color(1.0, 0.35, 0.3, 0.9)
		draw_rect(Rect2(Vector2(move_preview) - Vector2(1, 1), Vector2(3, 3)), col, false, 0.2)
