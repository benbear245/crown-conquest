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
