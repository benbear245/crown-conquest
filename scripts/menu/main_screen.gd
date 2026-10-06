class_name MainScreen
extends MenuScreen

# Title and the six big buttons.

const ENTRIES: Array = [
	["Play (Skirmish)", "skirmish"], ["Teams", "teams"], ["Daily Challenge", "daily"],
	["Customize", "customize"], ["Stats", "stats"], ["Settings", "settings"],
]


func _init(menu_root: MenuRoot) -> void:
	super(menu_root, "")
	var crown := IconView.new(IconView.Kind.CROWN, 96)
	crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(crown)
	var title := UIStyle.label("Crown Conquest", 72, Color(1.0, 0.86, 0.35))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 10)
	add_child(title)
	var tag := UIStyle.label("Grab land. Guard your Crown. Take theirs.", 22, UIStyle.COLOR_DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(tag)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	add_child(spacer)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(grid)
	for e: Array in ENTRIES:
		var b := UIStyle.big_button(e[0], 380, 26)
		b.name = str(e[1]).capitalize()
		var target: String = e[1]
		b.pressed.connect(func() -> void: root.show_screen(target))
		grid.add_child(b)
