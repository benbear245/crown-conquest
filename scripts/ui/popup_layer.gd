class_name PopupLayer
extends Control

# Floating reward numbers ("+75 loot", "+1,240 plunder") for the local player,
# drawn in screen space above the tile they came from. Reads GameState.popups; draws text directly,
# so there is no node per number.

const RISE_PX: float = 46.0
const FONT_SIZE: int = 24

var _state: GameState
var _local_id: int = 1
var _font: Font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font


func setup(state: GameState, local_player_id: int) -> void:
	_state = state
	_local_id = local_player_id


func _process(_delta: float) -> void:
	if _state != null and not _state.popups.is_empty():
		queue_redraw()


func _draw() -> void:
	if _state == null or _state.popups.is_empty():
		return
	var xf: Transform2D = get_viewport().canvas_transform
	for info: Dictionary in _state.popups:
		if int(info["owner_id"]) != _local_id:
			continue   # only your own rewards float up
		var tile: Vector2i = _state.idx_to_xy(int(info["tile_idx"]))
		var left: float = float(info["until"]) - _state.match_time
		var t: float = clampf(1.0 - left / Simulation.POPUP_SEC, 0.0, 1.0)
		var screen: Vector2 = xf * Vector2(float(tile.x) + 0.5, float(tile.y) + 0.5)
		screen.y -= RISE_PX * t
		var text: String = str(info["text"])
		var font_size: int = FONT_SIZE + (8 if text.contains("plunder") else 0)
		var w: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos: Vector2 = screen - Vector2(w * 0.5, 0.0)
		var alpha: float = 1.0 - t * t
		var col: Color = Palette.player(int(info["owner_id"])).lightened(0.45)
		col.a = alpha
		_font.draw_string_outline(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 6, Color(0, 0, 0, alpha))
		_font.draw_string(get_canvas_item(), pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
