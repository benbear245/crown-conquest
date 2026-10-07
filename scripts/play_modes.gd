class_name PlayModes
extends Node

# Starting, hosting, joining and leaving matches. Builds the right
# GameSession for each choice on the start menu and hands it to the game.

signal session_changed(session: GameSession)

var _hud: HUD
var _session: GameSession
var _host: NetHost
var _practice: bool = false


func setup(hud: HUD) -> void:
	_hud = hud
	var menu: HudStartMenu = hud.start_menu
	menu.play_bots.connect(_play_bots)
	menu.practice_online.connect(func() -> void: _start_host(false))
	menu.host_lan.connect(func() -> void: _start_host(true))
	menu.join_lan.connect(_join)
	menu.start_match.connect(func() -> void:
		if _session != null:
			_session.request_start())
	menu.leave.connect(func() -> void: _leave(""))
	hud.new_map_requested.connect(_on_new_map)
	menu.show_main("")


func _play_bots() -> void:
	_leave_quietly()
	var s := LocalSession.new()
	_use(s)
	s.start(int(Time.get_unix_time_from_system() * 1000.0) ^ randi())


# Practice runs a real host in this app with no network port; hosting on
# Wi-Fi also opens the port so other phones can join.
func _start_host(listen: bool) -> void:
	_leave_quietly()
	_host = NetHost.new(true)
	add_child(_host)
	if listen:
		var err: int = _host.listen(Protocol.DEFAULT_PORT)
		if err != OK:
			_leave("Couldn't open port %d (error %d)." % [Protocol.DEFAULT_PORT, err])
			return
	var link := LoopbackLink.new()
	_host.attach_loopback(link)
	_practice = not listen
	_use(NetSession.new(link, _hud.start_menu.player_name()))
	if listen:
		_hud.start_menu.show_lobby([_hud.start_menu.player_name()], true, NetHost.lan_addresses())


func _join(address: String) -> void:
	if address == "":
		_hud.start_menu.show_main("Type the host's address first.")
		return
	_leave_quietly()
	var link := ENetLink.new()
	var err: int = link.connect_to(address, Protocol.DEFAULT_PORT)
	if err != OK:
		_hud.start_menu.show_main("Couldn't connect to %s (error %d)." % [address, err])
		return
	_use(NetSession.new(link, _hud.start_menu.player_name()))
	_hud.start_menu.show_waiting("Joining %s…" % address)


func _use(s: GameSession) -> void:
	_session = s
	s.match_ready.connect(func() -> void: _hud.start_menu.visible = false)
	s.lobby_changed.connect(_on_lobby)
	s.ended.connect(func(reason: String) -> void: _leave(reason))
	session_changed.emit(s)


func _on_lobby(names: Array, is_host: bool) -> void:
	if _practice and is_host:
		_session.request_start()
		return
	_hud.start_menu.show_lobby(names, is_host, NetHost.lan_addresses() if _host != null else PackedStringArray())


# "New map" / "Play again": a fresh local game, or back to the menu online.
func _on_new_map() -> void:
	if _session is LocalSession:
		_play_bots()
	else:
		_leave("")


func _leave(reason: String) -> void:
	_leave_quietly()
	session_changed.emit(null)
	_hud.set_menu_open(false)
	_hud.start_menu.show_main(reason)


func _leave_quietly() -> void:
	if _session != null:
		_session.close()
		_session = null
	if _host != null:
		_host.stop()
		_host.queue_free()
		_host = null
	_practice = false
