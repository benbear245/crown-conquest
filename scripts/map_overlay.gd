class_name MapOverlay
extends Node2D

# World-space markers drawn every frame on top of the map texture: pulsing
# attack fronts, Crown and Shrine icons, boats, a Crown-move ghost, and
# floating "+N" numbers. Reads GameState only.

const FRONT_RECT_LIMIT: int = 3000
const FLOAT_TEXT_SEC: float = 1.6
const FLOAT_RISE_TILES: float = 6.0

var _state: GameState
var _local_id: int = 1
var _floaters: Array[Dictionary] = []
var _time: float = 0.0
var _font: Font


func setup(state: GameState, local_id: int) -> void:
	_state = state
	_local_id = local_id
	_floaters.clear()
	_font = ThemeDB.fallback_font


func add_floater(world_pos: Vector2, text: String, color: Color, scale_mult: float = 1.0) -> void:
	_floaters.append({"pos": world_pos, "text": text, "color": color, "age": 0.0, "scale": scale_mult})


func _process(delta: float) -> void:
	_time += delta
	for f in _floaters:
		f["age"] = float(f["age"]) + delta
	_floaters = _floaters.filter(func(f: Dictionary) -> bool: return float(f["age"]) < FLOAT_TEXT_SEC)
	queue_redraw()


func _draw() -> void:
	if _state == null:
		return
	_draw_fronts()
	_draw_shrines()
	_draw_crowns()
	_draw_boats()
	_draw_floaters()


# Fronts pulse in the attacker's colour; the local player's own fights pulse harder.
func _draw_fronts() -> void:
	var drawn: int = 0
	var pulse: float = 0.5 + 0.5 * sin(_time * 6.0)
	for a: Attack in _state.attacks:
		var mine: bool = a.attacker_id == _local_id or a.defender_id == _local_id
		var c: Color = Balance.color_for_player(a.attacker_id).lightened(0.3)
		c.a = (0.35 + 0.45 * pulse) if mine else (0.2 + 0.2 * pulse)
		for ti: int in a.front.keys():
			if drawn >= FRONT_RECT_LIMIT:
				return
			var pos: Vector2i = _state.idx_to_xy(ti)
			draw_rect(Rect2(Vector2(pos), Vector2.ONE), c)
			drawn += 1


func _draw_crowns() -> void:
	for p: Player in _state.players:
		if not p.is_alive or p.crown_x < 0:
			continue
		var centre := Vector2(p.crown_x + 0.5, p.crown_y + 0.5)
		var col: Color = Color(1.0, 0.85, 0.2)
		if p.crown_alert_until > _state.match_time:
			col = col.lerp(Color(1, 0.2, 0.2), 0.5 + 0.5 * sin(_time * 10.0))
		_draw_crown_icon(centre + Vector2(0, -3.2), 2.2, col)
		if AbilitiesOps.is_crown_shield_active(p, _state.match_time):
			draw_arc(centre, float(p.crown_zone_radius()) + 0.5, 0.0, TAU, 48, Color(0.5, 0.8, 1.0, 0.8), 0.4)
		if p.crown_move_to.x >= 0:
			var to := Vector2(p.crown_move_to.x + 0.5, p.crown_move_to.y + 0.5)
			var a: float = 0.4 + 0.4 * sin(_time * 8.0)
			draw_rect(Rect2(to - Vector2(1.5, 1.5), Vector2(3, 3)), Color(1, 0.9, 0.3, a), false, 0.3)
			draw_dashed_line(centre, to, Color(1, 0.9, 0.3, 0.6), 0.25, 1.0)


func _draw_crown_icon(base: Vector2, size: float, col: Color) -> void:
	var w: float = size
	var pts := PackedVector2Array([
		base + Vector2(-w, 0.6 * w), base + Vector2(-w, -0.3 * w), base + Vector2(-0.5 * w, 0.1 * w),
		base + Vector2(0, -0.6 * w), base + Vector2(0.5 * w, 0.1 * w), base + Vector2(w, -0.3 * w),
		base + Vector2(w, 0.6 * w),
	])
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, Color(0.2, 0.12, 0.0), 0.2)


func _draw_shrines() -> void:
	for s: Shrine in _state.shrines:
		var c := Vector2(s.x + 0.5, s.y + 0.5)
		var col: Color = shrine_color(s.kind)
		var glow: float = 0.6 + 0.4 * sin(_time * 2.0 + float(s.kind))
		draw_arc(c, 2.6, 0.0, TAU, 32, Color(col, 0.5 * glow), 0.35)
		var d: float = 1.4
		var pts := PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)])
		draw_colored_polygon(pts, col)
		if s.holder_id > 0:
			draw_circle(c, 0.55, Balance.color_for_player(s.holder_id))


static func shrine_color(kind: int) -> Color:
	match kind:
		Balance.SHRINE_PLENTY:
			return Color(0.45, 0.95, 0.45)
		Balance.SHRINE_WAR:
			return Color(1.0, 0.40, 0.30)
		_:
			return Color(0.55, 0.75, 1.0)


func _draw_boats() -> void:
	for b: Boat in _state.boats:
		var ti: int = b.current_tile_idx()
		if ti < 0:
			continue
		var pos: Vector2i = _state.idx_to_xy(ti)
		draw_rect(Rect2(Vector2(pos) - Vector2(0.3, 0.3), Vector2(1.6, 1.6)), Color.WHITE)
		draw_rect(Rect2(Vector2(pos), Vector2.ONE), Balance.color_for_player(b.owner_id))


func _draw_floaters() -> void:
	for f in _floaters:
		var t: float = float(f["age"]) / FLOAT_TEXT_SEC
		var pos: Vector2 = f["pos"] + Vector2(0, -FLOAT_RISE_TILES * t)
		var col: Color = f["color"]
		col.a = 1.0 - t * t
		# Font size is in world units (tiles); keep it readable when zoomed out.
		var size: int = int(4.0 * float(f["scale"]))
		draw_string_outline(_font, pos, String(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1, size, 1, Color(0, 0, 0, col.a))
		draw_string(_font, pos, String(f["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1, size, col)
