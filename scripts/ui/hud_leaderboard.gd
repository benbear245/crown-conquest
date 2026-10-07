class_name HudLeaderboard
extends PanelContainer

# Top players by land. Markers: ★ Rising Empire, ⚑ truce with you,
# ◆ holds a Shrine, ✝ Crown lost. You always get a row, even outside the top 5.

const ROWS: int = 5
const WIDTH: int = 280

var _rows: Array[Dictionary] = []


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := UI.vbox(4)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	v.add_child(UI.label("Leaderboard", 16, UI.COLOR_DIM))
	for i in range(ROWS + 1):
		var row := UI.hbox(8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(row)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		var name_l := UI.label("", 17)
		name_l.custom_minimum_size = Vector2(180, 0)
		name_l.clip_text = true
		row.add_child(name_l)
		var land_l := UI.label("", 17)
		land_l.custom_minimum_size = Vector2(56, 0)
		land_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(land_l)
		_rows.append({"row": row, "swatch": swatch, "name": name_l, "land": land_l})


func apply_side(left_handed: bool) -> void:
	# Leaderboard sits on the side opposite the thumb-heavy controls.
	UI.dock_side(self, left_handed, WIDTH, UI.TOP_BAR_H + 44, UI.TOP_BAR_H + 44 + 40 + (ROWS + 1) * 27)


func refresh(sim: Simulation, local: Player) -> void:
	var state: GameState = sim.state
	var ranked: Array[Player] = state.players.duplicate()
	ranked.sort_custom(func(a: Player, b: Player) -> bool:
		if a.is_alive != b.is_alive:
			return a.is_alive
		return a.land > b.land)
	var shown: Array[Player] = ranked.slice(0, ROWS)
	var local_rank: int = ranked.find(local)
	if local != null and local_rank >= ROWS:
		shown.append(local)
	for i in range(_rows.size()):
		var r: Dictionary = _rows[i]
		var row: HBoxContainer = r["row"]
		if i >= shown.size():
			row.visible = false
			continue
		row.visible = true
		var p: Player = shown[i]
		var rank: int = ranked.find(p) + 1
		(r["swatch"] as ColorRect).color = Balance.color_for_player(p.id) if p.is_alive else Color(0.25, 0.25, 0.25)
		(r["name"] as Label).text = "%d. %s%s" % [rank, p.display_name, _markers(sim, p, local)]
		(r["name"] as Label).add_theme_color_override("font_color", UI.COLOR_WARN if p == local else (UI.COLOR_TEXT if p.is_alive else UI.COLOR_DIM))
		(r["land"] as Label).text = "%.1f%%" % (100.0 * state.land_fraction(p))


func _markers(sim: Simulation, p: Player, local: Player) -> String:
	var m: String = ""
	if not p.is_alive:
		return " ✝"
	if sim.rising_empire_id() == p.id:
		m += " ★"
	if local != null and p != local and TrucesOps.has_truce(local, p.id, sim.state.match_time):
		m += " ⚑"
	for s: Shrine in sim.state.shrines:
		if s.holder_id == p.id:
			m += " ◆"
	return m
