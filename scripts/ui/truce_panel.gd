class_name TrucePanel
extends PanelContainer

# Your truces at a glance: partners with a white flag and a countdown,
# incoming offers (Accept / Decline) and offers you're waiting on.

signal respond(from_id: int, accepted: bool)

const MAX_ROWS: int = 4

var _sim: Simulation
var _vbox: VBoxContainer
var _rows: Array[Dictionary] = []


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_vbox)
	for i in range(MAX_ROWS):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := IconView.new(IconView.Kind.FLAG, 26)
		row.add_child(icon)
		var lbl := UIStyle.label("", UIStyle.FONT_SMALL + 1)
		lbl.custom_minimum_size = Vector2(170, 0)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(lbl)
		var yes := UIStyle.button("Accept", 88)
		yes.alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(yes)
		var no := UIStyle.button("Decline", 88)
		no.alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(no)
		var index: int = i
		yes.pressed.connect(func() -> void: _answer(index, true))
		no.pressed.connect(func() -> void: _answer(index, false))
		_vbox.add_child(row)
		_rows.append({"row": row, "icon": icon, "label": lbl, "yes": yes, "no": no, "from": -1})


func setup(sim: Simulation) -> void:
	_sim = sim


func _answer(i: int, accepted: bool) -> void:
	var from_id: int = int(_rows[i]["from"])
	if from_id > 0:
		respond.emit(from_id, accepted)


func update_view() -> void:
	if _sim == null:
		return
	var st: GameState = _sim.state
	var me: Player = st.get_player(_sim.local_player_id)
	var entries: Array[Array] = []    # [kind, text, offer_from_id]
	if me != null and me.is_alive and st.phase == Balance.PHASE_MATCH:
		for off: Dictionary in st.pending_truces:
			if int(off["to_id"]) == me.id:
				var from_p: Player = st.get_player(int(off["from_id"]))
				entries.append([IconView.Kind.FLAG, "%s offers a truce (%ds)" % [from_p.display_name, int(ceilf(float(off["decide_at"]) - st.match_time))], from_p.id])
		for partner_id: int in me.active_truces.keys():
			var left: float = TrucesOps.truce_time_left(me, partner_id, st.match_time)
			if left > 0.0:
				var partner: Player = st.get_player(partner_id)
				entries.append([IconView.Kind.FLAG, "Truce: %s  %s" % [partner.display_name, GameState.format_time(left)], -1])
		for off: Dictionary in st.pending_truces:
			if int(off["from_id"]) == me.id:
				var to_p: Player = st.get_player(int(off["to_id"]))
				entries.append([IconView.Kind.NONE, "Waiting for %s to answer…" % to_p.display_name, -1])
	visible = not entries.is_empty()
	mouse_filter = Control.MOUSE_FILTER_PASS if visible else Control.MOUSE_FILTER_IGNORE
	for i in range(MAX_ROWS):
		var r: Dictionary = _rows[i]
		if i >= entries.size():
			(r["row"] as Control).visible = false
			r["from"] = -1
			continue
		var e: Array = entries[i]
		(r["row"] as Control).visible = true
		(r["icon"] as IconView).kind = e[0]
		(r["label"] as Label).text = e[1]
		r["from"] = e[2]
		(r["yes"] as Button).visible = int(e[2]) > 0
		(r["no"] as Button).visible = int(e[2]) > 0
