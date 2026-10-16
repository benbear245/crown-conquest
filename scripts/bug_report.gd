class_name BugReport
extends Logger

# Keeps the last few log lines and errors in memory so a tester can tap
# "Report a problem" and paste them to the developer. Godot may call the
# logger from any thread, hence the mutex.

const MAX_LINES: int = 120

static var _instance: BugReport

var _lines: PackedStringArray = PackedStringArray()
var _errors: int = 0
var _mutex := Mutex.new()


static func install() -> void:
	if _instance == null:
		_instance = BugReport.new()
		OS.add_logger(_instance)


func _log_message(message: String, error: bool) -> void:
	_add(("ERR " if error else "") + message.strip_edges())


func _log_error(function: String, file: String, line: int, code: String, rationale: String,
		_editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var kind: String = ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"][clampi(error_type, 0, 3)]
	var text: String = "%s: %s (%s:%d %s)" % [kind, rationale if rationale != "" else code, file.get_file(), line, function]
	if not script_backtraces.is_empty():
		text += "\n" + script_backtraces[0].format(2)
	_mutex.lock()
	_errors += 1
	_mutex.unlock()
	_add(text)


func _add(text: String) -> void:
	if text == "":
		return
	_mutex.lock()
	_lines.append("[%s] %s" % [Time.get_time_string_from_system(), text])
	if _lines.size() > MAX_LINES:
		_lines = _lines.slice(_lines.size() - MAX_LINES)
	_mutex.unlock()


# Device and build details plus the recent log, ready to paste in a message.
static func build_text(extra: String = "") -> String:
	var lines := PackedStringArray()
	var errors: int = 0
	if _instance != null:
		_instance._mutex.lock()
		lines = _instance._lines.duplicate()
		errors = _instance._errors
		_instance._mutex.unlock()
	var out: Array[String] = [
		"Crown Conquest %s — problem report" % version_label(),
		"Device: %s, %s %s" % [OS.get_model_name(), OS.get_name(), OS.get_version()],
		"Screen: %s, %s" % [str(DisplayServer.screen_get_size()), Time.get_datetime_string_from_system()],
		"Errors this session: %d" % errors,
	]
	if extra != "":
		out.append(extra)
	out.append("--- recent log ---")
	out.append("\n".join(lines))
	return "\n".join(out)


static func version_label() -> String:
	return "v%s" % String(ProjectSettings.get_setting("application/config/version", "0.0.0"))
