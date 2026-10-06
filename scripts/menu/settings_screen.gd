class_name SettingsScreen
extends MenuScreen

# Settings from the main menu (the same toggles as the pause menu).


func _init(menu_root: MenuRoot) -> void:
	super(menu_root, "Settings")
	var list := SettingsList.new(480)
	list.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(list)
	var tips := UIStyle.button("Show tips again", 480)
	tips.alignment = HORIZONTAL_ALIGNMENT_CENTER
	tips.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tips.pressed.connect(func() -> void: Settings.reset_hints(); tips.text = "Tips will show again")
	add_child(tips)
	var tutorial := UIStyle.button("Replay tutorial", 480)
	tutorial.name = "ReplayTutorial"
	tutorial.alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tutorial.pressed.connect(func() -> void: Session.play(MatchConfig.tutorial()))
	add_child(tutorial)
	add_child(back_and_action_row("", Callable()))
