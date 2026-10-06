extends Node2D

# Root of the game scene. Owns the Simulation, drives it at fixed ticks,
# tells the Map node to render dirty tiles, and relays taps.

@onready var _map: Map = $Map
@onready var _hud: HUD = $HUD

var _simulation: Simulation
var _tick_accumulator: float = 0.0


func _ready() -> void:
	_simulation = Simulation.new()
	_simulation.start_default_match(0)
	_map.setup(_simulation.state)
	_hud.setup(_simulation.state)


func _process(delta: float) -> void:
	_tick_accumulator += delta
	# Guard against spiral-of-death: cap catch-up at a handful of ticks per frame.
	var ticks_this_frame := 0
	while _tick_accumulator >= Balance.TICK_DELTA and ticks_this_frame < 5:
		_tick_accumulator -= Balance.TICK_DELTA
		_simulation.advance_tick()
		ticks_this_frame += 1
	_map.render()
	_hud.update_from_state()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_try_tap(mb.position)
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		if st.pressed:
			_try_tap(st.position)


func _try_tap(screen_pos: Vector2) -> void:
	var tile: Vector2i = _map.screen_to_tile(screen_pos)
	if tile.x < 0:
		return
	if _simulation.state.players.is_empty():
		return
	var local_id: int = _simulation.state.players[0].id
	_simulation.player_expand(local_id, tile.x, tile.y, _hud.send_fraction())
