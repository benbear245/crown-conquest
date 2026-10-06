extends Node

# Player preferences (autoload "Settings"), saved to user://settings.cfg.
# Presentation only: nothing here changes game rules.

signal changed

const PATH: String = "user://settings.cfg"

var left_handed: bool = false
var sound: bool = true
var music: bool = true
var vibration: bool = true
var colorblind: bool = false
# First-time hints already shown (hint id -> true).
var hints_seen: Dictionary = {}
# Vibrations actually sent (used by the smoke tests).
var vibrations_sent: int = 0


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	left_handed = bool(cfg.get_value("ui", "left_handed", left_handed))
	sound = bool(cfg.get_value("audio", "sound", sound))
	music = bool(cfg.get_value("audio", "music", music))
	vibration = bool(cfg.get_value("feel", "vibration", vibration))
	colorblind = bool(cfg.get_value("ui", "colorblind", colorblind))
	var seen: Variant = cfg.get_value("ui", "hints_seen", {})
	hints_seen = seen if seen is Dictionary else {}


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "left_handed", left_handed)
	cfg.set_value("audio", "sound", sound)
	cfg.set_value("audio", "music", music)
	cfg.set_value("feel", "vibration", vibration)
	cfg.set_value("ui", "colorblind", colorblind)
	cfg.set_value("ui", "hints_seen", hints_seen)
	cfg.save(PATH)


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	save_settings()
	changed.emit()


# True the first time a hint id is asked for (and remembers it).
func first_time(hint_id: String) -> bool:
	if hints_seen.has(hint_id):
		return false
	hints_seen[hint_id] = true
	save_settings()
	return true


func reset_hints() -> void:
	hints_seen.clear()
	save_settings()


# Vibrate only if the player allows it.
func vibrate(ms: int = 60) -> void:
	if vibration:
		vibrations_sent += 1
		Input.vibrate_handheld(ms)
