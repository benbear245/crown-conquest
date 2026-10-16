class_name MatchProgress
extends RefCounted

# Per-frame match upkeep that isn't input: feeding the MatchRecorder and,
# once the match is over for you, saving progress and filling the recap;
# and moving the tutorial on. Split out of game.gd to keep it small.


static func record(hud: HUD, rec: MatchRecorder, tut: Tutorial, cur: Simulation) -> void:
	rec.observe(cur)
	if not rec.should_finish(cur):
		return
	rec.finished = true
	var summary: Dictionary = rec.summary(cur)
	var result: Dictionary
	if rec.mode == MatchSetup.MODE_TUTORIAL:
		var finished: bool = bool(summary["won"]) and tut != null and not tut.skipped
		result = Profile.complete_tutorial() if finished else {}
	else:
		result = Profile.record_match(summary)
	rec.result = result
	match rec.mode:
		MatchSetup.MODE_TUTORIAL:
			hud.recap.set_play_again_text("Replay tutorial")
		MatchSetup.MODE_DAILY:
			hud.recap.set_play_again_text("Retry daily")
		MatchSetup.MODE_ONLINE:
			hud.recap.set_play_again_text("Back to menu")
		_:
			hud.recap.set_play_again_text("Play again")
	hud.recap.show_result(rec, cur, result)


static func show_tutorial(hud: HUD, camera: CameraRig, tut: Tutorial, cur: Simulation) -> void:
	tut.update(cur)
	if tut.is_done() or cur.state.phase == Balance.PHASE_ENDED:
		hud.tutorial.visible = false
		return
	var arrow := Vector2(-1, -1)
	var world: Vector2 = tut.target_world(cur)
	if world.x >= 0.0:
		arrow = camera.world_to_screen(world)
	elif tut.target_ability() >= 0:
		var r: Rect2 = hud.bottom_bar.ability_rect(tut.target_ability())
		arrow = Vector2(r.get_center().x, r.position.y)
	hud.tutorial.show_step(tut.step, Tutorial.STEPS.size(), tut.text(cur), tut.needs_next_button(), arrow)
