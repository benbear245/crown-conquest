class_name TeamsScreen
extends MenuScreen

# Teams setup: 4 teams of 2 on a Medium map. You get a bot ally.

var type_row: OptionRow
var diff_row: OptionRow


func _init(menu_root: MenuRoot) -> void:
	super(menu_root, "Teams")
	add_child(MenuScreen.text_block("4 teams of 2 on a Medium map: you and a bot ally against 3 bot pairs. " +
		"Allies can't attack each other and can send each other 20% of their troops. " +
		"The last team with a Crown wins — together.", 1000, 22, UIStyle.COLOR_DIM))
	var setup: Dictionary = Settings.last_setup.get("teams", {})
	type_row = OptionRow.new("Map type", MatchConfig.TYPE_NAMES, int(setup.get("type", Balance.MAP_TYPE_CONTINENT)))
	add_child(type_row)
	diff_row = OptionRow.new("Difficulty", MatchConfig.DIFFICULTY_NAMES, int(setup.get("difficulty", MatchConfig.DIFFICULTY_MIXED)))
	add_child(diff_row)
	add_child(back_and_action_row("Start", start))


func make_config() -> MatchConfig:
	return MatchConfig.teams(type_row.selected, diff_row.selected)


func start() -> void:
	Settings.last_setup["teams"] = {"type": type_row.selected, "difficulty": diff_row.selected}
	Settings.save_settings()
	Session.play(make_config())
