class_name GameSession
extends RefCounted

# What the game scene plays through. A LocalSession runs the Simulation on
# this device; a NetSession mirrors a match running on a host. Either way the
# scene reads sim() to draw, sends commands with send(), and presents the
# events update() returns.

@warning_ignore("unused_signal")
signal match_ready
@warning_ignore("unused_signal")
signal lobby_changed(names: Array, is_host: bool)
@warning_ignore("unused_signal")
signal ended(reason: String)

var online: bool = false
var paused: bool = false


func sim() -> Simulation:
	return null


# Advances the match (or reads the host's updates) and returns new events.
func update(_delta: float) -> Array:
	return []


# on_result gets true/false once the match has accepted or refused it.
func send(_cmd: String, _args: Array, _on_result: Callable = Callable()) -> void:
	pass


func request_start() -> void:
	pass


func close() -> void:
	pass
