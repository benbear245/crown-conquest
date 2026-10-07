class_name CameraRig
extends Camera2D

# Pan, pinch/wheel zoom, jumps and screen shake for the map camera.

const ZOOM_MIN_FACTOR: float = 0.6         # vs. fit-to-screen zoom
const ZOOM_MAX_FACTOR: float = 6.0
const SHAKE_DECAY: float = 3.0

var _world_size: Vector2 = Vector2.ONE
var _fit_zoom: float = 1.0
var _shake: float = 0.0                    # current strength in screen pixels
var _rng := RandomNumberGenerator.new()


func fit_world(world_size: Vector2) -> void:
	_world_size = world_size
	position = world_size * 0.5
	var vp := get_viewport_rect().size
	_fit_zoom = minf(vp.x / world_size.x, vp.y / world_size.y)
	zoom = Vector2(_fit_zoom, _fit_zoom)


func pan_screen(relative: Vector2) -> void:
	position -= relative / zoom.x
	clamp_to_world()


func zoom_by(factor: float, screen_anchor: Vector2 = Vector2(-1, -1)) -> void:
	var before: Vector2 = screen_to_world(screen_anchor) if screen_anchor.x >= 0.0 else position
	var new_zoom: float = clampf(zoom.x * factor, _fit_zoom * ZOOM_MIN_FACTOR, _fit_zoom * ZOOM_MAX_FACTOR)
	zoom = Vector2(new_zoom, new_zoom)
	if screen_anchor.x >= 0.0:
		# Keep the world point under the fingers in place.
		position += before - screen_to_world(screen_anchor)
	clamp_to_world()


func jump_to(world_pos: Vector2) -> void:
	position = world_pos
	clamp_to_world()


func shake(strength_px: float) -> void:
	_shake = maxf(_shake, strength_px)


# Pure math (not the canvas transform) so it is right even before the camera
# has pushed a new zoom to the viewport this frame.
func screen_to_world(screen_pos: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	return position + (screen_pos - vp * 0.5) / zoom.x


# The world rectangle currently on screen (for the minimap's view box).
func visible_world_rect() -> Rect2:
	var vp := get_viewport_rect().size
	var size: Vector2 = vp / zoom.x
	return Rect2(position - size * 0.5, size)


func clamp_to_world() -> void:
	var vp := get_viewport_rect().size
	var half := (vp / zoom.x) * 0.5
	var w := _world_size
	position.x = clampf(position.x, minf(half.x, w.x * 0.5), maxf(w.x - half.x, w.x * 0.5))
	position.y = clampf(position.y, minf(half.y, w.y * 0.5), maxf(w.y - half.y, w.y * 0.5))


func _process(delta: float) -> void:
	if _shake <= 0.05:
		offset = Vector2.ZERO
		return
	offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake / zoom.x
	_shake = maxf(0.0, _shake - _shake * SHAKE_DECAY * delta - 0.5 * delta)
