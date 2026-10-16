class_name MenuCustomizePanel
extends ColorRect

# Pick your look: territory colour, pattern, Crown icon, title and victory
# effect. Locked items say what unlocks them. Looks are cosmetic only.

signal back

const W: int = 1300

var _cat: String = Cosmetics.CAT_COLOR
var _tabs: Dictionary = {}         # category -> Button
var _grid: GridContainer
var _preview: LookPreview
var _hint: Label
var _fx: VictoryFx
var _player_name: String = "Player"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.03, 0.04, 0.07, 1.0)
	var panel := UI.panel(22)
	UI.centre(panel, W, 100)
	add_child(panel)
	var v := UI.vbox(14)
	panel.add_child(v)
	var head := UI.hbox(16)
	v.add_child(head)
	head.add_child(UI.label("Customize", 34, UI.COLOR_WARN))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var back_btn := UI.outline_button("Back", UI.COLOR_DIM, 180)
	back_btn.pressed.connect(func() -> void: back.emit())
	head.add_child(back_btn)
	var tabs := UI.hbox(8)
	v.add_child(tabs)
	for cat in Cosmetics.CATEGORIES:
		var t := UI.toggle(Cosmetics.category_label(cat), 160, UI.BUTTON_H, 19)
		t.pressed.connect(func() -> void: _show_cat(cat))
		tabs.add_child(t)
		_tabs[cat] = t
	var body := UI.hbox(24)
	v.add_child(body)
	var left := UI.vbox(10)
	body.add_child(left)
	_preview = LookPreview.new()
	left.add_child(_preview)
	_hint = UI.label("Looks are just for show — they never change the rules.", 16, UI.COLOR_DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(_preview.custom_minimum_size.x, 0)
	left.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_grid)
	_fx = VictoryFx.new()
	add_child(_fx)
	visible = false


func open(player_name: String) -> void:
	_player_name = player_name
	visible = true
	_show_cat(_cat)


func _show_cat(cat: String) -> void:
	_cat = cat
	for c: String in _tabs.keys():
		(_tabs[c] as Button).set_pressed_no_signal(c == cat)
	UI.clear_children(_grid)
	var chosen: int = int(Profile.look().get(cat, 0))
	var names: Array[String] = Cosmetics.names_for(cat)
	for i in range(names.size()):
		var unlocked: bool = Profile.is_unlocked(cat, i)
		var text: String = Cosmetics.label(cat, i)
		if not unlocked:
			text = "%s\n(%s)" % [text, _unlock_text(cat, i)]
		var b := UI.toggle(text, 210, 76, 17)
		b.button_pressed = i == chosen
		b.disabled = not unlocked
		if cat == Cosmetics.CAT_COLOR:
			b.add_theme_color_override("font_color", Cosmetics.COLORS[i].lightened(0.25))
			b.add_theme_color_override("font_pressed_color", Cosmetics.COLORS[i].lightened(0.25))
			b.add_theme_color_override("font_hover_pressed_color", Cosmetics.COLORS[i].lightened(0.25))
		b.pressed.connect(func() -> void:
			Profile.set_look(cat, i)
			if cat == Cosmetics.CAT_VICTORY:
				_fx.play(i, Cosmetics.COLORS[int(Profile.look()[Cosmetics.CAT_COLOR])])
			_show_cat(cat))
		_grid.add_child(b)
	_preview.show_look(Profile.look(), _player_name)


static func _unlock_text(cat: String, idx: int) -> String:
	var lvl: int = Cosmetics.unlock_level(cat, idx)
	if lvl > 0:
		return "Level %d" % lvl
	for id: String in Progression.ACHIEVEMENTS.keys():
		if int(Progression.ACHIEVEMENTS[id][2]) == idx:
			return "Achievement: %s" % Progression.ACHIEVEMENTS[id][0]
	return "Locked"


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible and _fx != null:
		_fx.stop()
