class_name MainScreen
extends MenuScreen

# Title, your level and title, and the six big buttons.

const ENTRIES: Array = [
	["Play (Skirmish)", "skirmish"], ["Teams", "teams"], ["Daily Challenge", "daily"],
	["Customize", "customize"], ["Stats", "stats"], ["Settings", "settings"],
]


var _profile: Label
var _bar: Control
var _frac: float = 0.0


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
	_profile = UIStyle.label("", 22, Color(1.0, 0.9, 0.55))
	_profile.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_profile)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(420, 12)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
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


func refresh() -> void:
	var info: Dictionary = Progression.level_info(SaveData.xp())
	_frac = float(info.into) / float(info.need)
	_profile.text = "%s · Level %d   %s / %s XP" % [str(SaveData.cosmetic("title")), int(info.level),
		GameState.format_int(int(info.into)), GameState.format_int(int(info.need))]
	_bar.queue_redraw()


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, _bar.size)
	_bar.draw_rect(r, Color(0, 0, 0, 0.6))
	_bar.draw_rect(Rect2(r.position, Vector2(r.size.x * _frac, r.size.y)), Color(1.0, 0.8, 0.25))
