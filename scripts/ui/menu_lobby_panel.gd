class_name MenuLobbyPanel
extends ColorRect

# Online lobby: connecting, who has joined, and (for the host) Start.

signal start_match
signal leave

const W: int = 760

var _title: Label
var _info: Label
var _address: Label
var _names: Label
var _start_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.03, 0.04, 0.07, 1.0)
	var panel := UI.card(UI.COLOR_GOOD, 26)
	UI.centre(panel, W, 100)
	add_child(panel)
	var v := UI.vbox(14)
	panel.add_child(v)
	_title = UI.label("", 32, UI.COLOR_WARN)
	v.add_child(_title)
	_info = UI.label("", 20, UI.COLOR_DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(W - 52, 0)
	v.add_child(_info)
	_address = UI.label("", 40, UI.COLOR_WARN)
	v.add_child(_address)
	_names = UI.label("", 24)
	v.add_child(_names)
	_start_btn = UI.primary_button("Start match", W - 52, 84, 28)
	_start_btn.pressed.connect(func() -> void: start_match.emit())
	v.add_child(_start_btn)
	var hint := UI.label("Empty seats are filled with bots.", 16, UI.COLOR_DIM)
	v.add_child(hint)
	var leave_btn := UI.outline_button("Leave", UI.COLOR_DIM, W - 52, UI.BUTTON_H, 20)
	leave_btn.pressed.connect(func() -> void: leave.emit())
	v.add_child(leave_btn)
	visible = false


func show_waiting(text: String) -> void:
	visible = true
	_title.text = "Connecting…"
	_info.text = text
	_names.text = ""
	_address.visible = false
	_start_btn.visible = false


func show_lobby(names: Array, is_host: bool, addresses: PackedStringArray) -> void:
	visible = true
	_title.text = "Lobby — %d of %d players" % [names.size(), Protocol.MAX_PLAYERS]
	_address.visible = is_host and not addresses.is_empty()
	_address.text = "   or   ".join(addresses)
	if _address.visible:
		_info.text = "Friends on the same Wi-Fi tap \"Join a game\" and type this address:"
	elif is_host:
		_info.text = "Waiting for players…"
	else:
		_info.text = "You're in! Waiting for the host to start the match…"
	var lines: Array[String] = []
	for n in names:
		lines.append("• %s" % String(n))
	_names.text = "\n".join(lines)
	_start_btn.visible = is_host
