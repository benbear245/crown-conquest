class_name UI
extends RefCounted

# Shared look and small builders for the HUD, so every panel matches.

const MARGIN: int = 16
const TOP_BAR_H: int = 64
const BOTTOM_BAR_H: int = 72
const BUTTON_H: int = 56                       # Balance.MIN_BUTTON_PX
const COLOR_TEXT: Color = Color(0.95, 0.95, 0.95)
const COLOR_DIM: Color = Color(0.70, 0.70, 0.72)
const COLOR_GOOD: Color = Color(0.45, 0.95, 0.55)
const COLOR_WARN: Color = Color(1.0, 0.85, 0.35)
const COLOR_BAD: Color = Color(1.0, 0.45, 0.40)
const PANEL_BG: Color = Color(0.07, 0.08, 0.11, 0.94)


static func label(text: String = "", size: int = 18, color: Color = COLOR_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func button(text: String, min_w: int = 120, h: int = BUTTON_H, size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, maxi(h, 40))
	b.add_theme_font_size_override("font_size", size)
	b.focus_mode = Control.FOCUS_NONE
	return b


# A toggle button whose chosen state is easy to see: gold text and border.
static func toggle(text: String, min_w: int = 120, h: int = BUTTON_H, size: int = 18) -> Button:
	var b := button(text, min_w, h, size)
	b.toggle_mode = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.19, 0.08)
	sb.border_color = COLOR_WARN
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("hover_pressed", sb)
	b.add_theme_color_override("font_pressed_color", COLOR_WARN)
	b.add_theme_color_override("font_hover_pressed_color", COLOR_WARN)
	return b


# The one main action on a screen: gold with dark text.
static func primary_button(text: String, min_w: int = 120, h: int = BUTTON_H, size: int = 22) -> Button:
	var b := button(text, min_w, h, size)
	var gold := Color(1.0, 0.78, 0.22)
	b.add_theme_stylebox_override("normal", _flat(gold, 10))
	b.add_theme_stylebox_override("hover", _flat(gold.lightened(0.15), 10))
	b.add_theme_stylebox_override("pressed", _flat(gold.darkened(0.2), 10))
	b.add_theme_stylebox_override("disabled", _flat(Color(0.3, 0.3, 0.3), 10))
	var ink := Color(0.12, 0.08, 0.02)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, ink)
	return b


# A clearly tappable secondary button: outlined in the accent colour.
static func outline_button(text: String, accent: Color, min_w: int = 120, h: int = BUTTON_H, size: int = 20) -> Button:
	var b := button(text, min_w, h, size)
	var normal := _flat(Color(0.15, 0.16, 0.21), 10)
	normal.border_color = Color(accent, 0.7)
	normal.set_border_width_all(2)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.20, 0.21, 0.27)
	hover.border_color = accent
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(accent, 0.25)
	pressed.border_color = accent
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, accent.lerp(Color.WHITE, 0.35))
	return b


# A rounded box for a group of related actions, with a coloured top edge.
static func card(accent: Color, pad: int = 20) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _flat(Color(0.09, 0.10, 0.14, 0.97), 14)
	sb.border_color = accent
	sb.border_width_top = 5
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func _flat(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	return sb


static func panel(pad: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	return p


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


# Anchors a control to one side (left or right) with a fixed width, mirrored
# for the left-handed layout.
static func dock_side(c: Control, on_left: bool, width: float, top: float, bottom: float, anchor_bottom: bool = false) -> void:
	var a: float = 0.0 if on_left else 1.0
	c.anchor_left = a
	c.anchor_right = a
	c.anchor_top = 1.0 if anchor_bottom else 0.0
	c.anchor_bottom = 1.0 if anchor_bottom else 0.0
	if on_left:
		c.offset_left = MARGIN
		c.offset_right = MARGIN + width
	else:
		c.offset_left = -(MARGIN + width)
		c.offset_right = -MARGIN
	c.offset_top = top
	c.offset_bottom = bottom


static func centre(c: Control, w: float, h: float) -> void:
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.offset_left = -w * 0.5
	c.offset_right = w * 0.5
	c.offset_top = -h * 0.5
	c.offset_bottom = h * 0.5
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


static func clear_children(c: Node) -> void:
	for ch in c.get_children():
		c.remove_child(ch)
		ch.queue_free()
