class_name VictoryFx
extends Control

# The winner's victory effect, drawn over everything for a few seconds:
# Fireworks, Confetti or Golden Rain (Cosmetics.VICTORY_NAMES).

const DURATION_SEC: float = 6.0
const GRAVITY: float = 260.0

var _parts: Array[Dictionary] = []      # {pos, vel, col, life, size}
var _kind: int = 0
var _left: float = 0.0
var _spawn_timer: float = 0.0
var _color: Color = Color.WHITE
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func play(kind: int, player_color: Color) -> void:
	if kind <= 0:
		return
	_kind = kind
	_color = player_color
	_left = DURATION_SEC
	_parts.clear()
	_rng.randomize()
	set_process(true)


func stop() -> void:
	_left = 0.0
	_parts.clear()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	_left -= delta
	_spawn_timer -= delta
	if _left > 1.0 and _spawn_timer <= 0.0:
		_spawn()
	for p in _parts:
		p["vel"] = (p["vel"] as Vector2) + Vector2(0, GRAVITY * float(p["grav"])) * delta
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		p["life"] = float(p["life"]) - delta
	_parts = _parts.filter(func(p: Dictionary) -> bool: return float(p["life"]) > 0.0)
	if _left <= 0.0 and _parts.is_empty():
		set_process(false)
	queue_redraw()


func _spawn() -> void:
	var w: float = size.x
	match _kind:
		1:   # Fireworks: a burst every half second
			_spawn_timer = 0.5
			var c := Vector2(_rng.randf_range(w * 0.15, w * 0.85), _rng.randf_range(size.y * 0.15, size.y * 0.5))
			var col: Color = _color.lightened(0.3) if _rng.randf() < 0.5 else Color.from_hsv(_rng.randf(), 0.6, 1.0)
			for i in range(48):
				var a: float = TAU * float(i) / 48.0
				_add(c, Vector2(cos(a), sin(a)) * _rng.randf_range(140.0, 320.0), col, 1.4, 4.0, 0.35)
		2:   # Confetti: steady shower of coloured flakes
			_spawn_timer = 0.05
			for i in range(5):
				var col := Color.from_hsv(_rng.randf(), 0.7, 1.0)
				_add(Vector2(_rng.randf_range(0, w), -10), Vector2(_rng.randf_range(-60, 60), _rng.randf_range(60, 160)), col, 4.0, 6.0, 0.25)
		_:   # Golden Rain
			_spawn_timer = 0.04
			for i in range(6):
				var col := Color(1.0, _rng.randf_range(0.75, 0.9), 0.25)
				_add(Vector2(_rng.randf_range(0, w), -10), Vector2(0, _rng.randf_range(200, 380)), col, 3.0, 3.0, 0.6)


func _add(pos: Vector2, vel: Vector2, col: Color, life: float, sz: float, grav: float) -> void:
	_parts.append({"pos": pos, "vel": vel, "col": col, "life": life, "max": life, "size": sz, "grav": grav})


func _draw() -> void:
	for p in _parts:
		var col: Color = p["col"]
		col.a = clampf(float(p["life"]) / float(p["max"]) * 1.5, 0.0, 1.0)
		var s: float = float(p["size"])
		draw_rect(Rect2((p["pos"] as Vector2) - Vector2(s, s) * 0.5, Vector2(s, s)), col)
