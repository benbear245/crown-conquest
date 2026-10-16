class_name Look
extends RefCounted

# Draws the cosmetics players picked: territory colour, pattern and Crown
# icon. Presentation only — the rules never read any of this.

const CLASH_DISTANCE: float = 0.28        # colours closer than this read as the same
const PATTERN_DARKEN: float = 0.16

# Per player id, refreshed by apply() at the start of each match.
static var patterns: PackedInt32Array = PackedInt32Array()
static var crowns: PackedInt32Array = PackedInt32Array()


# Reads every player's cosmetic and sets the map colours, patterns and Crown
# icons for this match. A chosen colour that clashes with another player's
# swaps with that player's normal colour, so everyone stays readable. In
# colour-blind mode the safe palette always wins.
static func apply(state: GameState) -> void:
	Balance.player_color_overrides = {}
	var top: int = 1
	for p: Player in state.players:
		top = maxi(top, p.id + 1)
	patterns = PackedInt32Array()
	patterns.resize(top)
	crowns = PackedInt32Array()
	crowns.resize(top)
	for p: Player in state.players:
		patterns[p.id] = int(p.cosmetic.get(Cosmetics.CAT_PATTERN, 0))
		crowns[p.id] = int(p.cosmetic.get(Cosmetics.CAT_CROWN, 0))
	if Balance.colorblind_mode:
		return
	var taken: Dictionary = {}       # player id -> colour now in use
	for p: Player in state.players:
		taken[p.id] = Balance.color_for_player(p.id)
	for p: Player in state.players:
		if not p.cosmetic.has(Cosmetics.CAT_COLOR):
			continue
		var want: Color = Cosmetics.COLORS[clampi(int(p.cosmetic[Cosmetics.CAT_COLOR]), 0, Cosmetics.COLORS.size() - 1)]
		var own: Color = taken[p.id]
		var clash_id: int = -1
		var blocked: bool = false
		for q: Player in state.players:
			if q.id == p.id or _distance(taken[q.id], want) >= CLASH_DISTANCE:
				continue
			if Balance.player_color_overrides.has(q.id):
				blocked = true         # someone already chose it
			else:
				clash_id = q.id
		if blocked:
			continue
		if clash_id >= 0:
			Balance.player_color_overrides[clash_id] = own
			taken[clash_id] = own
		Balance.player_color_overrides[p.id] = want
		taken[p.id] = want


static func name_with_title(p: Player) -> String:
	var t: int = clampi(int(p.cosmetic.get(Cosmetics.CAT_TITLE, 0)), 0, Cosmetics.TITLE_NAMES.size() - 1)
	return p.display_name if t == 0 else "%s the %s" % [p.display_name, Cosmetics.TITLE_NAMES[t]]


static func clear() -> void:
	Balance.player_color_overrides = {}
	patterns = PackedInt32Array()
	crowns = PackedInt32Array()


static func pattern_of(player_id: int) -> int:
	return patterns[player_id] if player_id >= 0 and player_id < patterns.size() else 0


static func crown_of(player_id: int) -> int:
	return crowns[player_id] if player_id >= 0 and player_id < crowns.size() else 0


# Territory colour for one tile with the owner's pattern on top.
static func patterned(color: Color, pattern: int, x: int, y: int) -> Color:
	return color.darkened(PATTERN_DARKEN) if pattern_hit(pattern, x, y) else color


static func pattern_hit(pattern: int, x: int, y: int) -> bool:
	match pattern:
		1:   # Stripes
			return posmod(x + y, 4) == 0
		2:   # Dots
			return posmod(x, 3) == 1 and posmod(y, 3) == 1
		3:   # Checks
			return posmod((x >> 1) + (y >> 1), 2) == 0
		4:   # Waves
			return posmod(y + int(round(sin(float(x) * 0.8) * 1.4)), 4) == 0
		5:   # Scales
			var u: int = posmod(x + posmod(y >> 1, 2) * 2, 4)
			return (posmod(y, 2) == 0 and (u == 1 or u == 3)) or (posmod(y, 2) == 1 and u == 0)
		6:   # Bricks
			return posmod(y, 3) == 0 or posmod(x + posmod(floori(y / 3.0), 2) * 3, 6) == 0
	return false


static func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


# --- Crown icons ---------------------------------------------------------------

# Draws Crown icon `kind` centred on base, size = half-width. Used on the map
# (sizes in tiles) and in menus (sizes in pixels).
static func draw_crown(ci: CanvasItem, kind: int, base: Vector2, size: float, col: Color) -> void:
	var w: float = size
	var outline := Color(0.2, 0.12, 0.0)
	var pts: PackedVector2Array
	match kind:
		1:   # Star
			pts = PackedVector2Array()
			for i in range(10):
				var r: float = w if i % 2 == 0 else w * 0.45
				var a: float = -PI * 0.5 + float(i) * PI / 5.0
				pts.append(base + Vector2(cos(a), sin(a)) * r)
		2:   # Shield
			pts = PackedVector2Array([base + Vector2(-w, -0.7 * w), base + Vector2(w, -0.7 * w),
				base + Vector2(w, 0.1 * w), base + Vector2(0, 0.9 * w), base + Vector2(-w, 0.1 * w)])
		3:   # Tower
			pts = PackedVector2Array([base + Vector2(-0.8 * w, 0.8 * w), base + Vector2(-0.8 * w, -0.8 * w),
				base + Vector2(-0.4 * w, -0.8 * w), base + Vector2(-0.4 * w, -0.5 * w), base + Vector2(-0.1 * w, -0.5 * w),
				base + Vector2(-0.1 * w, -0.8 * w), base + Vector2(0.2 * w, -0.8 * w), base + Vector2(0.2 * w, -0.5 * w),
				base + Vector2(0.5 * w, -0.5 * w), base + Vector2(0.5 * w, -0.8 * w), base + Vector2(0.8 * w, -0.8 * w),
				base + Vector2(0.8 * w, 0.8 * w)])
		4:   # Flame
			pts = PackedVector2Array([base + Vector2(0, -w), base + Vector2(0.35 * w, -0.4 * w),
				base + Vector2(0.7 * w, 0.1 * w), base + Vector2(0.6 * w, 0.6 * w), base + Vector2(0, 0.9 * w),
				base + Vector2(-0.6 * w, 0.6 * w), base + Vector2(-0.7 * w, 0.1 * w), base + Vector2(-0.2 * w, -0.3 * w)])
		5:   # Gem
			pts = PackedVector2Array([base + Vector2(-0.5 * w, -0.6 * w), base + Vector2(0.5 * w, -0.6 * w),
				base + Vector2(w, -0.1 * w), base + Vector2(0, 0.9 * w), base + Vector2(-w, -0.1 * w)])
		6:   # Laurel
			ci.draw_arc(base + Vector2(0.25 * w, 0), 0.8 * w, PI * 0.55, PI * 1.45, 12, col, 0.3 * w)
			ci.draw_arc(base - Vector2(0.25 * w, 0), 0.8 * w, -PI * 0.45, PI * 0.45, 12, col, 0.3 * w)
			ci.draw_circle(base + Vector2(0, -0.1 * w), 0.25 * w, col)
			return
		7:   # High Crown
			pts = PackedVector2Array([base + Vector2(-w, 0.6 * w), base + Vector2(-w, -0.5 * w),
				base + Vector2(-0.6 * w, 0), base + Vector2(-0.3 * w, -0.8 * w), base + Vector2(0, -0.1 * w),
				base + Vector2(0.3 * w, -0.8 * w), base + Vector2(0.6 * w, 0), base + Vector2(w, -0.5 * w),
				base + Vector2(w, 0.6 * w)])
		_:   # Crown
			pts = PackedVector2Array([base + Vector2(-w, 0.6 * w), base + Vector2(-w, -0.3 * w),
				base + Vector2(-0.5 * w, 0.1 * w), base + Vector2(0, -0.6 * w), base + Vector2(0.5 * w, 0.1 * w),
				base + Vector2(w, -0.3 * w), base + Vector2(w, 0.6 * w)])
	ci.draw_colored_polygon(pts, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, outline, maxf(0.2, w * 0.09))
