class_name HudStartMenu
extends ColorRect

# First screen: play vs bots, practice online on this device, host a game on
# your Wi-Fi, or join one. Also the lobby while waiting for the host to start.

signal play_bots
signal practice_online
signal host_lan
signal join_lan(address: String)
signal start_match
signal leave

const WIDTH: int = 560
const HOW_TO_PLAY: String = """• Place your Crown, then tap free land next to your border to grow.
• The slider sets how many troops each tap sends. Troops grow fastest while the bar is green.
• After 1:00, tap enemy land to attack. Take an enemy Crown's centre to knock them out.
• Long-press your land to build; long-press a rival to spy, scout or offer a truce.
• Hold the Shrines (◆) for bonuses. Tap ♛ Crown for upgrades.
• Win: last Crown standing, own 60% of the land, or lead at 15:00."""

var _main: VBoxContainer
var _lobby: VBoxContainer
var _status: Label
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _lobby_title: Label
var _lobby_info: Label
var _lobby_names: Label
var _start_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.03, 0.04, 0.07, 1.0)
	var panel := UI.panel(20)
	UI.centre(panel, WIDTH, 100)
	add_child(panel)
	var v := UI.vbox(12)
	panel.add_child(v)
	var title := UI.label("Crown Conquest", 40, UI.COLOR_WARN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_main = UI.vbox(10)
	v.add_child(_main)
	_lobby = UI.vbox(10)
	v.add_child(_lobby)
	_status = UI.label("", 17, UI.COLOR_BAD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_status)
	_build_main()
	_build_lobby()
	var version := UI.label("Test build %s — thanks for testing!" % BugReport.version_label(), 14, UI.COLOR_DIM)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(version)
	show_main("")


func _build_main() -> void:
	var name_row := UI.hbox(8)
	_main.add_child(name_row)
	name_row.add_child(UI.label("Your name", 18, UI.COLOR_DIM))
	_name_edit = _line_edit(Settings.player_name, "Player")
	_name_edit.max_length = 16
	_name_edit.text_changed.connect(func(t: String) -> void: Settings.set_text("player_name", t))
	name_row.add_child(_name_edit)
	_main.add_child(_menu_button("Play vs bots", func() -> void: play_bots.emit()))
	var help := UI.label(HOW_TO_PLAY, 16)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(WIDTH - 40, 0)
	help.visible = false
	var help_btn := UI.button("How to play", WIDTH - 40, 44, 17)
	help_btn.pressed.connect(func() -> void: help.visible = not help.visible)
	_main.add_child(_menu_button("Practice online (this device)", func() -> void: practice_online.emit()))
	_main.add_child(_menu_button("Host a game on this Wi-Fi", func() -> void: host_lan.emit()))
	var join_row := UI.hbox(8)
	_main.add_child(join_row)
	_main.add_child(help_btn)
	_main.add_child(help)
	_ip_edit = _line_edit(Settings.last_address, "Host's address, e.g. 192.168.1.20")
	join_row.add_child(_ip_edit)
	var join := UI.button("Join", 120)
	join.pressed.connect(func() -> void:
		Settings.set_text("last_address", _ip_edit.text.strip_edges())
		join_lan.emit(_ip_edit.text.strip_edges()))
	join_row.add_child(join)


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
	var b := UI.button(text, WIDTH - 40, UI.BUTTON_H, 20)
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


func player_name() -> String:
	var n: String = _name_edit.text.strip_edges()
	return n if n != "" else "Player"


func show_main(status: String) -> void:
	visible = true
	_main.visible = true
	_lobby.visible = false
	_status.text = status


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
