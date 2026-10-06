class_name Leaderboard
extends PanelContainer

# Top 5 players by land. Crown icon while alive (skull once out), a star for
# the Rising Empire, and a white flag with the time left for your truces.
# In Teams it ranks the teams by their combined land instead.

const ROWS: int = 5

var _sim: Simulation
var _rows: Array[Dictionary] = []
var _title: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)
	_title = UIStyle.label("Leaderboard", UIStyle.FONT_NORMAL)
	vbox.add_child(_title)
	for i in range(ROWS):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(row)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(14, 22)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(swatch)
		var status := IconView.new(IconView.Kind.CROWN, 22)
		row.add_child(status)
		var name_label := UIStyle.label("", UIStyle.FONT_SMALL + 1)
		name_label.custom_minimum_size = Vector2(150, 22)
		name_label.clip_text = true
		row.add_child(name_label)
		var rising := IconView.new(IconView.Kind.STAR, 22)
		row.add_child(rising)
		var flag := IconView.new(IconView.Kind.FLAG, 22)
		row.add_child(flag)
		var truce_label := UIStyle.label("", UIStyle.FONT_SMALL)
		truce_label.custom_minimum_size = Vector2(36, 22)
		row.add_child(truce_label)
		var land_label := UIStyle.label("", UIStyle.FONT_SMALL + 1)
		land_label.custom_minimum_size = Vector2(56, 22)
		land_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(land_label)
		_rows.append({"row": row, "swatch": swatch, "status": status, "name": name_label,
			"rising": rising, "flag": flag, "truce": truce_label, "land": land_label})


func setup(sim: Simulation) -> void:
	_sim = sim


func update_view() -> void:
	if _sim == null:
		return
	var st: GameState = _sim.state
	_title.text = "Teams" if st.teams_mode else "Leaderboard"
	if st.teams_mode:
		_update_teams(st)
		return
	var ranked: Array[Player] = st.players.duplicate()
	ranked.sort_custom(func(a: Player, b: Player) -> bool: return a.land > b.land)
	var me: Player = st.get_player(_sim.local_player_id)
	var rising_id: int = _sim.rising_empire_id()
	for i in range(ROWS):
		var r: Dictionary = _rows[i]
		if i >= ranked.size():
			(r["row"] as Control).visible = false
			continue
		var p: Player = ranked[i]
		(r["row"] as Control).visible = true
		(r["swatch"] as ColorRect).color = Palette.player(p.id) if p.is_alive else Color(0.25, 0.25, 0.25)
		(r["status"] as IconView).kind = IconView.Kind.CROWN if p.is_alive else IconView.Kind.SKULL
		(r["name"] as Label).text = p.display_name
		(r["rising"] as IconView).visible = p.id == rising_id
		var truce_left: float = 0.0
		if me != null and p.id != me.id:
			truce_left = TrucesOps.truce_time_left(me, p.id, st.match_time)
		(r["flag"] as IconView).visible = truce_left > 0.0
		(r["truce"] as Label).text = ("%d" % int(ceilf(truce_left))) if truce_left > 0.0 else ""
		(r["land"] as Label).text = "%.1f%%" % (100.0 * st.land_fraction(p))


func _update_teams(st: GameState) -> void:
	var me: Player = st.get_player(_sim.local_player_id)
	var teams: Array[int] = []
	for p: Player in st.players:
		if not teams.has(p.team):
			teams.append(p.team)
	teams.sort_custom(func(a: int, b: int) -> bool: return _sim.team_land(a) > _sim.team_land(b))
	var usable: float = float(maxi(st.total_usable_tiles(), 1))
	for i in range(ROWS):
		var r: Dictionary = _rows[i]
		if i >= teams.size():
			(r["row"] as Control).visible = false
			continue
		var team: int = teams[i]
		var alive: bool = false
		var first: Player = null
		for p: Player in st.players:
			if p.team == team:
				alive = alive or p.is_alive
				if first == null:
					first = p
		(r["row"] as Control).visible = true
		(r["swatch"] as ColorRect).color = Palette.player(first.id) if alive else Color(0.25, 0.25, 0.25)
		(r["status"] as IconView).kind = IconView.Kind.CROWN if alive else IconView.Kind.SKULL
		var label: String = _sim.team_name(team)
		if me != null and me.team == team:
			label += " (you)"
		(r["name"] as Label).text = label
		(r["rising"] as IconView).visible = false
		(r["flag"] as IconView).visible = false
		(r["truce"] as Label).text = ""
		(r["land"] as Label).text = "%.1f%%" % (100.0 * float(_sim.team_land(team)) / usable)
