class_name HudHints
extends PanelContainer

# Short first-time hints. Each shows once (remembered in Settings) when its
# moment comes, and goes away when the player does the thing or taps Got it.

const SHOW_SEC: float = 9.0
const HINTS: Dictionary = {
	"place": "Tap a plains, forest or hill tile to place your Crown.",
	"expand": "Tap free land next to your border to expand. The slider sets how many troops you send.",
	"sweet_spot": "Troops grow fastest while the bar is green (35–65% full). Keep spending!",
	"attack": "Peace is over. Tap enemy land next to your border to attack.",
	"build": "Long-press your own land to build Forts, Barracks, Watchtowers and Walls.",
	"spy": "Long-press enemy land to see a rival, offer a truce, or spy on them.",
	"shrine": "Shrines (◆ on the map) bless whoever holds their centre tile. Fight for them!",
	"crown": "Tap ♛ Crown for Keep upgrades, moving your Crown and Disinformation. Double-tap to jump home.",
}

# Hidden (but not dismissed) while a menu or panel is open.
var suppressed: bool = false:
	set(v):
		suppressed = v
		visible = _showing and not v
var _showing: bool = false
var _label: Label
var _current: String = ""
var _until: float = 0.0


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.20, 0.30, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -330
	offset_right = 330
	offset_bottom = -(UI.BOTTOM_BAR_H + UI.MARGIN * 3 + 64)
	offset_top = offset_bottom - 70
	var row := UI.hbox(10)
	add_child(row)
	_label = UI.label("", 17)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_label)
	var ok := UI.button("Got it", 100, 48)
	ok.pressed.connect(func() -> void: done(_current))
	row.add_child(ok)
	visible = false


# Shows the hint if it hasn't been seen and nothing else is showing.
func offer(hint_id: String) -> void:
	if Settings.hints_seen.has(hint_id) or (_showing and _current != hint_id) or not HINTS.has(hint_id):
		return
	if _showing:
		return
	_current = hint_id
	_label.text = HINTS[hint_id]
	_until = Time.get_ticks_msec() / 1000.0 + SHOW_SEC
	_showing = true
	visible = not suppressed


# The player did the thing (or dismissed it): never show this one again.
func done(hint_id: String) -> void:
	Settings.mark_hint_seen(hint_id)
	if hint_id == _current:
		_showing = false
		visible = false
		_current = ""


func _process(_delta: float) -> void:
	if _showing and not suppressed and Time.get_ticks_msec() / 1000.0 > _until:
		done(_current)
