class_name HudKeepPanel
extends PanelContainer

# The Crown menu: Keep upgrades, moving the Crown, and Disinformation.

signal buy_keep_requested(level: int)
signal move_crown_requested
signal disinformation_requested(look_strong: bool)

const WIDTH: int = 420

var _keep_buttons: Array[Button] = []
var _move_btn: Button
var _weak_btn: Button
var _strong_btn: Button
var _disinfo_info: Label


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	add_theme_stylebox_override("panel", sb)
	UI.centre(self, WIDTH, 100)
	var v := UI.vbox(8)
	add_child(v)
	v.add_child(UI.label("Your Crown", 24))
	for lvl in range(1, Balance.KEEP_COST.size()):
		var b := UI.button("", WIDTH - 28, 50, 17)
		b.pressed.connect(func() -> void: buy_keep_requested.emit(lvl))
		v.add_child(b)
		_keep_buttons.append(b)
	_move_btn = UI.button("", WIDTH - 28, 50, 17)
	_move_btn.pressed.connect(func() -> void:
		move_crown_requested.emit()
		visible = false)
	v.add_child(_move_btn)
	v.add_child(UI.label("Disinformation — rivals see fake troop numbers", 15, UI.COLOR_DIM))
	var row := UI.hbox(8)
	v.add_child(row)
	_weak_btn = UI.button("Look weak", int((WIDTH - 36) * 0.5), 50, 17)
	_weak_btn.pressed.connect(func() -> void: disinformation_requested.emit(false))
	row.add_child(_weak_btn)
	_strong_btn = UI.button("Look strong", int((WIDTH - 36) * 0.5), 50, 17)
	_strong_btn.pressed.connect(func() -> void: disinformation_requested.emit(true))
	row.add_child(_strong_btn)
	_disinfo_info = UI.label("", 15, UI.COLOR_DIM)
	v.add_child(_disinfo_info)
	var close := UI.button("Close", WIDTH - 28, 44)
	close.pressed.connect(func() -> void: visible = false)
	v.add_child(close)
	visible = false


func refresh(sim: Simulation, local: Player) -> void:
	if not visible or local == null:
		return
	if not local.is_alive:
		visible = false
		return
	var now: float = sim.state.match_time
	for i in range(_keep_buttons.size()):
		var lvl: int = i + 1
		var b: Button = _keep_buttons[i]
		var cost: float = Balance.KEEP_COST[lvl]
		var unlock: float = Balance.KEEP_UNLOCK_SEC[lvl]
		if local.keep_level >= lvl:
			b.text = "Keep %d — owned" % lvl
			b.disabled = true
		elif now < unlock:
			b.text = "Keep %d — unlocks %s" % [lvl, GameState.format_time(unlock)]
			b.disabled = true
		elif local.keep_level + 1 != lvl:
			b.text = "Keep %d — buy Keep %d first" % [lvl, lvl - 1]
			b.disabled = true
		else:
			b.text = "Keep %d — %d troops  (Crown x%d)" % [lvl, int(cost), int(Balance.KEEP_CROWN_TILE_DEF[lvl])]
			b.disabled = local.troops < cost
	if local.crown_moved:
		_move_btn.text = "Move Crown — used" if local.crown_move_to.x < 0 else "Moving Crown…"
		_move_btn.disabled = true
	elif now < Balance.CROWN_MOVE_UNLOCK_SEC:
		_move_btn.text = "Move Crown — unlocks %s" % GameState.format_time(Balance.CROWN_MOVE_UNLOCK_SEC)
		_move_btn.disabled = true
	else:
		_move_btn.text = "Move Crown — %d troops, then tap a spot" % int(floorf(local.troops * Balance.CROWN_MOVE_COST_FRACTION))
		_move_btn.disabled = false
	var blocker: String = IntelOps.disinfo_blocker(sim, local)
	_weak_btn.disabled = blocker != ""
	_strong_btn.disabled = blocker != ""
	_disinfo_info.text = blocker if blocker != "" else "%d troops, lasts %ds" % [int(IntelOps.disinfo_cost(local)), int(Balance.DISINFO_DURATION_SEC)]
