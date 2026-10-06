class_name PlaceholderScreen
extends MenuScreen

# Stand-in for a screen that isn't built yet.


func _init(menu_root: MenuRoot, title: String, text: String) -> void:
	super(menu_root, title)
	add_child(MenuScreen.text_block(text, 900, 22, UIStyle.COLOR_DIM))
	add_child(back_and_action_row("", Callable()))
