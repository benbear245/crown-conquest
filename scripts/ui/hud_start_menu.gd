class_name HudStartMenu
extends ColorRect

# First screen. Left: your level, Quick play (your last setup), match setup,
# the Daily Challenge, the tutorial, looks and progress. Right: today's
# challenges and online play. Also the lobby while waiting for the host.

signal quick_play
signal play_setup(setup: MatchSetup)
signal play_daily
signal play_tutorial
signal practice_online
signal host_lan
signal join_lan(address: String)
signal start_match
signal leave

const W: int = 1320
const COL_W: int = 620
const HOW_TO_PLAY: String = """• Place your Crown, then tap free land next to your border to grow.
• The slider sets how many troops each tap sends. Troops grow fastest while the bar is green.
• After 1:00, tap enemy land to attack. Take an enemy Crown's centre to knock them out.
• Long-press your land to build; long-press a rival to spy, scout or offer a truce.
• Hold the Shrines (◆) for bonuses. Tap ♛ Crown for upgrades.
• Win: last Crown standing, own 60% of the land, or lead at 15:00."""

var setup_panel: MenuSetupPanel
var customize_panel: MenuCustomizePanel
var progress_panel: MenuProgressPanel

var _main: HBoxContainer
var _lobby: VBoxContainer
var _status: Label
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _bar: XpBar
var _quick: Button
var _daily: Button
var _tutorial: Button
var _challenges: VBoxContainer
var _chal_title: Label
var _help: Label
var _lobby_title: Label
var _lobby_info: Label
var _lobby_names: Label
var _start_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.03, 0.04, 0.07, 1.0)
	var panel := UI.panel(22)
	UI.centre(panel, W, 100)
	add_child(panel)
	var v := UI.vbox(12)
	panel.add_child(v)
	var title := UI.label("Crown Conquest", 42, UI.COLOR_WARN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_main = UI.hbox(36)
	v.add_child(_main)
	_main.add_child(_build_left())
	_main.add_child(_build_right())
	_lobby = UI.vbox(10)
	v.add_child(_lobby)
	_build_lobby()
	_status = UI.label("", 17, UI.COLOR_BAD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)
	var version := UI.label("Test build %s — thanks for testing!" % BugReport.version_label(), 14, UI.COLOR_DIM)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(version)
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
	Profile.changed.connect(_refresh)
	show_main("")


func _build_left() -> VBoxContainer:
	var col := UI.vbox(10)
	col.custom_minimum_size = Vector2(COL_W, 0)
	var name_row := UI.hbox(8)
	col.add_child(name_row)
	var nl := UI.label("Your name", 18, UI.COLOR_DIM)
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(nl)
	_name_edit = _line_edit(Settings.player_name, "Player")
	_name_edit.max_length = 16
	_name_edit.text_changed.connect(func(t: String) -> void: Settings.set_text("player_name", t))
	name_row.add_child(_name_edit)
	_bar = XpBar.new(30, 17)
	col.add_child(_bar)
	_quick = UI.button("", COL_W, 92, 26)
	_quick.add_theme_color_override("font_color", UI.COLOR_WARN)
	_quick.pressed.connect(func() -> void: quick_play.emit())
	col.add_child(_quick)
	col.add_child(_menu_button("Play vs bots — choose map and bots", func() -> void: setup_panel.open(Profile.last_setup())))
	_daily = _menu_button("", func() -> void: play_daily.emit())
	col.add_child(_daily)
	var row := UI.hbox(10)
	col.add_child(row)
	_tutorial = UI.button("Tutorial", 196, UI.BUTTON_H, 19)
	_tutorial.pressed.connect(func() -> void: play_tutorial.emit())
	row.add_child(_tutorial)
	var cust := UI.button("Customize", 196, UI.BUTTON_H, 19)
	cust.pressed.connect(func() -> void: customize_panel.open(player_name()))
	row.add_child(cust)
	var prog := UI.button("Progress", 196, UI.BUTTON_H, 19)
	prog.pressed.connect(func() -> void: progress_panel.open())
	row.add_child(prog)
	return col


func _build_right() -> VBoxContainer:
	var col := UI.vbox(10)
	col.custom_minimum_size = Vector2(COL_W, 0)
	_chal_title = UI.label("Today's challenges", 22, UI.COLOR_WARN)
	col.add_child(_chal_title)
	_challenges = UI.vbox(4)
	col.add_child(_challenges)
	col.add_child(UI.label("Online", 22, UI.COLOR_WARN))
	col.add_child(_menu_button("Practice online (this device)", func() -> void: practice_online.emit()))
	col.add_child(_menu_button("Host a game on this Wi-Fi", func() -> void: host_lan.emit()))
	var join_row := UI.hbox(8)
	col.add_child(join_row)
	_ip_edit = _line_edit(Settings.last_address, "Host's address, e.g. 192.168.1.20")
	join_row.add_child(_ip_edit)
	var join := UI.button("Join", 120)
	join.pressed.connect(func() -> void:
		Settings.set_text("last_address", _ip_edit.text.strip_edges())
		join_lan.emit(_ip_edit.text.strip_edges()))
	join_row.add_child(join)
	_help = UI.label(HOW_TO_PLAY, 16)
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help.custom_minimum_size = Vector2(COL_W, 0)
	_help.visible = false
	var help_btn := UI.button("How to play", COL_W, 44, 17)
	help_btn.pressed.connect(func() -> void:
		_help.visible = not _help.visible
		_chal_title.visible = not _help.visible
		_challenges.visible = not _help.visible)
	col.add_child(help_btn)
	col.add_child(_help)
	return col


func _build_lobby() -> void:
	_lobby_title = UI.label("Lobby", 26)
	_lobby.add_child(_lobby_title)
	_lobby_info = UI.label("", 17, UI.COLOR_DIM)
	_lobby_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby.add_child(_lobby_info)
	_lobby_names = UI.label("", 20)
	_lobby.add_child(_lobby_names)
	_start_btn = _menu_button("Start match (bots fill empty seats)", func() -> void: start_match.emit())
	_lobby.add_child(_start_btn)
	_lobby.add_child(_menu_button("Leave", func() -> void: leave.emit()))


func _menu_button(text: String, on_press: Callable) -> Button:
	var b := UI.button(text, COL_W, UI.BUTTON_H, 20)
	b.pressed.connect(on_press)
	return b


func _line_edit(text: String, placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, UI.BUTTON_H)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", 20)
	return e


func _refresh() -> void:
	if _bar == null:
		return
	_bar.set_total(int(Profile.data["xp"]))
	var s: MatchSetup = Profile.last_setup()
	_quick.text = "Quick play\n%s · %s · %d %s bot%s" % [MatchSetup.label_for_size(s.size), MatchSetup.label_for_type(s.map_type),
		s.bots, MatchSetup.label_for_difficulty(s.difficulty), "" if s.bots == 1 else "s"]
	var today: String = Progression.today()
	var best: int = Profile.daily_best(today)
	_daily.text = "Daily Challenge — %s · %s" % [MatchSetup.label_for_type(MatchSetup.daily(today).map_type),
		"best score %d" % best if best >= 0 else "not played yet"]
	var new_player: bool = not bool(Profile.data["tutorial_done"])
	_tutorial.text = "Tutorial ★" if new_player else "Tutorial"
	_tutorial.add_theme_color_override("font_color", UI.COLOR_WARN if new_player else UI.COLOR_TEXT)
	MenuProgressPanel.fill_challenges(_challenges, 17)


func player_name() -> String:
	var n: String = _name_edit.text.strip_edges()
	return n if n != "" else "Player"


func show_main(status: String) -> void:
	visible = true
	_main.visible = true
	_lobby.visible = false
	_status.text = status
	if status == "" and not bool(Profile.data["tutorial_done"]) and int(Profile.stats()["matches"]) == 0:
		_status.text = "New here? Try the Tutorial ★ first — it takes about five minutes."
	_refresh()


func show_waiting(text: String) -> void:
	visible = true
	_main.visible = false
	_lobby.visible = true
	_lobby_title.text = "Connecting…"
	_lobby_info.text = text
	_lobby_names.text = ""
	_start_btn.visible = false
	_status.text = ""


func show_lobby(names: Array, is_host: bool, addresses: PackedStringArray) -> void:
	visible = true
	_main.visible = false
	_lobby.visible = true
	_lobby_title.text = "Lobby — %d / %d players" % [names.size(), Protocol.MAX_PLAYERS]
	if is_host and not addresses.is_empty():
		_lobby_info.text = "Friends on the same Wi-Fi join with: %s" % ", ".join(addresses)
	elif is_host:
		_lobby_info.text = "Waiting for players…"
	else:
		_lobby_info.text = "Waiting for the host to start the match…"
	var lines: Array[String] = []
	for n in names:
		lines.append("• %s" % String(n))
	_lobby_names.text = "\n".join(lines)
	_start_btn.visible = is_host
	_status.text = ""
