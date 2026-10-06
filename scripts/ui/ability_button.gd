class_name AbilityButton
extends Button

# One ability button, drawn in code: a vector icon, the name, the troop cost,
# a cooldown ring that empties as the cooldown runs out, a lock icon until the
# ability unlocks, and a glowing ring while the effect is active.

const SIZE: Vector2 = Vector2(150, 96)
const COLOR_ICON: Color = Color(0.95, 0.95, 0.98)
const COLOR_LOCKED: Color = Color(0.55, 0.55, 0.60)
const COLOR_RING_BG: Color = Color(1, 1, 1, 0.12)
const COLOR_COOLDOWN: Color = Color(0.55, 0.75, 1.0)
const COLOR_ACTIVE: Color = Color(1.0, 0.85, 0.30)
const COLOR_READY: Color = Color(0.45, 0.95, 0.55)

var ability_id: int = 0
var title: String = ""
# Set every frame by AbilityBar.
var locked: bool = true
var unlock_text: String = ""
var active_frac: float = 0.0       # 1 -> 0 while the effect runs
var cooldown_frac: float = 0.0     # 1 -> 0 while cooling down
var cooldown_left: float = 0.0
var cost_text: String = ""
var affordable: bool = true

var _font: Font
var _time: float = 0.0


func _ready() -> void:
	custom_minimum_size = SIZE
	focus_mode = Control.FOCUS_NONE
	text = ""
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, 34.0)
	var r: float = 24.0
	# Ring: active effect (gold, pulsing) > cooldown (blue) > ready (green).
	draw_arc(c, r, 0.0, TAU, 40, COLOR_RING_BG, 4.0, true)
	if active_frac > 0.0:
		var pulse: float = 0.6 + 0.4 * sin(_time * 7.0)
		draw_arc(c, r + 3.0, 0.0, TAU, 40, Color(COLOR_ACTIVE, 0.35 * pulse), 8.0, true)
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * active_frac, 40, COLOR_ACTIVE, 4.0, true)
	elif cooldown_frac > 0.0:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * cooldown_frac, 40, COLOR_COOLDOWN, 4.0, true)
	elif not locked and affordable:
		draw_arc(c, r, 0.0, TAU, 40, Color(COLOR_READY, 0.8), 3.0, true)
	var icon_col: Color = COLOR_LOCKED if (locked or disabled) and active_frac <= 0.0 else COLOR_ICON
	_draw_icon(c, icon_col)
	if locked:
		_draw_lock(c + Vector2(14, 12))
	# Cooldown seconds in the middle of the ring.
	if cooldown_frac > 0.0 and active_frac <= 0.0:
		_text_centered("%d" % int(ceilf(cooldown_left)), c + Vector2(0, 7), 20, Color.WHITE)
	_text_centered(title, Vector2(size.x * 0.5, 76.0), 15, UIStyle.COLOR_TEXT)
	var sub: String = unlock_text if locked else cost_text
	var sub_col: Color = UIStyle.COLOR_DIM if locked else (UIStyle.COLOR_TEXT if affordable else UIStyle.COLOR_BAD)
	_text_centered(sub, Vector2(size.x * 0.5, 92.0), 13, sub_col)


func _text_centered(s: String, at: Vector2, font_size: int, col: Color) -> void:
	var w: float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string_outline(_font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color.BLACK)
	draw_string(_font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _draw_icon(c: Vector2, col: Color) -> void:
	match ability_id:
		AbilitiesOps.ID_SWIFT_MARCH:
			# Double chevron: speed.
			for dx: float in [-7.0, 5.0]:
				draw_polyline(PackedVector2Array([c + Vector2(dx - 6, -11), c + Vector2(dx + 6, 0), c + Vector2(dx - 6, 11)]), col, 4.0, true)
		AbilitiesOps.ID_CROWN_SHIELD:
			var shield := PackedVector2Array([
				c + Vector2(0, -14), c + Vector2(12, -9), c + Vector2(11, 3), c + Vector2(0, 14),
				c + Vector2(-11, 3), c + Vector2(-12, -9),
			])
			draw_colored_polygon(shield, Color(col, 0.35))
			shield.append(shield[0])
			draw_polyline(shield, col, 3.0, true)
		AbilitiesOps.ID_RALLY:
			# Banner on a pole.
			draw_line(c + Vector2(-8, -14), c + Vector2(-8, 14), col, 3.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -13), c + Vector2(12, -7), c + Vector2(-7, -1)]), col)
		AbilitiesOps.ID_BOMBARD:
			# Burst with a crosshair.
			var pts := PackedVector2Array()
			for k in range(16):
				var ang: float = TAU * float(k) / 16.0
				var rad: float = 14.0 if k % 2 == 0 else 7.0
				pts.append(c + Vector2(cos(ang), sin(ang)) * rad)
			draw_colored_polygon(pts, Color(col, 0.45))
			draw_arc(c, 6.0, 0.0, TAU, 20, col, 2.5, true)
			draw_line(c + Vector2(-15, 0), c + Vector2(15, 0), col, 2.0, true)
			draw_line(c + Vector2(0, -15), c + Vector2(0, 15), col, 2.0, true)


func _draw_lock(at: Vector2) -> void:
	draw_arc(at + Vector2(0, -3), 5.0, PI, TAU, 12, Color.WHITE, 2.5, true)
	draw_rect(Rect2(at + Vector2(-7, -3), Vector2(14, 11)), Color(0.95, 0.80, 0.30))
	draw_rect(Rect2(at + Vector2(-7, -3), Vector2(14, 11)), Color.BLACK, false, 1.5)
