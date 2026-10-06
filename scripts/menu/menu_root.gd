class_name MenuRoot
extends Control

# The menus (scenes/menu.tscn): a generated map in the background and one
# screen at a time in front of it. Screens are built when first shown.

var _screens: Dictionary = {}       # name -> MenuScreen
var _holder: CenterContainer
var current: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.texture = ImageTexture.create_from_image(make_background(randi()))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.04, 0.07, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	_holder = CenterContainer.new()
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_holder)
	Audio.music("music_calm_loop")
	show_screen(Session.return_screen if Session.return_screen != "" else "main")
	Session.return_screen = ""


func show_screen(screen_name: String) -> void:
	if not _screens.has(screen_name):
		var s: MenuScreen = _make(screen_name)
		if s == null:
			return
		_screens[screen_name] = s
		if screen_name == "main":
			_holder.add_child(s)
		else:
			# Setup screens sit on a dark card so the text stays readable.
			var card := PanelContainer.new()
			var sb := UIStyle.panel_style(16)
			sb.content_margin_left = 40
			sb.content_margin_right = 40
			sb.content_margin_top = 24
			sb.content_margin_bottom = 28
			card.add_theme_stylebox_override("panel", sb)
			card.add_child(s)
			_holder.add_child(card)
	for k: String in _screens.keys():
		var node: Control = _screens[k]
		var shown: Control = node if k == "main" else node.get_parent() as Control
		shown.visible = k == screen_name
	current = screen_name
	(_screens[screen_name] as MenuScreen).refresh()
	Audio.play("sfx_ui_tap", -10.0)


func screen(screen_name: String) -> MenuScreen:
	return _screens.get(screen_name, null)


func _make(screen_name: String) -> MenuScreen:
	match screen_name:
		"main":
			return MainScreen.new(self)
		"skirmish":
			return SkirmishScreen.new(self)
		"teams":
			return TeamsScreen.new(self)
		"daily":
			return DailyScreen.new(self)
		"settings":
			return SettingsScreen.new(self)
		"customize":
			return CustomizeScreen.new(self)
		"stats":
			return StatsScreen.new(self)
		"achievements":
			return AchievementsScreen.new(self)
	return null


func _unhandled_input(event: InputEvent) -> void:
	# Android back button / Escape: back to the main screen.
	if event.is_action_pressed("ui_cancel") and current != "main":
		show_screen("main")
		get_viewport().set_input_as_handled()


# A terrain-only map (no players) to sit behind the menus.
static func make_background(bg_seed: int) -> Image:
	var st := GameState.new()
	var dims: Vector2i = MapGen.dims_for_size(Balance.MAP_SIZE_MEDIUM)
	st.configure(dims.x, dims.y, bg_seed)
	MapGen.generate(st, Balance.MAP_TYPE_RANDOM)
	var img := Image.create(st.width, st.height, false, Image.FORMAT_RGBA8)
	for i in range(st.width * st.height):
		var t: int = st.terrain[i]
		var c: Color = Balance.TERRAIN_COLORS[t] if t < Balance.TERRAIN_COLORS.size() else Color.BLACK
		@warning_ignore("integer_division")
		img.set_pixel(i % st.width, i / st.width, c)
	return img
