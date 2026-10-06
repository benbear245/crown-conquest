extends Node

# Moves between the menus and a match (autoload "Session"). Holds the
# MatchConfig for the next match and the screen to return to.

const MENU_SCENE: String = "res://scenes/menu.tscn"
const GAME_SCENE: String = "res://scenes/main.tscn"

# The match the game scene should start. Null = a default Skirmish.
var config: MatchConfig = null
# Menu screen to show when coming back from a match ("" = main screen).
var return_screen: String = ""


func play(cfg: MatchConfig) -> void:
	config = cfg
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func to_menu(screen: String = "") -> void:
	return_screen = screen
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)


# The config for the game scene: the one the menus chose, or a default
# Skirmish (when main.tscn is run directly).
func current_config() -> MatchConfig:
	if config == null:
		config = MatchConfig.skirmish(Balance.MAP_SIZE_MEDIUM, Balance.MAP_TYPE_CONTINENT, 7, MatchConfig.DIFFICULTY_MIXED)
	return config
