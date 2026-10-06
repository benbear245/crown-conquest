class_name VictoryEffect
extends Control

# Cheap victory celebrations drawn with simple shapes (no particle nodes):
# 1 Fireworks, 2 Confetti, 3 Golden rain. Plays for a few seconds.

const DURATION: float = 5.0
const COLORS: Array[Color] = [Color(1, 0.85, 0.3), Color(0.95, 0.35, 0.35), Color(0.4, 0.75, 1.0), Color(0.5, 0.95, 0.5), Color(0.9, 0.5, 0.95)]

var kind: int = 0
var _left: float = 0.0
var _parts: Array[Dictionary] = []     # {pos, vel, col, life, size, spin}
var _next_burst: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func play(effect: int) -> void:
	kind = effect
	_left = DURATION if effect > 0 else 0.0
	_parts.clear()
	_next_burst = 0.0


func is_playing() -> bool:
	return _left > 0.0


func _process(delta: float) -> void:
	if _left <= 0.0 and _parts.is_empty():
		return
	_left -= delta
	var sz: Vector2 = size
	if _left > 0.0:
		match kind:
			1:
				_next_burst -= delta
				if _next_burst <= 0.0:
					_next_burst = _rng.randf_range(0.25, 0.55)
					_burst(Vector2(_rng.randf_range(0.15, 0.85) * sz.x, _rng.randf_range(0.12, 0.45) * sz.y))
			2:
				for i in range(3):
					_parts.append({"pos": Vector2(_rng.randf() * sz.x, -10.0), "vel": Vector2(_rng.randf_range(-40, 40), _rng.randf_range(160, 260)),
						"col": COLORS[_rng.randi() % COLORS.size()], "life": 4.0, "size": _rng.randf_range(6, 11), "spin": _rng.randf() * TAU})
			3:
				for i in range(2):
					_parts.append({"pos": Vector2(_rng.randf() * sz.x, -10.0), "vel": Vector2(0, _rng.randf_range(220, 340)),
						"col": Color(1.0, _rng.randf_range(0.75, 0.9), 0.25), "life": 4.0, "size": _rng.randf_range(5, 9), "spin": 0.0})
	var i2: int = 0
	while i2 < _parts.size():
		var p: Dictionary = _parts[i2]
		p.life = float(p.life) - delta
		if kind == 1:
			p.vel = (p.vel as Vector2) * (1.0 - 1.6 * delta) + Vector2(0, 90.0 * delta)
		p.pos = (p.pos as Vector2) + (p.vel as Vector2) * delta
		p.spin = float(p.spin) + delta * 6.0
		if float(p.life) <= 0.0 or (p.pos as Vector2).y > sz.y + 20.0:
			_parts.remove_at(i2)
			continue
		i2 += 1
	queue_redraw()


func _burst(at: Vector2) -> void:
	var col: Color = COLORS[_rng.randi() % COLORS.size()]
	for k in range(36):
		var a: float = TAU * float(k) / 36.0 + _rng.randf() * 0.1
		_parts.append({"pos": at, "vel": Vector2(cos(a), sin(a)) * _rng.randf_range(160, 320), "col": col, "life": 1.3, "size": 4.0, "spin": 0.0})
	Audio.play("sfx_capture", -6.0, _rng.randf_range(0.6, 0.9))


func _draw() -> void:
	for p: Dictionary in _parts:
		var col: Color = p.col
		var pos: Vector2 = p.pos
		var s: float = float(p.size)
		match kind:
			1:
				col.a = clampf(float(p.life) / 1.3, 0.0, 1.0)
				draw_circle(pos, s, col)
			2:
				var d := Vector2(cos(float(p.spin)), sin(float(p.spin))) * s
				draw_line(pos - d, pos + d, col, s * 0.7)
			3:
				draw_circle(pos, s, col)
				draw_circle(pos - Vector2(s, s) * 0.3, s * 0.35, Color(1, 1, 0.85, 0.9))
