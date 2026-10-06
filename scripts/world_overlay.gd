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

var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if state == null:
		return
	_draw_crowns()
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
	if move_preview.x >= 0:
		var col: Color = Color(0.4, 1.0, 0.5, 0.9) if move_preview_ok else Color(1.0, 0.35, 0.3, 0.9)
		draw_rect(Rect2(Vector2(move_preview) - Vector2(1, 1), Vector2(3, 3)), col, false, 0.2)
