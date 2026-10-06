class_name AlertQueue
extends VBoxContainer

# Banners stacked at the top of the screen (between the side panels, so they
# never cover the controls). Each banner fades after its time; banners with
# the same id replace each other instead of piling up.

signal action_pressed(id: String)

const MAX_BANNERS: int = 3
const COLORS: Dictionary = {
	"info": Color(0.20, 0.35, 0.60, 0.92),
	"event": Color(0.45, 0.33, 0.08, 0.94),
	"warning": Color(0.55, 0.12, 0.10, 0.94),
	"achievement": Color(0.62, 0.45, 0.05, 0.96),
}

var _banners: Array[Dictionary] = []   # {id, panel, label, until}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	alignment = BoxContainer.ALIGNMENT_BEGIN


# kind: "info" (hints), "event" (announcements), "warning" (your Crown),
# "achievement" (gold, an achievement was just earned).
# action: optional button text; pressing it emits action_pressed(id).
func push(text: String, kind: String = "event", seconds: float = 4.0, id: String = "", action: String = "") -> void:
	var until: float = Time.get_ticks_msec() / 1000.0 + seconds
	if id != "":
		for b: Dictionary in _banners:
			if b.id == id:
				(b.label as Label).text = text
				b.until = until
				return
	var panel := PanelContainer.new()
	var sb := UIStyle.panel_style(10)
	sb.bg_color = COLORS.get(kind, COLORS["event"])
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE if action == "" else Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var lbl := UIStyle.label(text, UIStyle.FONT_NORMAL)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(200, 0)
	row.add_child(lbl)
	if action != "":
		var btn := UIStyle.button(action, 120)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.pressed.connect(func() -> void: action_pressed.emit(id))
		row.add_child(btn)
	add_child(panel)
	_banners.append({"id": id, "panel": panel, "label": lbl, "until": until})
	while _banners.size() > MAX_BANNERS:
		_remove(0)


func dismiss(id: String) -> void:
	for i in range(_banners.size()):
		if _banners[i].id == id:
			_remove(i)
			return


func has_banner(id: String) -> bool:
	for b: Dictionary in _banners:
		if b.id == id:
			return true
	return false


func clear_all() -> void:
	while not _banners.is_empty():
		_remove(0)


func _remove(i: int) -> void:
	(_banners[i].panel as Node).queue_free()
	_banners.remove_at(i)


func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var i: int = 0
	while i < _banners.size():
		var left: float = float(_banners[i].until) - now
		if left <= 0.0:
			_remove(i)
			continue
		(_banners[i].panel as Control).modulate.a = clampf(left / 0.4, 0.0, 1.0)
		i += 1
