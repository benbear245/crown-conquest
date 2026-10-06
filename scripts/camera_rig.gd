class_name CameraRig
extends Camera2D

# Fit-to-map camera with drag panning and pinch / wheel zoom, kept inside the map.

const ZOOM_STEP: float = 1.15
const ZOOM_MIN_FACTOR: float = 0.6         # vs. fit-to-screen zoom
const ZOOM_MAX_FACTOR: float = 6.0

var world_size: Vector2 = Vector2(200, 120)
var _fit_zoom: float = 1.0


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
