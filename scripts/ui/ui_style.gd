class_name UIStyle
extends RefCounted

# Shared look for the code-built HUD: colours, label outlines, panel and
# button styles. Keeps every panel consistent without a .tres theme file.

const COLOR_TEXT: Color = Color(0.95, 0.95, 0.95)
const COLOR_DIM: Color = Color(0.70, 0.70, 0.74)
const COLOR_GOOD: Color = Color(0.45, 0.95, 0.55)
const COLOR_BAD: Color = Color(1.00, 0.50, 0.45)
const COLOR_WARN: Color = Color(1.00, 0.90, 0.40)
const PANEL_BG: Color = Color(0.07, 0.08, 0.11, 0.86)
const FONT_SMALL: int = 15
const FONT_NORMAL: int = 18
const FONT_LARGE: int = 24


static func label(text: String = "", font_size: int = FONT_NORMAL, color: Color = COLOR_TEXT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	style_label(lbl, font_size, color)
	return lbl


static func style_label(lbl: Label, font_size: int = FONT_NORMAL, color: Color = COLOR_TEXT) -> void:
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func panel_style(radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


static func panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style())
	return p


# A thumb-sized button. Multi-line text is fine (title on line 1, detail on 2).
static func button(text: String, min_width: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, Balance.MIN_BUTTON_PX)
	b.add_theme_font_size_override("font_size", FONT_SMALL + 1)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	return b
