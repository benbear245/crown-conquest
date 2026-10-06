class_name CameraRig
extends Camera2D

# Fit-to-map camera with drag panning and pinch / wheel zoom, kept inside the map.

const ZOOM_STEP: float = 1.15
const ZOOM_MIN_FACTOR: float = 0.6         # vs. fit-to-screen zoom
const ZOOM_MAX_FACTOR: float = 6.0

var world_size: Vector2 = Vector2(200, 120)
var _fit_zoom: float = 1.0
var _shake_strength: float = 0.0     # screen pixels
var _shake_left: float = 0.0
var _shake_total: float = 0.0


# Screen shake (in screen pixels), fading out over `seconds`.
func shake(strength: float, seconds: float) -> void:
	if strength >= _shake_strength * (_shake_left / maxf(_shake_total, 0.01)):
		_shake_strength = strength
		_shake_left = seconds
		_shake_total = seconds


func _process(delta: float) -> void:
	if _shake_left <= 0.0:
		if offset != Vector2.ZERO:
			offset = Vector2.ZERO
		return
	_shake_left -= delta
	var k: float = maxf(0.0, _shake_left / _shake_total)
	offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake_strength * k / zoom.x


func fit_to_world(size_in_tiles: Vector2) -> void:
	world_size = size_in_tiles
	position = world_size * 0.5
	var vp: Vector2 = get_viewport_rect().size
	_fit_zoom = minf(vp.x / world_size.x, vp.y / world_size.y)
	zoom = Vector2(_fit_zoom, _fit_zoom)


func zoom_by(factor: float) -> void:
	var z: float = clampf(zoom.x * factor, _fit_zoom * ZOOM_MIN_FACTOR, _fit_zoom * ZOOM_MAX_FACTOR)
	zoom = Vector2(z, z)
	clamp_to_world()


# Zoom keeping the world point under `screen_pos` where it is (pinch centre).
func zoom_at(factor: float, screen_pos: Vector2) -> void:
	var vp: Vector2 = get_viewport_rect().size
	var before: Vector2 = position + (screen_pos - vp * 0.5) / zoom.x
	zoom_by(factor)
	var after: Vector2 = position + (screen_pos - vp * 0.5) / zoom.x
	position += before - after
	clamp_to_world()


func pan_screen(relative: Vector2) -> void:
	position -= relative / zoom.x
	clamp_to_world()


func look_at_tile(tile: Vector2i) -> void:
	position = Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)
	clamp_to_world()


func clamp_to_world() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var half: Vector2 = (vp / zoom.x) * 0.5
	position.x = clampf(position.x, minf(half.x, world_size.x * 0.5), maxf(world_size.x - half.x, world_size.x * 0.5))
	position.y = clampf(position.y, minf(half.y, world_size.y * 0.5), maxf(world_size.y - half.y, world_size.y * 0.5))
