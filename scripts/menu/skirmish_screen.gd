class_name SkirmishScreen
extends MenuScreen

# Skirmish setup: map size, map type, number of bots, difficulty, optional seed.

var size_row: OptionRow
var type_row: OptionRow
var diff_row: OptionRow
var seed_edit: LineEdit
var bots: int = 7
var _bots_label: Label


func _init(menu_root: MenuRoot) -> void:
	super(menu_root, "Skirmish")
	var setup: Dictionary = Settings.last_setup.get("skirmish", {})
	size_row = OptionRow.new("Map size", ["Small", "Medium", "Large"], int(setup.get("size", Balance.MAP_SIZE_MEDIUM)))
	size_row.changed.connect(func(_i: int) -> void: _set_bots(MatchConfig.max_bots_for(size_row.selected)))
	add_child(size_row)
	type_row = OptionRow.new("Map type", MatchConfig.TYPE_NAMES, int(setup.get("type", Balance.MAP_TYPE_CONTINENT)))
	add_child(type_row)
	var bots_row := HBoxContainer.new()
	bots_row.add_theme_constant_override("separation", 10)
	var lbl := UIStyle.label("Bots", 22)
	lbl.custom_minimum_size = Vector2(230, 0)
	bots_row.add_child(lbl)
	var minus := UIStyle.choice_button("−", 90)
	minus.toggle_mode = false
	minus.pressed.connect(func() -> void: _set_bots(bots - 1))
	bots_row.add_child(minus)
	_bots_label = UIStyle.label("", 26)
	_bots_label.custom_minimum_size = Vector2(160, 56)
	_bots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bots_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bots_row.add_child(_bots_label)
	var plus := UIStyle.choice_button("+", 90)
	plus.toggle_mode = false
	plus.pressed.connect(func() -> void: _set_bots(bots + 1))
	bots_row.add_child(plus)
	add_child(bots_row)
	diff_row = OptionRow.new("Difficulty", MatchConfig.DIFFICULTY_NAMES, int(setup.get("difficulty", MatchConfig.DIFFICULTY_MIXED)))
	add_child(diff_row)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	var sl := UIStyle.label("Seed (optional)", 22)
	sl.custom_minimum_size = Vector2(230, 0)
	seed_row.add_child(sl)
	seed_edit = LineEdit.new()
	seed_edit.placeholder_text = "Random map — or type any word or number to replay a map"
	seed_edit.custom_minimum_size = Vector2(700, 56)
	seed_edit.add_theme_font_size_override("font_size", 20)
	seed_edit.max_length = 40
	seed_row.add_child(seed_edit)
	add_child(seed_row)
	add_child(back_and_action_row("Start", start))
	_set_bots(int(setup.get("bots", MatchConfig.max_bots_for(size_row.selected))))


func _set_bots(n: int) -> void:
	bots = clampi(n, 1, MatchConfig.max_bots_for(size_row.selected))
	_bots_label.text = "%d" % bots


func make_config() -> MatchConfig:
	return MatchConfig.skirmish(size_row.selected, type_row.selected, bots, diff_row.selected, seed_edit.text)


func start() -> void:
	Settings.last_setup["skirmish"] = {"size": size_row.selected, "type": type_row.selected, "bots": bots, "difficulty": diff_row.selected}
	Settings.save_settings()
	Session.play(make_config())
