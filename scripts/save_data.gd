extends Node

# Everything the game remembers between sessions (autoload "SaveData"):
# Daily Challenge scores now, progression later. Saved to user://save.json
# safely: written to a temp file, read back to check it, then renamed over
# the old save, so a crash mid-write can't wipe progress.

signal saved

const PATH: String = "user://save.json"
const TMP_PATH: String = "user://save.json.tmp"
const VERSION: int = 1

var data: Dictionary = {}


func _ready() -> void:
	load_save()


static func defaults() -> Dictionary:
	return {
		"version": VERSION,
		"daily": {"best_by_date": {}, "best_ever": 0, "played": 0},
	}


func load_save() -> void:
	var loaded: Variant = _read_json(PATH)
	if loaded == null:
		loaded = _read_json(TMP_PATH)   # crashed between write and rename
	data = defaults()
	if loaded is Dictionary:
		_merge(data, loaded)


func save() -> bool:
	var text: String = JSON.stringify(data, "\t")
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("SaveData: can't write %s" % TMP_PATH)
		return false
	f.store_string(text)
	f.close()
	if not (_read_json(TMP_PATH) is Dictionary):
		push_warning("SaveData: temp save didn't read back; keeping the old save")
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		return false
	if dir.file_exists(PATH.get_file()):
		dir.remove(PATH.get_file())
	if dir.rename(TMP_PATH.get_file(), PATH.get_file()) != OK:
		push_warning("SaveData: rename failed; the temp save is kept")
		return false
	saved.emit()
	return true


# --- Daily Challenge -----------------------------------------------------------

func daily_best(date: String) -> int:
	return int((data.daily.best_by_date as Dictionary).get(date, -1))


func daily_best_ever() -> int:
	return int(data.daily.best_ever)


# Records a Daily score. Returns true if it's a new best for that day.
func submit_daily(date: String, score: int) -> bool:
	var by_date: Dictionary = data.daily.best_by_date
	var is_best: bool = score > int(by_date.get(date, -1))
	if is_best:
		by_date[date] = score
	data.daily.best_ever = maxi(int(data.daily.best_ever), score)
	data.daily.played = int(data.daily.played) + 1
	save()
	return is_best


# --- Helpers -------------------------------------------------------------------

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else null


# Copies saved values over the defaults, keeping new default keys that an
# older save doesn't have yet.
static func _merge(into: Dictionary, from: Dictionary) -> void:
	for k: Variant in from.keys():
		if into.has(k) and into[k] is Dictionary and from[k] is Dictionary:
			_merge(into[k], from[k])
		else:
			into[k] = from[k]
