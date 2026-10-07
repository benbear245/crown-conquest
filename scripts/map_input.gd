class_name MapInput
extends Node

# Turns raw pointer input on the map into gestures: tap, long-press, drag
# (one finger) and pinch (two fingers). Godot turns the first touch into
# mouse events, so single-finger gestures come from mouse events and only
# pinch reads the raw touches. That way a touch is never handled twice.

signal tapped(screen_pos: Vector2)
signal long_pressed(screen_pos: Vector2)
signal dragged(screen_pos: Vector2, relative: Vector2)
signal pinched(factor: float, centre: Vector2)
signal wheel_zoomed(factor: float, screen_pos: Vector2)

const DRAG_THRESHOLD_PX: float = 14.0
const LONG_PRESS_SEC: float = 0.45
const WHEEL_STEP: float = 1.15

var _down: bool = false
var _dragging: bool = false
var _long_fired: bool = false
var _press_pos: Vector2 = Vector2.ZERO
var _press_time: float = 0.0
# Raw touches for pinch: index -> position.
var _touches: Dictionary = {}
var _pinch_dist: float = 0.0


func _process(delta: float) -> void:
	if not _down or _dragging or _long_fired or _touches.size() >= 2:
		return
	_press_time += delta
	if _press_time >= LONG_PRESS_SEC:
		_long_fired = true
		long_pressed.emit(_press_pos)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event)
	elif event is InputEventScreenDrag:
		_on_touch_drag(event)
	elif event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _down and _touches.size() < 2:
			_on_pointer_move(event.position, event.relative)
	elif event is InputEventMagnifyGesture:
		var mg: InputEventMagnifyGesture = event
		pinched.emit(mg.factor, mg.position)


func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_down = true
				_dragging = false
				_long_fired = false
				_press_pos = event.position
				_press_time = 0.0
			else:
				if _down and not _dragging and not _long_fired and _touches.size() < 2:
					tapped.emit(event.position)
				_down = false
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				wheel_zoomed.emit(WHEEL_STEP, event.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				wheel_zoomed.emit(1.0 / WHEEL_STEP, event.position)


func _on_pointer_move(pos: Vector2, relative: Vector2) -> void:
	if not _dragging and pos.distance_to(_press_pos) > DRAG_THRESHOLD_PX:
		_dragging = true
		# Don't lose the movement that crossed the threshold.
		relative = pos - _press_pos
	if _dragging:
		dragged.emit(pos, relative)


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
	else:
		_touches.erase(event.index)
	if _touches.size() == 2:
		# A second finger cancels any tap / long-press in progress.
		_dragging = true
		var pts: Array = _touches.values()
		_pinch_dist = (pts[0] as Vector2).distance_to(pts[1])
	elif _touches.is_empty():
		_pinch_dist = 0.0


func _on_touch_drag(event: InputEventScreenDrag) -> void:
	_touches[event.index] = event.position
	if _touches.size() < 2 or _pinch_dist <= 0.0:
		return
	var pts: Array = _touches.values()
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[1]
	var d: float = a.distance_to(b)
	if d > 1.0:
		pinched.emit(d / _pinch_dist, (a + b) * 0.5)
		_pinch_dist = d
