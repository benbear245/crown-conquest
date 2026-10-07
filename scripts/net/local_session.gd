class_name LocalSession
extends GameSession

# Single player against bots: the Simulation runs right here.

const MAX_TICKS_PER_FRAME: int = 5

var _sim: Simulation = Simulation.new()
var _tick_accumulator: float = 0.0


func start(match_seed: int) -> void:
	_sim.start_default_match(match_seed)
	match_ready.emit()


func sim() -> Simulation:
	return _sim


func update(delta: float) -> Array:
	if not paused:
		_tick_accumulator += delta
		var ticks := 0
		while _tick_accumulator >= Balance.TICK_DELTA and ticks < MAX_TICKS_PER_FRAME:
			_tick_accumulator -= Balance.TICK_DELTA
			_sim.advance_tick()
			ticks += 1
		if ticks == MAX_TICKS_PER_FRAME:
			_tick_accumulator = 0.0
	var events: Array = _sim.state.events
	_sim.state.events = []
	return events


func send(cmd: String, args: Array, on_result: Callable = Callable()) -> void:
	var ok: bool = CommandRouter.apply(_sim, _sim.local_player_id, cmd, args)
	if on_result.is_valid():
		on_result.call(ok)
