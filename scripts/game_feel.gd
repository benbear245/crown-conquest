class_name GameFeel
extends RefCounted

# Turns one simulation event into what the player sees, hears and feels:
# banners, floating numbers, sounds, vibration, screen shake and slow motion.
# Bigger reactions when the event involves the local player.

const SHAKE_CROWN_FALL: float = 10.0
const SHAKE_MY_CROWN: float = 22.0


static func handle(game: Node, e: Dictionary) -> void:
	var sim: Simulation = game.sim()
	var hud: HUD = game.hud()
	var audio: GameAudio = game.audio()
	var me: int = sim.local_player_id
	match String(e["type"]):
		"announce":
			var to: Array = e.get("to", [])
			if to.is_empty() or to.has(me):
				hud.banners.push_text(String(e["text"]))
		"crown_alert":
			if int(e["player_id"]) == me:
				hud.banners.push_crown_alert()
				audio.play("crown_alarm")
				Settings.vibrate(200)
		"crown_fell":
			_crown_fell(game, e, me)
		"loot":
			if int(e["player_id"]) == me:
				var pos := Vector2(float(e["x"]) + 0.5, float(e["y"]))
				game.overlay().add_floater(pos, "+%d loot" % int(e["amount"]), Color(1, 0.9, 0.4))
				audio.play("loot", -4.0)
		"shrine_taken":
			audio.play("shrine", -2.0 if int(e["player_id"]) == me else -10.0)
			if int(e["player_id"]) == me:
				game.overlay().add_floater(Vector2(float(e["x"]) + 0.5, float(e["y"]) - 2.0), Shrine.kind_label(int(e["kind"])), MapOverlay.shrine_color(int(e["kind"])), 1.2)
		"spy_done":
			if int(e["spender_id"]) == me:
				audio.play("spy")
			elif int(e["target_id"]) == me:
				hud.banners.push_text("Someone is watching you…", UI.COLOR_WARN, Balance.SPY_WARNING_SEC)
		"spy_caught":
			if int(e["spender_id"]) == me or int(e["target_id"]) == me:
				audio.play("spy")
				Settings.vibrate(60)
		"truce_offer":
			if int(e["to_id"]) == me:
				var from: Player = sim.state.get_player(int(e["from_id"]))
				if from != null:
					hud.banners.push_truce_offer(from.id, from.display_name, Balance.TRUCE_HUMAN_REPLY_SEC)
		"final_siege":
			audio.set_siege_music(true)
			game.camera().shake(6.0)
		"match_started":
			audio.set_siege_music(false)
		"match_ended":
			audio.play("crown_fall")


static func _crown_fell(game: Node, e: Dictionary, me: int) -> void:
	var involved: bool = int(e["victim_id"]) == me or int(e["capturer_id"]) == me
	var cam: CameraRig = game.camera()
	cam.shake(SHAKE_MY_CROWN if involved else SHAKE_CROWN_FALL)
	game.audio().play("crown_fall", 0.0 if involved else -8.0)
	Settings.vibrate(400 if involved else 120)
	if involved:
		game.start_slow_mo()
	if int(e["capturer_id"]) == me and int(e["plunder"]) > 0:
		var pos := Vector2(float(e["x"]) + 0.5, float(e["y"]) - 2.0)
		game.overlay().add_floater(pos, "+%d plunder" % int(e["plunder"]), Color(1, 0.85, 0.2), 1.6)
