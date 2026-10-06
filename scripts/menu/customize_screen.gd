class_name CustomizeScreen
extends MenuScreen

# Pick your territory colour, pattern, Crown icon, title and victory effect.
# Locked choices show the level that unlocks them. Saved straight away.

const TABS: Array[String] = ["Colour", "Pattern", "Crown", "Title", "Victory effect"]

var preview: CustomizePreview
var tab_row: OptionRow
var _grid: GridContainer
var _who: Label
var _note: Label


func _init(menu_root: MenuRoot) -> void:
	super(menu_root, "Customize")
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 30)
	add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	body.add_child(left)
	preview = CustomizePreview.new()
	left.add_child(preview)
	_who = UIStyle.label("", 24, Color(1.0, 0.9, 0.5))
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_who)
	_note = MenuScreen.text_block("Cosmetic only — nothing here makes you stronger.", 480, UIStyle.FONT_SMALL, UIStyle.COLOR_DIM)
	left.add_child(_note)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 14)
	body.add_child(right)
	tab_row = OptionRow.new("", TABS, 0, 150)
	tab_row.changed.connect(func(_i: int) -> void: _fill())
	right.add_child(tab_row)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	right.add_child(_grid)
	add_child(back_and_action_row("", Callable()))


func refresh() -> void:
	_fill()


func _fill() -> void:
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var lvl: int = SaveData.level()
	match tab_row.selected:
		0:
			_grid.columns = 6
			for i in range(Progression.COLORS.size()):
				_add_art(CosmeticArt.Kind.COLOR, i, Progression.COLOR_NAMES[i], Progression.color_level(i), "color")
		1:
			_grid.columns = 4
			for i in range(Progression.PATTERN_NAMES.size()):
				_add_art(CosmeticArt.Kind.PATTERN, i, Progression.PATTERN_NAMES[i], Progression.pattern_level(i), "pattern")
		2:
			_grid.columns = 4
			for i in range(Progression.CROWN_NAMES.size()):
				_add_art(CosmeticArt.Kind.CROWN, i, Progression.CROWN_NAMES[i], Progression.crown_level(i), "crown")
		3:
			_grid.columns = 3
			for t: Array in Progression.LEVEL_TITLES:
				_add_title(str(t[1]), lvl >= int(t[0]), "Level %d" % int(t[0]))
			for a: Dictionary in Progression.ACHIEVEMENTS:
				_add_title(str(a.title), SaveData.has_achievement(a.id), a.name)
		4:
			_grid.columns = 4
			for i in range(Progression.EFFECT_NAMES.size()):
				_add_art(CosmeticArt.Kind.EFFECT, i, Progression.EFFECT_NAMES[i], Progression.effect_level(i), "effect")
	_update_preview()


func _add_art(kind: int, i: int, label: String, unlock_level: int, key: String) -> void:
	var unlocked: bool = SaveData.level() >= unlock_level
	var b := UIStyle.choice_button("", 150)
	b.custom_minimum_size = Vector2(150, 110)
	b.disabled = not unlocked
	b.set_pressed_no_signal(int(SaveData.cosmetic(key)) == i)
	b.tooltip_text = label
	var art := CosmeticArt.new(kind, i)
	art.locked = not unlocked
	b.add_child(art)
	var name_label := UIStyle.label(label if unlocked else "Level %d" % unlock_level, UIStyle.FONT_SMALL,
		UIStyle.COLOR_TEXT if unlocked else UIStyle.COLOR_DIM)
	name_label.name = "Name"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.anchor_left = 0.0
	name_label.anchor_right = 1.0
	name_label.anchor_top = 1.0
	name_label.anchor_bottom = 1.0
	name_label.offset_top = -28.0
	name_label.offset_bottom = -4.0
	b.add_child(name_label)
	b.pressed.connect(func() -> void: SaveData.set_cosmetic(key, i); _fill())
	_grid.add_child(b)


func _add_title(title: String, unlocked: bool, how: String) -> void:
	var b := UIStyle.choice_button(title if unlocked else "%s  (%s)" % [title, how], 300)
	b.disabled = not unlocked
	b.set_pressed_no_signal(str(SaveData.cosmetic("title")) == title)
	b.pressed.connect(func() -> void: SaveData.set_cosmetic("title", title); _fill())
	_grid.add_child(b)


func _update_preview() -> void:
	var c: Variant = SaveData.custom_color()
	var col: Color = c if c != null else Progression.COLORS[0]
	var pat: int = int(SaveData.cosmetic("pattern"))
	var cr: int = int(SaveData.cosmetic("crown"))
	preview.set_look(col, pat if SaveData.pattern_unlocked(pat) else 0, cr if SaveData.crown_unlocked(cr) else 0)
	var info: Dictionary = Progression.level_info(SaveData.xp())
	_who.text = "%s · Level %d" % [str(SaveData.cosmetic("title")), int(info.level)]
