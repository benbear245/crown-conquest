class_name HudBuildMenu
extends PanelContainer

# Long-press your own land: build here. Rows grey out with the reason when a
# building can't go here (cost, limit, too close to the enemy, unlock time).

signal build_requested(type: int, x: int, y: int)
signal upgrade_fort_requested(x: int, y: int)
signal wall_mode_requested
signal boat_mode_requested(port_x: int, port_y: int)

const WIDTH: int = 360

var _title: Label
var _list: VBoxContainer
var _tile: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UI.PANEL_BG
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(6)
	add_child(v)
	_title = UI.label("Build", 20)
	v.add_child(_title)
	_list = UI.vbox(6)
	v.add_child(_list)
	visible = false


func apply_side(left_handed: bool) -> void:
	UI.dock_side(self, not left_handed, WIDTH, UI.TOP_BAR_H + 50, UI.TOP_BAR_H + 60)


func open_at(sim: Simulation, local: Player, x: int, y: int) -> void:
	_tile = Vector2i(x, y)
	_title.text = "Build here   (troops %d)" % int(local.troops)
	UI.clear_children(_list)
	var state: GameState = sim.state
	var ti: int = state.idx(x, y)
	var here: Building = state.building_at_tile.get(ti, null)
	if here != null and here.owner_id == local.id:
		_add_existing(sim, local, here)
	else:
		for type: int in [Balance.BUILDING_FORT, Balance.BUILDING_BARRACKS, Balance.BUILDING_WATCHTOWER, Balance.BUILDING_PORT]:
			_add_build_row(sim, local, type, ti)
	var wall := UI.button("Wall mode — drag along your land (4 each)", WIDTH - 24, 48, 16)
	wall.pressed.connect(func() -> void:
		wall_mode_requested.emit()
		close())
	_list.add_child(wall)
	var close_btn := UI.button("Close", WIDTH - 24, 44)
	close_btn.pressed.connect(close)
	_list.add_child(close_btn)
	visible = true


func close() -> void:
	visible = false


func _add_existing(sim: Simulation, local: Player, b: Building) -> void:
	var now: float = sim.state.match_time
	var status: String = "" if b.is_active(now) else "  (sabotaged %ds)" % int(ceilf(b.disabled_until - now))
	_list.add_child(UI.label("%s%s" % [Building.type_label(b.type), status], 18, UI.COLOR_DIM))
	if b.type == Balance.BUILDING_FORT:
		var ok: bool = local.troops >= Balance.FORT2_COST
		var up := UI.button("Upgrade to Fort II  —  %d" % int(Balance.FORT2_COST), WIDTH - 24, 48, 16)
		up.disabled = not ok
		up.pressed.connect(func() -> void:
			upgrade_fort_requested.emit(b.x, b.y)
			close())
		_list.add_child(up)
	elif b.type == Balance.BUILDING_PORT:
		var boat := UI.button("Launch boat — then tap a coast", WIDTH - 24, 48, 16)
		boat.pressed.connect(func() -> void:
			boat_mode_requested.emit(b.x, b.y)
			close())
		_list.add_child(boat)


func _add_build_row(sim: Simulation, local: Player, type: int, ti: int) -> void:
	var state: GameState = sim.state
	if type == Balance.BUILDING_PORT and not BuildingsOps.tile_touches_water(state, ti):
		return
	var cost: float = BuildingsOps.next_cost(local, type)
	var desc: String = _describe(type)
	var reason: String = ""
	if cost < 0.0:
		reason = "limit reached"
	elif state.match_time < BuildingsOps.unlock_sec(type):
		reason = "unlocks %s" % GameState.format_time(BuildingsOps.unlock_sec(type))
	elif not BuildingsOps.tile_is_buildable(sim, local.id, ti):
		reason = "too close to enemy / occupied"
	elif local.troops < cost:
		reason = "need %d" % int(cost)
	var label: String = "%s  —  %d   %s" % [Building.type_label(type), int(maxf(cost, 0.0)), desc]
	if reason != "":
		label = "%s  —  %s" % [Building.type_label(type), reason]
	var b := UI.button(label, WIDTH - 24, 48, 16)
	b.disabled = reason != ""
	b.pressed.connect(func() -> void:
		build_requested.emit(type, _tile.x, _tile.y)
		close())
	_list.add_child(b)


func _describe(type: int) -> String:
	match type:
		Balance.BUILDING_FORT:
			return "(x%.1f defense nearby)" % Balance.FORT_DEFENSE
		Balance.BUILDING_BARRACKS:
			return "(+%d%% troop cap)" % int(Balance.BARRACKS_TROOP_CAP_BONUS * 100.0)
		Balance.BUILDING_WATCHTOWER:
			return "(see nearby rivals)"
		Balance.BUILDING_PORT:
			return "(boats)"
		_:
			return ""
