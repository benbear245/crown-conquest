class_name Tutorial
extends RefCounted

# The guided first match: one passive Easy bot, a short peace, and a list of
# steps that each wait for the player to do one thing. Reads the Simulation
# only; HudTutorial shows the current step and points at its target.

const STEPS: Array[Dictionary] = [
	{"id": "place", "text": "Welcome! Tap a green plains tile to place your Crown. Pick a spot with room to grow."},
	{"id": "expand", "text": "Tap free land next to your border to grow. Each tap sends troops from your pool. Double your land!"},
	{"id": "sweet_spot", "next": true,
		"text": "Troops grow fastest while the troop bar at the top is green — about half full. Spending keeps you in that sweet spot."},
	{"id": "fort", "text": "Long-press your own land and build a Fort. Forts make the land around them much harder to take. A Fort costs troops, so let your pool fill up first."},
	{"id": "peace", "text": "Nobody can attack during the peace. It ends at %s — keep growing until then."},
	{"id": "attack", "text": "Peace is over! Tap the bot's land to attack it."},
	{"id": "shield", "text": "Tap Crown Shield. It protects your Crown for a while when enemies get close."},
	{"id": "crown", "text": "Now take their Crown: keep attacking until you capture the gold tile at its centre."},
]

var step: int = 0
var skipped: bool = false
var _start_land: int = 0
var _next_pressed: bool = false


func current() -> Dictionary:
	return STEPS[step] if step < STEPS.size() else {}


func is_done() -> bool:
	return skipped or step >= STEPS.size()


func text(sim: Simulation) -> String:
	var s: Dictionary = current()
	if s.is_empty():
		return ""
	if String(s["id"]) == "peace":
		return String(s["text"]) % GameState.format_time(sim.state.peace_sec)
	return String(s["text"])


func needs_next_button() -> bool:
	return bool(current().get("next", false))


func press_next() -> void:
	_next_pressed = true


# Moves on past every step the player has already done.
func update(sim: Simulation) -> void:
	var me: Player = sim.state.get_player(sim.local_player_id)
	if me == null or is_done():
		return
	while not is_done() and _step_done(sim, me):
		step += 1
		_next_pressed = false
		_start_land = me.land


func _step_done(sim: Simulation, me: Player) -> bool:
	var state: GameState = sim.state
	var now: float = state.match_time
	match String(current()["id"]):
		"place":
			return me.crown_x >= 0 and state.phase == Balance.PHASE_MATCH
		"expand":
			return me.land >= maxi(_start_land * 2, _start_land + 40)
		"sweet_spot":
			return _next_pressed
		"fort":
			return me.fort_count >= 1
		"peace":
			return not state.is_peace()
		"attack":
			return not sim.attacks_by(me.id).is_empty()
		"shield":
			return me.crown_shield_until > now or me.crown_shield_cd_until > now
		"crown":
			return state.phase == Balance.PHASE_ENDED
	return true


# World position the arrow points at, or (-1, -1) for none.
func target_world(sim: Simulation) -> Vector2:
	var me: Player = sim.state.get_player(sim.local_player_id)
	var bot: Player = _bot(sim)
	match String(current().get("id", "")):
		"expand":
			if me != null and me.crown_x >= 0:
				var mid := Vector2(sim.state.width, sim.state.height) * 0.5
				var c := Vector2(me.crown_x + 0.5, me.crown_y + 0.5)
				var dir: Vector2 = (mid - c).normalized() if mid.distance_to(c) > 1.0 else Vector2.RIGHT
				return c + dir * float(me.crown_zone_radius() + 3)
		"attack", "crown":
			if bot != null and bot.is_alive and bot.crown_x >= 0:
				return Vector2(bot.crown_x + 0.5, bot.crown_y + 0.5)
	return Vector2(-1, -1)


# Ability button to point at, or -1.
func target_ability() -> int:
	return AbilitiesOps.ID_CROWN_SHIELD if String(current().get("id", "")) == "shield" else -1


static func _bot(sim: Simulation) -> Player:
	for p: Player in sim.state.players:
		if p.is_bot:
			return p
	return null
