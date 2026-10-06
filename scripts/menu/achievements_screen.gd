class_name AchievementsScreen
extends MenuScreen

# Every achievement: gold star and the date once earned, grey until then.

var _grid: GridContainer


func _init(menu_root: MenuRoot) -> void:
	super(menu_root, "Achievements")
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 30)
	_grid.add_theme_constant_override("v_separation", 10)
	add_child(_grid)
	add_child(back_and_action_row("", Callable(), "stats"))


func refresh() -> void:
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for a: Dictionary in Progression.ACHIEVEMENTS:
		var got: bool = SaveData.has_achievement(a.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.custom_minimum_size = Vector2(700, 0)
		var star := IconView.new(IconView.Kind.STAR, 40)
		star.modulate = Color.WHITE if got else Color(0.35, 0.35, 0.38)
		row.add_child(star)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		row.add_child(col)
		col.add_child(UIStyle.label(str(a.name), 22, Color(1.0, 0.86, 0.35) if got else UIStyle.COLOR_DIM))
		var when: String = ""
		if got:
			when = "  ·  earned " + Time.get_date_string_from_unix_time(int(SaveData.data.achievements[a.id]))
		col.add_child(UIStyle.label("%s  ·  title \"%s\"%s" % [a.desc, a.title, when], UIStyle.FONT_SMALL, UIStyle.COLOR_TEXT if got else UIStyle.COLOR_DIM))
		_grid.add_child(row)
