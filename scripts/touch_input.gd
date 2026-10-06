class_name TouchInput
extends RefCounted

# Turns raw touch / mouse events into reliable gestures:
#   tap, long-press (held still for LONG_PRESS_SEC), one-finger drag, and
#   two-finger pinch (zoom) + pan. A second finger cancels any tap or
#   long-press in progress, and a finger that wanders more than the slop
#   distance becomes a drag instead of a tap.
# Android also sends a fake mouse event for every touch; those are ignored
# (we already handle the touch itself), so a tap never fires twice.

signal tapped(pos: Vector2)
signal long_pressed(pos: Vector2)
signal drag_started(pos: Vector2)
signal dragged(pos: Vector2, relative: Vector2)
signal drag_ended(pos: Vector2)
signal pinched(factor: float, centre: Vector2)

const LONG_PRESS_SEC: float = 0.45
const SLOP_PX: float = 14.0          # finger jitter allowed before a press becomes a drag

var _touches: Dictionary = {}        # finger index -> current position
var _press_pos: Vector2 = Vector2.ZERO
var _press_time: float = 0.0
var _pressing: bool = false          # a single finger is down and may still tap / long-press
var _dragging: bool = false
var _long_fired: bool = false
var _multi: bool = false             # two fingers were down during this gesture
var _pinch_dist: float = 0.0


func handle(event: InputEvent) -> bool:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			return false
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			_touches[st.index] = st.position
			if _touches.size() == 1:
				_begin(st.position)
			else:
				_begin_multi()
		else:
			_touches.erase(st.index)
			if _touches.is_empty():
				_end(st.position)
		return true
	if event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		var prev: Vector2 = _touches.get(sd.index, sd.position)
		_touches[sd.index] = sd.position
		if _touches.size() >= 2:
			_update_pinch(sd.position - prev)
		else:
			_move(sd.position, sd.relative)
		return true
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_begin(mb.position)
			else:
				_end(mb.position)
			return true
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			pinched.emit(1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15, mb.position)
			return true
	if event is InputEventMouseMotion and _pressing:
		var mm: InputEventMouseMotion = event
		_move(mm.position, mm.relative)
		return true
	if event is InputEventMagnifyGesture:
		var mg: InputEventMagnifyGesture = event
		pinched.emit(mg.factor, mg.position)
		return true
	return false


# Call every frame: fires the long-press once the finger has been still long enough.
func process(delta: float) -> void:
	if not _pressing or _dragging or _long_fired or _multi:
		return
	_press_time += delta
	if _press_time >= LONG_PRESS_SEC:
		_long_fired = true
		long_pressed.emit(_press_pos)


# 0..1 while a long-press is building up (for the on-screen ring), else -1.
func long_press_progress() -> float:
	if not _pressing or _dragging or _long_fired or _multi or _press_time < 0.1:
		return -1.0
	return clampf(_press_time / LONG_PRESS_SEC, 0.0, 1.0)


func press_position() -> Vector2:
	return _press_pos


func _begin(pos: Vector2) -> void:
	_pressing = true
	_dragging = false
	_long_fired = false
	_multi = false
	_press_pos = pos
	_press_time = 0.0


func _begin_multi() -> void:
	if _dragging:
		drag_ended.emit(_press_pos)
	_multi = true
	_dragging = false
	_pinch_dist = _finger_distance()


func _move(pos: Vector2, relative: Vector2) -> void:
	if not _pressing or _multi:
		return
	if not _dragging and pos.distance_to(_press_pos) > SLOP_PX:
		_dragging = true
		drag_started.emit(_press_pos)
	if _dragging:
		dragged.emit(pos, relative)


func _end(pos: Vector2) -> void:
	if _pressing and not _multi:
		if _dragging:
			drag_ended.emit(pos)
		elif not _long_fired:
			tapped.emit(_press_pos)
	_pressing = false
	_dragging = false
	_long_fired = false
	_multi = false


func _update_pinch(moved: Vector2) -> void:
	var d: float = _finger_distance()
	if _pinch_dist > 1.0 and d > 1.0:
		pinched.emit(d / _pinch_dist, _finger_centre())
	_pinch_dist = d
	# Two fingers moving together also pan (half the movement of one finger).
	dragged.emit(_finger_centre(), moved * 0.5)


func _finger_distance() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _finger_centre() -> Vector2:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return _press_pos
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
