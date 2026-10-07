class_name CommandRouter
extends RefCounted

# Every player action as a named command with plain arguments, so the same
# path serves a local game (called directly) and an online one (the command
# arrives as a network message). Arguments are checked here because online
# they come from someone else's device.

const COMMANDS: Dictionary = {
	# name: number of arguments
	"place_crown": 2,      # x, y
	"expand": 3,           # x, y, send fraction
	"attack": 3,           # x, y, send fraction
	"retreat": 1,          # index among your attacks
	"build": 3,            # building type, x, y
	"upgrade_fort": 2,     # x, y
	"build_wall": 2,       # x, y
	"buy_keep": 1,         # level
	"move_crown": 2,       # x, y
	"launch_boat": 5,      # port x, port y, target x, target y, fraction
	"ability": 3,          # ability id, target x, target y (-1 when unused)
	"offer_truce": 1,      # target player id
	"answer_truce": 2,     # offering player id, accepted
	"spy": 2,              # target player id, action
	"disinformation": 1,   # look strong
}


# Runs one command for player_id. Returns true if the sim accepted it.
static func apply(sim: Simulation, player_id: int, cmd: String, args: Array) -> bool:
	if not COMMANDS.has(cmd) or args.size() != int(COMMANDS[cmd]):
		return false
	for a in args:
		var t: int = typeof(a)
		if t != TYPE_INT and t != TYPE_FLOAT and t != TYPE_BOOL:
			return false
	match cmd:
		"place_crown":
			return sim.player_place_crown(player_id, int(args[0]), int(args[1]))
		"expand":
			return sim.player_expand(player_id, int(args[0]), int(args[1]), _frac(args[2]))
		"attack":
			return sim.player_attack(player_id, int(args[0]), int(args[1]), _frac(args[2]))
		"retreat":
			return sim.player_retreat(player_id, int(args[0]))
		"build":
			return sim.player_build(player_id, int(args[0]), int(args[1]), int(args[2]))
		"upgrade_fort":
			return sim.player_upgrade_fort(player_id, int(args[0]), int(args[1]))
		"build_wall":
			return sim.player_build_wall(player_id, int(args[0]), int(args[1]))
		"buy_keep":
			return sim.player_buy_keep(player_id, int(args[0]))
		"move_crown":
			return sim.player_move_crown(player_id, int(args[0]), int(args[1]))
		"launch_boat":
			return sim.player_launch_boat(player_id, int(args[0]), int(args[1]), int(args[2]), int(args[3]), _frac(args[4]))
		"ability":
			return sim.player_activate_ability(player_id, int(args[0]), int(args[1]), int(args[2]))
		"offer_truce":
			return sim.player_offer_truce(player_id, int(args[0]))
		"answer_truce":
			return sim.player_answer_truce(player_id, int(args[0]), bool(args[1]))
		"spy":
			return sim.player_spy(player_id, int(args[0]), int(args[1]))
		"disinformation":
			return sim.player_disinformation(player_id, bool(args[0]))
	return false


static func _frac(v: Variant) -> float:
	var f: float = float(v)
	if is_nan(f):
		return Balance.SEND_MIN_FRACTION
	return clampf(f, Balance.SEND_MIN_FRACTION, Balance.SEND_MAX_FRACTION)
