class_name HudBanners
extends VBoxContainer

# A queue of banners under the top bar. Up to MAX_VISIBLE show at once and
# each fades after its time; they never cover the controls at the bottom.
# Some banners have buttons (truce offers) or can be tapped (Crown alert).

signal truce_answered(from_id: int, accepted: bool)
signal crown_alert_tapped

const MAX_VISIBLE: int = 3
const WIDTH: int = 680
const DEFAULT_SEC: float = 4.0

# Each entry: {node, until, key}
var _live: Array[Dictionary] = []
var _queue: Array[Dictionary] = []


func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = UI.TOP_BAR_H + 44
	offset_bottom = offset_top + MAX_VISIBLE * 60
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func push_text(text: String, color: Color = UI.COLOR_TEXT, seconds: float = DEFAULT_SEC) -> void:
	_queue.append({"kind": "text", "text": text, "color": color, "sec": seconds})


func push_crown_alert() -> void:
	if _has_key("crown_alert"):
		return
	_queue.push_front({"kind": "alert", "sec": 3.0, "key": "crown_alert"})


func push_truce_offer(from_id: int, from_name: String, seconds: float) -> void:
	_queue.push_front({"kind": "truce", "from_id": from_id, "text": from_name, "sec": seconds, "key": "truce_%d" % from_id})


func remove_key(key: String) -> void:
	for e in _live:
		if e.get("key", "") == key:
			e["until"] = 0.0


func _has_key(key: String) -> bool:
	for e in _live:
		if e.get("key", "") == key:
			return true
	for e in _queue:
		if e.get("key", "") == key:
			return true
	return false


func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	for i in range(_live.size() - 1, -1, -1):
		var e: Dictionary = _live[i]
		var left: float = float(e["until"]) - now
		var node: Control = e["node"]
		node.modulate.a = clampf(left / 0.4, 0.0, 1.0)
		if left <= 0.0:
			node.queue_free()
			_live.remove_at(i)
	while _live.size() < MAX_VISIBLE and not _queue.is_empty():
		var spec: Dictionary = _queue.pop_front()
		var node: Control = _make(spec)
		add_child(node)
		if spec.get("kind", "") != "text":
			move_child(node, 0)
		_live.append({"node": node, "until": now + float(spec["sec"]), "key": spec.get("key", "")})


func _make(spec: Dictionary) -> Control:
	var p := UI.panel(8)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	match String(spec["kind"]):
		"alert":
			var b := UI.button("⚠ Crown under attack — tap to jump", WIDTH - 16, 44, 20)
			b.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
			b.pressed.connect(func() -> void: crown_alert_tapped.emit())
			p.add_child(b)
		"truce":
			var row := UI.hbox(10)
			p.add_child(row)
			var l := UI.label("%s offers a truce" % String(spec["text"]), 19)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			var from_id: int = int(spec["from_id"])
			var key: String = String(spec["key"])
			var yes := UI.button("Accept", 110, 44)
			yes.pressed.connect(func() -> void:
				truce_answered.emit(from_id, true)
				remove_key(key))
			row.add_child(yes)
			var no := UI.button("Decline", 110, 44)
			no.pressed.connect(func() -> void:
				truce_answered.emit(from_id, false)
				remove_key(key))
			row.add_child(no)
		_:
			var l := UI.label(String(spec["text"]), 20, spec.get("color", UI.COLOR_TEXT))
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			p.add_child(l)
	return p


func clear_all() -> void:
	_queue.clear()
	for e in _live:
		(e["node"] as Node).queue_free()
	_live.clear()
