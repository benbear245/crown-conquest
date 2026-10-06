class_name KeepPanel
extends PanelContainer

# Tap your Crown: buy Keep 1-3 (with unlock times and effects) or move the
# Crown once per match.

signal buy_keep_requested(level: int)
signal move_crown_requested
signal closed

const REFRESH_SEC: float = 0.25

var _sim: Simulation
var _title: Label
var _keep_rows: Array[Button] = []
var _move_row: Button
var _refresh_left: float = 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	_title = UIStyle.label("Your Crown", UIStyle.FONT_LARGE)
	vbox.add_child(_title)
	for i in range(1, Balance.KEEP_COST.size()):
		var btn := UIStyle.button("", 400)
		var lvl: int = i
		btn.pressed.connect(func() -> void: buy_keep_requested.emit(lvl))
		vbox.add_child(btn)
		_keep_rows.append(btn)
	_move_row = UIStyle.button("", 400)
	_move_row.pressed.connect(_on_move_pressed)
	vbox.add_child(_move_row)
	var close := UIStyle.button("Close", 400)
	close.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.pressed.connect(close_panel)
	vbox.add_child(close)


func setup(sim: Simulation) -> void:
	_sim = sim


func open_panel() -> void:
	visible = true
	_refresh()


func close_panel() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh()


func _refresh() -> void:
	_refresh_left = REFRESH_SEC
	if _sim == null:
		return
	var me: Player = _sim.state.get_player(_sim.local_player_id)
	if me == null or not me.is_alive or me.crown_x < 0 or _sim.state.phase != Balance.PHASE_MATCH:
		close_panel()
		return
	var siege: bool = _sim.state.is_final_siege()
	_title.text = "Your Crown — Keep %d%s" % [me.keep_level, ("  (off in Final Siege)" if siege and me.keep_level > 0 else "")]
	for i in range(_keep_rows.size()):
		var lvl: int = i + 1
		var btn: Button = _keep_rows[i]
		var effect: String = "Crown x%d, zone x%.1f radius %d" % [
			int(Balance.KEEP_CROWN_TILE_DEF[lvl]), Balance.KEEP_ZONE_DEF[lvl], Balance.KEEP_ZONE_RADIUS[lvl]]
		if lvl == 2:
			effect += ", Shield cd -%ds" % int(Balance.KEEP_2_CROWN_SHIELD_CD_REDUCTION_SEC)
		elif lvl == 3:
			effect += ", +%d%% troop cap" % int(Balance.KEEP_3_TROOP_CAP_BONUS * 100.0)
		var reason: String = BuildingsOps.keep_block_reason(_sim, me, lvl)
		btn.text = "Keep %d — %d troops\n%s" % [lvl, int(Balance.KEEP_COST[lvl]), (effect if reason == "" else "%s  ·  %s" % [reason, effect])]
		btn.disabled = reason != ""
	var move_reason: String = ""
	if me.crown_moved:
		move_reason = "Already moved this match"
	elif _sim.state.match_time < Balance.CROWN_MOVE_UNLOCK_SEC:
		move_reason = "Unlocks at %s" % GameState.format_time(Balance.CROWN_MOVE_UNLOCK_SEC)
	_move_row.text = "Move Crown — %d troops (20%%)\n%s" % [int(CrownsOps.move_cost(me)),
		("Then tap your land %d+ tiles from enemies" % Balance.CROWN_MOVE_MIN_DIST_FROM_ENEMY if move_reason == "" else move_reason)]
	_move_row.disabled = move_reason != ""


func _on_move_pressed() -> void:
	move_crown_requested.emit()
	close_panel()
