class_name BuildMenu
extends PanelContainer

# Long-press your own land: every building with its cost, effect and how many
# you have left. Options you can't use right now stay visible but greyed out,
# with the reason on the second line.

signal build_requested(type: int, x: int, y: int)
signal wall_mode_requested
signal boat_requested(port_x: int, port_y: int)
signal closed

const ROW_FORT: int = 0
const ROW_BARRACKS: int = 1
const ROW_PORT: int = 2
const ROW_WALL: int = 3
const ROW_BOAT: int = 4
const REFRESH_SEC: float = 0.25

var _sim: Simulation
var _tile: Vector2i = Vector2i(-1, -1)
var _title: Label
var _rows: Array[Button] = []
var _refresh_left: float = 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UIStyle.panel_style())
	visible = false
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	add_child(vbox)
	_title = UIStyle.label("Build", UIStyle.FONT_LARGE)
	vbox.add_child(_title)
	for i in range(5):
		var btn := UIStyle.button("", 380)
		var row: int = i
		btn.pressed.connect(func() -> void: _on_row_pressed(row))
		vbox.add_child(btn)
		_rows.append(btn)
	var close := UIStyle.button("Close", 380)
	close.alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.pressed.connect(close_menu)
	vbox.add_child(close)


func setup(sim: Simulation) -> void:
	_sim = sim


func open_at(tile: Vector2i) -> void:
	_tile = tile
	visible = true
	_refresh()


func close_menu() -> void:
	if visible:
		visible = false
		closed.emit()
	_tile = Vector2i(-1, -1)


# The button for a row (ROW_FORT, ...), e.g. for the tutorial's arrow.
func row_button(row: int) -> Button:
	return _rows[row] if row >= 0 and row < _rows.size() else null


func selected_tile() -> Vector2i:
	return _tile if visible else Vector2i(-1, -1)


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_left -= delta
	if _refresh_left <= 0.0:
		_refresh()


func _refresh() -> void:
	_refresh_left = REFRESH_SEC
	if _sim == null or _tile.x < 0:
		return
	var state: GameState = _sim.state
	var me: Player = state.get_player(_sim.local_player_id)
	if me == null or not me.is_alive or state.phase != Balance.PHASE_MATCH:
		close_menu()
		return
	var ti: int = state.idx(_tile.x, _tile.y)
	if state.owners[ti] != me.id:
		close_menu()
		return
	_title.text = "Build    troops %d" % int(me.troops)
	var here: Building = state.building_at_tile.get(ti, null)
	# Fort / Fort II.
	if here != null and here.type == Balance.BUILDING_FORT:
		_set_row(ROW_FORT, "Upgrade to Fort II — %d" % int(Balance.FORT2_COST),
			"Radius %d, x%.1f defense" % [Balance.FORT2_RADIUS, Balance.FORT2_DEFENSE],
			BuildingsOps.build_block_reason(_sim, me, Balance.BUILDING_FORT2, ti))
	elif here != null and here.type == Balance.BUILDING_FORT2:
		_set_row(ROW_FORT, "Fort II", "Fully upgraded", "Fully upgraded")
	else:
		_set_row(ROW_FORT, "Fort — %d   (%d left)" % [int(BuildingsOps.fort_cost_for(me)), Balance.FORT_LIMIT - me.fort_count],
			"Your tiles within %d get x%.1f defense" % [Balance.FORT_RADIUS, Balance.FORT_DEFENSE],
			BuildingsOps.build_block_reason(_sim, me, Balance.BUILDING_FORT, ti))
	_set_row(ROW_BARRACKS, "Barracks — %d   (%d left)" % [int(BuildingsOps.barracks_cost_for(me)), Balance.BARRACKS_LIMIT - me.barracks_count],
		"Troop cap +%d%%" % int(Balance.BARRACKS_TROOP_CAP_BONUS * 100.0),
		BuildingsOps.build_block_reason(_sim, me, Balance.BUILDING_BARRACKS, ti))
	_set_row(ROW_PORT, "Port — %d   (%d left)" % [int(Balance.PORT_COST), Balance.PORT_LIMIT - me.port_count],
		"Launch boats up to %d tiles across water" % Balance.BOAT_RANGE_TILES,
		BuildingsOps.build_block_reason(_sim, me, Balance.BUILDING_PORT, ti))
	var wall_reason: String = ""
	if me.wall_count >= Balance.WALL_LIMIT:
		wall_reason = "Limit reached (%d/%d)" % [me.wall_count, Balance.WALL_LIMIT]
	elif me.troops < Balance.WALL_COST_PER_TILE:
		wall_reason = "Need %d troops" % int(Balance.WALL_COST_PER_TILE)
	_set_row(ROW_WALL, "Draw walls — %d per tile   (%d left)" % [int(Balance.WALL_COST_PER_TILE), Balance.WALL_LIMIT - me.wall_count],
		"Drag on your land: each tile x%.1f defense" % Balance.WALL_DEFENSE, wall_reason)
	var boat_btn: Button = _rows[ROW_BOAT]
	boat_btn.visible = here != null and here.type == Balance.BUILDING_PORT
	if boat_btn.visible:
		_set_row(ROW_BOAT, "Launch boat", "Then tap a coast across the water", "")


func _set_row(row: int, title: String, effect: String, reason: String) -> void:
	var btn: Button = _rows[row]
	btn.visible = true
	btn.disabled = reason != ""
	btn.text = "%s\n%s" % [title, (effect if reason == "" else reason)]
	btn.tooltip_text = effect


func _on_row_pressed(row: int) -> void:
	if _tile.x < 0:
		return
	var t: Vector2i = _tile
	match row:
		ROW_FORT:
			var here: Building = _sim.state.building_at_tile.get(_sim.state.idx(t.x, t.y), null)
			var type: int = Balance.BUILDING_FORT2 if here != null and here.type == Balance.BUILDING_FORT else Balance.BUILDING_FORT
			build_requested.emit(type, t.x, t.y)
		ROW_BARRACKS:
			build_requested.emit(Balance.BUILDING_BARRACKS, t.x, t.y)
		ROW_PORT:
			build_requested.emit(Balance.BUILDING_PORT, t.x, t.y)
		ROW_WALL:
			wall_mode_requested.emit()
		ROW_BOAT:
			boat_requested.emit(t.x, t.y)
	close_menu()
