extends Node2D

# Root of the game scene. Owns the Simulation, drives it at fixed ticks,
# and tells the Map node to render the dirty tiles once per frame.

@onready var _map: Map = $Map

var _simulation: Simulation
var _tick_accumulator: float = 0.0


func _ready() -> void:
	_simulation = Simulation.new()
	_simulation.start_default_match(0)
	_map.setup(_simulation.state)


func _process(delta: float) -> void:
	_tick_accumulator += delta
	# Guard against spiral-of-death: cap catch-up at ~5 ticks per frame.
	var ticks_this_frame := 0
	while _tick_accumulator >= Balance.TICK_DELTA and ticks_this_frame < 5:
		_tick_accumulator -= Balance.TICK_DELTA
		_simulation.advance_tick()
		ticks_this_frame += 1
	_map.render()
