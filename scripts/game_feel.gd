class_name GameFeel
extends Node

# Turns simulation events into feel: sounds, screen shake, slow motion,
# vibration and music. Presentation only; it never changes the game.

const SLOW_MO_SMALL: Vector2 = Vector2(0.55, 0.35)   # (speed, seconds) when any Crown falls
const SLOW_MO_BIG: Vector2 = Vector2(0.25, 0.9)      # ...when it's yours or you took it

var _sim: Simulation
var _camera: CameraRig
var _slow_speed: float = 1.0
var _slow_left: float = 0.0
var _prev_alert: bool = false
var _ready_abilities: Dictionary = {}   # ability id -> was ready last frame


func setup(sim: Simulation, camera: CameraRig) -> void:
	_sim = sim
	_camera = camera
	_prev_alert = false
	_ready_abilities.clear()
	_slow_left = 0.0
	Audio.music("music_calm_loop")


# Multiplier for simulation time (slow-motion moments).
func time_scale() -> float:
	return _slow_speed if _slow_left > 0.0 else 1.0


func _process(delta: float) -> void:
	if _slow_left > 0.0:
		_slow_left -= delta
	if _sim == null:
		return
	_watch_crown_alert()
	_watch_abilities()


func consume(events: Array) -> void:
	var me: int = _sim.local_player_id
	for e: Dictionary in events:
		match str(e.type):
			"expand":
				if int(e.player_id) == me:
					Audio.play("sfx_expand_tick", -12.0, randf_range(0.9, 1.15))
			"attack_ring":
				if int(e.attacker_id) == me:
					Audio.play("sfx_attack_drum", -8.0, randf_range(0.95, 1.05))
					if int(e.tiles) > 0:
						Audio.play("sfx_capture", -14.0, randf_range(0.9, 1.2))
				elif int(e.defender_id) == me:
					Audio.play("sfx_attack_drum", -4.0, 0.8)
			"crown_fall":
				_crown_fall(int(e.victim_id) == me or int(e.capturer_id) == me)
			"build":
				if int(e.player_id) == me:
					Audio.play("sfx_build", -6.0)
			"ability":
				if int(e.player_id) == me:
					Audio.play("sfx_ability_use", -6.0)
			"loot":
				if int(e.player_id) == me:
					Audio.play("sfx_loot", -6.0)
			"truce":
				if int(e.a) == me or int(e.b) == me:
					Audio.play("sfx_truce", -6.0)
			"final_siege":
				Audio.play("sfx_crown_alarm_horn", -4.0, 0.8)
				Audio.music("music_siege_loop")
			"match_end":
				Audio.music("")
				Audio.play("sfx_victory" if int(e.winner_id) == me else "sfx_defeat")


func _crown_fall(mine: bool) -> void:
	var slow: Vector2 = SLOW_MO_BIG if mine else SLOW_MO_SMALL
	_slow_speed = slow.x
	_slow_left = slow.y
	_camera.shake(16.0 if mine else 6.0, 0.7 if mine else 0.35)
	Audio.play("sfx_crown_fall_big" if mine else "sfx_crown_fall", 0.0 if mine else -6.0)
	Settings.vibrate(350 if mine else 80)


func _watch_crown_alert() -> void:
	var me: Player = _sim.state.get_player(_sim.local_player_id)
	var active: bool = me != null and me.is_alive and me.crown_alert_until > _sim.state.match_time
	if active and not _prev_alert:
		Audio.play("sfx_crown_alarm_horn", -2.0)
		Settings.vibrate(150)
	_prev_alert = active


# A short chime + buzz when one of your abilities comes off cooldown (or unlocks).
func _watch_abilities() -> void:
	var st: GameState = _sim.state
	var me: Player = st.get_player(_sim.local_player_id)
	if me == null or not me.is_alive or st.phase != Balance.PHASE_MATCH:
		_ready_abilities.clear()
		return
	for id in range(4):
		var is_ready: bool = st.match_time >= AbilitiesOps.unlock_sec(id) and AbilitiesOps.cooldown_until(id, me) <= st.match_time
		if is_ready and _ready_abilities.has(id) and not bool(_ready_abilities[id]):
			Audio.play("sfx_ability_ready", -8.0)
			Settings.vibrate(40)
		_ready_abilities[id] = is_ready
