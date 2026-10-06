extends Node

# Sound effects and music (autoload "Audio"). Files live in assets/audio/ and
# are looked up by name, so any placeholder can be replaced by a real sound
# with the same name (.ogg or .wav). Respects the Sound / Music settings.

const DIR: String = "res://assets/audio/"
const SFX_PLAYERS: int = 8
# Shortest gap between two plays of the same sound (keeps busy moments calm).
const MIN_GAP_SEC: Dictionary = {
	"sfx_expand_tick": 0.12, "sfx_attack_drum": 0.35, "sfx_capture": 0.08, "sfx_loot": 0.15,
}
const MUSIC_DB: float = -14.0
const FADE_SEC: float = 2.0

var _sfx: Array[AudioStreamPlayer] = []
var _next: int = 0
var _streams: Dictionary = {}
var _last_played: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_name: String = ""
# How many times each sound actually started (used by the smoke tests).
var play_counts: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(SFX_PLAYERS):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_sfx.append(p)
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	Settings.changed.connect(_apply_settings)


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = -80.0
	p.finished.connect(func() -> void: if p.volume_db > -79.0: p.play())   # loop
	add_child(p)
	return p


func _stream(sound: String) -> AudioStream:
	if _streams.has(sound):
		return _streams[sound]
	var s: AudioStream = null
	for ext: String in [".ogg", ".wav", ".mp3"]:
		if ResourceLoader.exists(DIR + sound + ext):
			s = load(DIR + sound + ext)
			break
	_streams[sound] = s
	return s


func play(sound: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not Settings.sound:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sound, -10.0)) < float(MIN_GAP_SEC.get(sound, 0.0)):
		return
	var s: AudioStream = _stream(sound)
	if s == null:
		return
	_last_played[sound] = now
	play_counts[sound] = int(play_counts.get(sound, 0)) + 1
	var p: AudioStreamPlayer = _sfx[_next]
	_next = (_next + 1) % _sfx.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()


func current_music() -> String:
	return _music_name


# Switch music with a crossfade ("music_calm_loop", "music_siege_loop", or "" to stop).
func music(track: String) -> void:
	if track == _music_name:
		return
	_music_name = track
	var incoming: AudioStreamPlayer = _music_b if _music_a.playing and _music_a.volume_db > -79.0 else _music_a
	var outgoing: AudioStreamPlayer = _music_a if incoming == _music_b else _music_b
	var tw := create_tween().set_parallel(true)
	tw.tween_property(outgoing, "volume_db", -80.0, FADE_SEC)
	if track != "" and Settings.music:
		incoming.stream = _stream(track)
		if incoming.stream != null:
			incoming.volume_db = -40.0
			incoming.play()
			tw.tween_property(incoming, "volume_db", MUSIC_DB, FADE_SEC)
	tw.chain().tween_callback(func() -> void: if outgoing.volume_db <= -79.0: outgoing.stop())


func _apply_settings() -> void:
	if not Settings.music:
		for p: AudioStreamPlayer in [_music_a, _music_b]:
			p.stop()
			p.volume_db = -80.0
	elif _music_name != "" and not _music_a.playing and not _music_b.playing:
		var wanted: String = _music_name
		_music_name = ""
		music(wanted)
