class_name HudTutorial
extends Control

# The tutorial's guide card (step, text, Next and Skip) and a bouncing arrow
# pointing at the thing to tap.

signal next_pressed
signal skip_pressed

const CARD_W: int = 520
const ARROW_COLOR: Color = Color(1.0, 0.85, 0.25)

var _card: PanelContainer
var _step: Label
var _text: Label
var _next: Button
var _arrow_at: Vector2 = Vector2(-1, -1)
var _time: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = UI.panel(14)
	var sb: StyleBoxFlat = _card.get_theme_stylebox("panel").duplicate()
	sb.border_color = ARROW_COLOR
	sb.set_border_width_all(3)
	_card.add_theme_stylebox_override("panel", sb)
	add_child(_card)
	var v := UI.vbox(8)
	_card.add_child(v)
	_step = UI.label("", 16, UI.COLOR_WARN)
	v.add_child(_step)
	_text = UI.label("", 21)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(CARD_W - 28, 0)
	v.add_child(_text)
	var row := UI.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var skip := UI.button("Skip tutorial", 190, 48, 17)
	skip.pressed.connect(func() -> void: skip_pressed.emit())
	row.add_child(skip)
	_next = UI.button("Next", 150, 48, 18)
	_next.pressed.connect(func() -> void: next_pressed.emit())
	row.add_child(_next)
	visible = false


# The card sits on the side away from the leaderboard, below the banners.
func apply_side(left_handed: bool) -> void:
	UI.dock_side(_card, not left_handed, CARD_W, UI.TOP_BAR_H + 60, UI.TOP_BAR_H + 60)


func show_step(index: int, total: int, text: String, show_next: bool, arrow_screen: Vector2) -> void:
	visible = true
	_step.text = "Tutorial — step %d of %d" % [index + 1, total]
	_text.text = text
	_next.visible = show_next
	_arrow_at = arrow_screen
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if visible and _arrow_at.x >= 0.0:
		queue_redraw()


# Arrow above the target, pointing down at it.
func _draw() -> void:
	if _arrow_at.x < 0.0:
		return
	var tip: Vector2 = _arrow_at + Vector2(0, -10.0 - 10.0 * absf(sin(_time * 4.0)))
	var pts := PackedVector2Array([tip, tip + Vector2(-26, -36), tip + Vector2(-10, -36),
		tip + Vector2(-10, -80), tip + Vector2(10, -80), tip + Vector2(10, -36), tip + Vector2(26, -36)])
	draw_colored_polygon(pts, ARROW_COLOR)
	pts.append(pts[0])
	draw_polyline(pts, Color.BLACK, 3.0)
