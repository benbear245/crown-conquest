extends Node

# Headless server for online matches (no player of its own). The first
# person to join can start the match; bots fill the empty seats.
#
# Run with:
#   godot --headless --path <project_dir> res://scenes/server.tscn -- --port 24680

var _host: NetHost


func _ready() -> void:
	var port: int = Protocol.DEFAULT_PORT
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--port":
			port = args[i + 1].to_int()
	_host = NetHost.new(false)
	add_child(_host)
	var err: int = _host.listen(port)
	if err != OK:
		push_error("[server] Could not listen on port %d (error %d)." % [port, err])
		get_tree().quit(1)
		return
	print("[server] Crown Conquest server v%d listening on UDP port %d" % [Protocol.VERSION, port])
