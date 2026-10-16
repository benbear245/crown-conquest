class_name HudStartMenu
extends ColorRect

# Home screen. A header with your name and level, a welcome banner for new
# players, three cards (Play vs bots, Daily Challenge, Play with friends) and
# a row of extras (Tutorial, How to play, Customize, Progress). Everything
# else opens on top as its own screen or pop-up, so the home stays simple.

signal quick_play
signal play_setup(setup: MatchSetup)
signal play_daily
signal play_tutorial
signal practice_online
signal host_lan
signal join_lan(address: String)
signal start_match
signal leave

const PLAY_COLOR: Color = Color(1.0, 0.78, 0.22)
const DAILY_COLOR: Color = Color(0.40, 0.65, 1.0)
const FRIENDS_COLOR: Color = Color(0.45, 0.90, 0.55)

var setup_panel: MenuSetupPanel
var customize_panel: MenuCustomizePanel
var progress_panel: MenuProgressPanel
var lobby_panel: MenuLobbyPanel
var help_panel: MenuHelpPanel
var settings_panel: MenuSettingsPanel

var _home: VBoxContainer
var _name_edit: LineEdit
var _bar: XpBar
var _welcome: PanelContainer
var _welcome_dismissed: bool = false
var _quick_info: Label
var _record: Label
var _daily_info: Label
var _daily_best: Label
var _challenges: VBoxContainer
var _join_row: HBoxContainer
var _ip_edit: LineEdit
var _tutorial: Button
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.03, 0.04, 0.07, 1.0)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	_home = UI.vbox(18)
	margin.add_child(_home)
	_home.add_child(_build_header())
	_welcome = _build_welcome()
	_home.add_child(_welcome)
	var cards := UI.hbox(24)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home.add_child(cards)
	cards.add_child(_build_play_card())
	cards.add_child(_build_daily_card())
	cards.add_child(_build_friends_card())
	_home.add_child(_build_extras())
	_status = UI.label("", 18, UI.COLOR_BAD)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_home.add_child(_status)
	var version := UI.label("Test build %s — thanks for testing!" % BugReport.version_label(), 14, UI.COLOR_DIM)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_home.add_child(version)
	_build_overlays()
	Profile.changed.connect(_refresh)
	show_main("")


func _build_header() -> HBoxContainer:
	var h := UI.hbox(20)
	var title := UI.label("♛ Crown Conquest", 44, UI.COLOR_WARN)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)
	var me := UI.vbox(4)
	h.add_child(me)
	var name_row := UI.hbox(8)
	me.add_child(name_row)
	var nl := UI.label("Your name", 16, UI.COLOR_DIM)
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(nl)
	_name_edit = _line_edit(Settings.player_name, "Type your name")
	_name_edit.max_length = 16
	_name_edit.custom_minimum_size = Vector2(300, 48)
	_name_edit.text_changed.connect(func(t: String) -> void: Settings.set_text("player_name", t))
	name_row.add_child(_name_edit)
	_bar = XpBar.new(26, 15)
	_bar.custom_minimum_size.x = 400
	me.add_child(_bar)
	var settings := UI.outline_button("Settings", UI.COLOR_DIM, 150, 80, 20)
	settings.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	settings.pressed.connect(func() -> void: settings_panel.open())
	h.add_child(settings)
	return h


func _build_welcome() -> PanelContainer:
	var card := UI.card(UI.COLOR_GOOD, 14)
	var row := UI.hbox(16)
	card.add_child(row)
	var text := UI.label("New here? The tutorial teaches the basics in about 5 minutes.", 22)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(text)
	var go := UI.primary_button("Start tutorial", 240, UI.BUTTON_H, 22)
	go.pressed.connect(func() -> void: play_tutorial.emit())
	row.add_child(go)
	var later := UI.outline_button("Not now", UI.COLOR_DIM, 160, UI.BUTTON_H, 18)
	later.pressed.connect(func() -> void:
		_welcome_dismissed = true
		_welcome.visible = false)
	row.add_child(later)
	return card


func _build_play_card() -> PanelContainer:
	var v := _card(PLAY_COLOR, "Play vs bots", "Grab land, take Crowns, be the last one standing.")
	var quick := UI.primary_button("▶  Quick play", 0, 120, 36)
	quick.pressed.connect(func() -> void: quick_play.emit())
	v.add_child(quick)
	_quick_info = UI.label("", 19, UI.COLOR_DIM)
	_quick_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quick_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_quick_info)
	_record = UI.label("", 19)
	_record.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_record)
	v.add_child(_filler())
	var change := UI.outline_button("Change map and bots", PLAY_COLOR, 0, UI.BUTTON_H + 8, 21)
	change.pressed.connect(func() -> void: setup_panel.open(Profile.last_setup()))
	v.add_child(change)
	return v.get_parent() as PanelContainer


func _build_daily_card() -> PanelContainer:
	var v := _card(DAILY_COLOR, "Daily Challenge", "Same map for everyone today. Beat your best score!")
	_daily_info = UI.label("", 19)
	v.add_child(_daily_info)
	_daily_best = UI.label("", 22, UI.COLOR_WARN)
	v.add_child(_daily_best)
	var play := UI.outline_button("Play today's map", DAILY_COLOR, 0, UI.BUTTON_H + 8, 22)
	play.pressed.connect(func() -> void: play_daily.emit())
	v.add_child(play)
	v.add_child(UI.label("Today's challenges  (+%d XP each)" % Balance.XP_PER_DAILY_CHALLENGE, 18, UI.COLOR_DIM))
	_challenges = UI.vbox(4)
	v.add_child(_challenges)
	return v.get_parent() as PanelContainer


func _build_friends_card() -> PanelContainer:
	var v := _card(FRIENDS_COLOR, "Play with friends", "Phones on the same Wi-Fi play in one match.")
	var host := UI.outline_button("Host a game", FRIENDS_COLOR, 0, UI.BUTTON_H + 8, 22)
	host.pressed.connect(func() -> void: host_lan.emit())
	v.add_child(host)
	var join := UI.outline_button("Join a game", FRIENDS_COLOR, 0, UI.BUTTON_H + 8, 22)
	join.pressed.connect(func() -> void:
		_join_row.visible = not _join_row.visible
		if _join_row.visible:
			_ip_edit.grab_focus())
	v.add_child(join)
	_join_row = UI.hbox(8)
	_join_row.visible = false
	v.add_child(_join_row)
	_ip_edit = _line_edit(Settings.last_address, "Host's address, e.g. 192.168.1.20")
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _join())
	_join_row.add_child(_ip_edit)
	var go := UI.primary_button("Join", 110, UI.BUTTON_H, 20)
	go.pressed.connect(_join)
	_join_row.add_child(go)
	var steps := UI.label("How it works\n1.  One phone taps Host a game.\n2.  Friends tap Join a game and type the address it shows.\n3.  The host taps Start. Bots fill any empty seats.", 18, UI.COLOR_DIM)
	steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(steps)
	v.add_child(_filler())
	var practice := UI.outline_button("Try online mode on this phone", UI.COLOR_DIM, 0, 48, 17)
	practice.pressed.connect(func() -> void: practice_online.emit())
	v.add_child(practice)
	return v.get_parent() as PanelContainer


func _build_extras() -> HBoxContainer:
	var row := UI.hbox(16)
	_tutorial = _extra(row, "Tutorial", func() -> void: play_tutorial.emit())
	_extra(row, "How to play", func() -> void: help_panel.visible = true)
	_extra(row, "Customize", func() -> void: customize_panel.open(player_name()))
	_extra(row, "Progress & trophies", func() -> void: progress_panel.open())
	return row


func _build_overlays() -> void:
	setup_panel = MenuSetupPanel.new()
	add_child(setup_panel)
	setup_panel.back.connect(func() -> void: setup_panel.visible = false)
	setup_panel.start.connect(func(s: MatchSetup) -> void:
		setup_panel.visible = false
		play_setup.emit(s))
	customize_panel = MenuCustomizePanel.new()
	add_child(customize_panel)
	customize_panel.back.connect(func() -> void: customize_panel.visible = false)
	progress_panel = MenuProgressPanel.new()
	add_child(progress_panel)
	progress_panel.back.connect(func() -> void: progress_panel.visible = false)
	help_panel = MenuHelpPanel.new()
	add_child(help_panel)
	help_panel.tutorial_pressed.connect(func() -> void: play_tutorial.emit())
	settings_panel = MenuSettingsPanel.new()
	add_child(settings_panel)
	lobby_panel = MenuLobbyPanel.new()
	add_child(lobby_panel)
	lobby_panel.start_match.connect(func() -> void: start_match.emit())
	lobby_panel.leave.connect(func() -> void: leave.emit())


# A card with a title and one-line explanation; returns its content box.
func _card(accent: Color, title: String, blurb: String) -> VBoxContainer:
	var c := UI.card(accent, 22)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_stretch_ratio = 1.0
	var v := UI.vbox(12)
	c.add_child(v)
	v.add_child(UI.label(title, 30, accent))
	var b := UI.label(blurb, 18, UI.COLOR_DIM)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(b)
	return v


func _extra(row: HBoxContainer, text: String, on_press: Callable) -> Button:
	var b := UI.outline_button(text, UI.COLOR_TEXT, 0, 72, 22)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	row.add_child(b)
	return b


func _filler() -> Control:
	var f := Control.new()
	f.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return f


func _line_edit(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, UI.BUTTON_H)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 20)
	return e


func _join() -> void:
	var address: String = _ip_edit.text.strip_edges()
	Settings.set_text("last_address", address)
	join_lan.emit(address)


func _refresh() -> void:
	if _bar == null:
		return
	_bar.set_total(int(Profile.data["xp"]))
	var s: MatchSetup = Profile.last_setup()
	_quick_info.text = "%s map · %s · %d %s bot%s" % [MatchSetup.label_for_size(s.size), MatchSetup.label_for_type(s.map_type),
		s.bots, MatchSetup.label_for_difficulty(s.difficulty).to_lower(), "" if s.bots == 1 else "s"]
	var st: Dictionary = Profile.stats()
	if int(st["matches"]) == 0:
		_record.text = "\nTip: troops grow fastest while the troop bar is green, so keep spending them on new land."
	else:
		_record.text = "\nYour record\n%d matches · %d wins · %d Crowns taken\nBest land: %.0f%%" % [
			int(st["matches"]), int(st["wins"]), int(st["crowns"]), float(st["best_peak_pct"])]
	var today: String = Progression.today()
	_daily_info.text = "Today: %s map · 7 bots" % MatchSetup.label_for_type(MatchSetup.daily(today).map_type)
	var best: int = Profile.daily_best(today)
	_daily_best.text = "Your best today: %d" % best if best >= 0 else "Not played yet today"
	MenuProgressPanel.fill_challenges(_challenges, 18, false)
	var new_player: bool = not bool(Profile.data["tutorial_done"])
	_tutorial.text = "Tutorial  ★ NEW" if new_player else "Tutorial"
	_tutorial.add_theme_color_override("font_color", UI.COLOR_WARN if new_player else UI.COLOR_TEXT)
	_welcome.visible = new_player and not _welcome_dismissed


func player_name() -> String:
	var n: String = _name_edit.text.strip_edges()
	return n if n != "" else "Player"


# Closes whatever is open on top of the home (Android back button).
# Returns false if only the home itself is showing.
func close_top() -> bool:
	if lobby_panel.visible:
		leave.emit()
		return true
	for p: Control in [settings_panel, help_panel, setup_panel, customize_panel, progress_panel]:
		if p.visible:
			p.visible = false
			return true
	if _join_row.visible:
		_join_row.visible = false
		return true
	return false


# status: an error to show (e.g. a failed connection), or "".
func show_main(status: String) -> void:
	visible = true
	lobby_panel.visible = false
	_status.text = status
	_refresh()


func show_waiting(text: String) -> void:
	visible = true
	lobby_panel.show_waiting(text)


func show_lobby(names: Array, is_host: bool, addresses: PackedStringArray) -> void:
	visible = true
	lobby_panel.show_lobby(names, is_host, addresses)
