class_name GameAudio
extends Node

# Sound effects and music. The files in assets/audio/ are placeholders with
# clear names; drop in real sounds with the same names to replace them.

const SFX: Dictionary = {
	"expand": "res://assets/audio/sfx_expand_tick.wav",
	"tap": "res://assets/audio/sfx_ui_tap.wav",
	"attack": "res://assets/audio/sfx_attack_drums.wav",
	"crown_alarm": "res://assets/audio/sfx_crown_alarm.wav",
	"crown_fall": "res://assets/audio/sfx_crown_fall.wav",
	"ability_ready": "res://assets/audio/sfx_ability_ready.wav",
	"spy": "res://assets/audio/sfx_spy.wav",
	"shrine": "res://assets/audio/sfx_shrine.wav",
	"loot": "res://assets/audio/sfx_loot.wav",
}
const MUSIC_CALM: String = "res://assets/audio/music_calm.wav"
const MUSIC_SIEGE: String = "res://assets/audio/music_siege.wav"
const VOICES: int = 6
# Quiet repeats of the same sound so a burst of captures doesn't turn into noise.
const MIN_REPEAT_SEC: float = 0.08

var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next_voice: int = 0
var _last_played: Dictionary = {}
var _music: AudioStreamPlayer
var _music_path: String = ""


func _ready() -> void:
	for key: String in SFX.keys():
		_streams[key] = load(SFX[key])
	for i in range(VOICES):
		var v := AudioStreamPlayer.new()
		add_child(v)
		_voices.append(v)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -10.0
	_music.finished.connect(func() -> void: _music.play())
	add_child(_music)
	Settings.changed.connect(_on_settings_changed)


func play(key: String, volume_db: float = 0.0) -> void:
	if not Settings.sound or not _streams.has(key):
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(key, -1.0)) < MIN_REPEAT_SEC:
		return
	_last_played[key] = now
	var v: AudioStreamPlayer = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	v.stream = _streams[key]
	v.volume_db = volume_db
	v.play()


# Calm music normally; the intense track during the Final Siege.
func set_siege_music(siege: bool) -> void:
	var path: String = MUSIC_SIEGE if siege else MUSIC_CALM
	if path == _music_path and (_music.playing or not Settings.music):
		return
	_music_path = path
	_music.stream = load(path)
	if Settings.music:
		_music.play()


func stop_music() -> void:
	_music.stop()


func _on_settings_changed() -> void:
	if not Settings.music:
		_music.stop()
	elif _music_path != "" and not _music.playing:
		_music.play()


# Stop and drop streams on exit so nothing is still playing when Godot
# shuts the audio server down (otherwise it reports leaked playbacks).
func _exit_tree() -> void:
	_music.stop()
	_music.stream = null
	for v in _voices:
		v.stop()
		v.stream = null
