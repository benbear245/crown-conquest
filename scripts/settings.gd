extends Node

# Player settings (autoload "Settings"). Saved to user://settings.cfg with a
# temp-file-then-rename write so a crash can't leave a half-written file.
# Presentation only: the simulation never reads these.

signal changed

const PATH: String = "user://settings.cfg"
const TMP_PATH: String = "user://settings.cfg.tmp"

var sound: bool = true
var music: bool = true
var vibration: bool = true
var colorblind: bool = false
var left_handed: bool = false
var player_name: String = ""
var last_address: String = ""
# First-time hints already shown: hint id -> true.
var hints_seen: Dictionary = {}


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		_apply()
		return
	sound = bool(cfg.get_value("audio", "sound", true))
	music = bool(cfg.get_value("audio", "music", true))
	vibration = bool(cfg.get_value("feel", "vibration", true))
	colorblind = bool(cfg.get_value("display", "colorblind", false))
	left_handed = bool(cfg.get_value("display", "left_handed", false))
	player_name = String(cfg.get_value("online", "name", ""))
	last_address = String(cfg.get_value("online", "last_address", ""))
	var seen: Variant = cfg.get_value("hints", "seen", {})
	hints_seen = seen if seen is Dictionary else {}
	_apply()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sound", sound)
	cfg.set_value("audio", "music", music)
	cfg.set_value("feel", "vibration", vibration)
	cfg.set_value("display", "colorblind", colorblind)
	cfg.set_value("display", "left_handed", left_handed)
	cfg.set_value("hints", "seen", hints_seen)
	cfg.set_value("online", "name", player_name)
	cfg.set_value("online", "last_address", last_address)
	if cfg.save(TMP_PATH) != OK:
		push_warning("Settings could not be saved.")
		return
	var dir := DirAccess.open("user://")
	if dir != null:
		dir.rename(TMP_PATH.get_file(), PATH.get_file())


func set_value(key: String, value: bool) -> void:
	match key:
		"sound":
			sound = value
		"music":
			music = value
		"vibration":
			vibration = value
		"colorblind":
			colorblind = value
		"left_handed":
			left_handed = value
	_apply()
	save_settings()
	changed.emit()


func set_text(key: String, value: String) -> void:
	match key:
		"player_name":
			player_name = value.left(16)
		"last_address":
			last_address = value
	save_settings()


func mark_hint_seen(hint_id: String) -> void:
	if hints_seen.has(hint_id):
		return
	hints_seen[hint_id] = true
	save_settings()


func reset_hints() -> void:
	hints_seen.clear()
	save_settings()


func vibrate(ms: int) -> void:
	if vibration:
		Input.vibrate_handheld(ms)


func _apply() -> void:
	Balance.colorblind_mode = colorblind
