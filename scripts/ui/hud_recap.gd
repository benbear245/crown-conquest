class_name HudRecap
extends ColorRect

# End-of-match recap: result, land-over-time graph, best moment, XP earned
# with an animated level bar, and anything new (unlocks, achievements, daily
# challenges, Daily Challenge score). Shown when the match ends or your Crown
# falls; "Watch" hides it to keep spectating.

signal play_again_pressed
signal menu_pressed
signal leveled_up(level: int)

const W: int = 1240

var _title: Label
var _subtitle: Label
var _stats: Label
var _graph: LandGraph
var _moment: Label
var _xp_title: Label
var _xp_lines: GridContainer
var _bar: XpBar
var _level_up: Label
var _news: Label
var _again: Button
var _dismissed_key: String = ""
var _current_key: String = ""
var _has_result: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.6)
	var panel := UI.panel(20)
	UI.centre(panel, W, 100)
	add_child(panel)
	var outer := UI.vbox(14)
	panel.add_child(outer)
	_title = _centred(UI.label("", 44))
	outer.add_child(_title)
	_subtitle = _centred(UI.label("", 20))
	outer.add_child(_subtitle)
	var cols := UI.hbox(28)
	outer.add_child(cols)
	cols.add_child(_build_left())
	cols.add_child(_build_right())
	var row := UI.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.add_child(row)
	_again = UI.button("Play again", 220)
	_again.pressed.connect(func() -> void: play_again_pressed.emit())
	row.add_child(_again)
	var watch := UI.button("Watch", 180)
	watch.pressed.connect(func() -> void: _dismissed_key = _current_key)
	row.add_child(watch)
	var menu := UI.button("Main menu", 220)
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	row.add_child(menu)
	visible = false


func _build_left() -> VBoxContainer:
	var v := UI.vbox(10)
	v.custom_minimum_size = Vector2(580, 0)
	_stats = UI.label("", 18, UI.COLOR_DIM)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_stats)
	v.add_child(UI.label("Your land over time", 16, UI.COLOR_DIM))
	_graph = LandGraph.new()
	v.add_child(_graph)
	_moment = UI.label("", 20, UI.COLOR_WARN)
	_moment.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_moment)
	return v


func _build_right() -> VBoxContainer:
	var v := UI.vbox(8)
	v.custom_minimum_size = Vector2(580, 0)
	_xp_title = UI.label("XP earned", 22)
	v.add_child(_xp_title)
	_xp_lines = GridContainer.new()
	_xp_lines.columns = 2
	_xp_lines.add_theme_constant_override("h_separation", 24)
	v.add_child(_xp_lines)
	_bar = XpBar.new(30, 17)
	_bar.level_up.connect(_on_level_up)
	v.add_child(_bar)
	_level_up = _centred(UI.label("", 30, UI.COLOR_WARN))
	_level_up.pivot_offset = Vector2(290, 20)
	v.add_child(_level_up)
	_news = UI.label("", 18, UI.COLOR_GOOD)
	_news.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_news)
	return v


func _centred(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func reset() -> void:
	_dismissed_key = ""
	_has_result = false
	_level_up.text = ""
	_news.text = ""
	UI.clear_children(_xp_lines)


func set_play_again_text(text: String) -> void:
	_again.text = text


# Fills in progress once, when the match is recorded.
func show_result(rec: MatchRecorder, sim: Simulation, result: Dictionary) -> void:
	_has_result = true
	_graph.set_data(rec.land_samples, MatchRecorder.SAMPLE_EVERY_SEC, Balance.color_for_player(sim.local_player_id))
	var best: Dictionary = rec.best_moment()
	_moment.text = "Best moment: %s at %s" % [best["text"], GameState.format_time(float(best["time"]))] if not best.is_empty() else ""
	UI.clear_children(_xp_lines)
	_level_up.text = ""
	if result.is_empty():
		_xp_title.text = "No XP this time"
		_bar.set_total(int(Profile.data["xp"]))
		_news.text = ""
		return
	for line: Array in result["xp_lines"]:
		_xp_lines.add_child(UI.label(String(line[0]), 18))
		var amt := UI.label("+%d" % int(line[1]), 18, UI.COLOR_GOOD)
		amt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_xp_lines.add_child(amt)
	_xp_title.text = "XP earned: +%d" % int(result["xp_total"])
	_bar.animate_to(int(result["xp_before"]), int(result["xp_before"]) + int(result["xp_total"]))
	_news.text = "\n".join(_news_lines(result))


static func _news_lines(result: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if int(result.get("daily_score", -1)) >= 0:
		var best: int = int(result["daily_best"])
		var tag: String = "  — new best!" if best == int(result["daily_score"]) else "  (best %d)" % best
		lines.append("Daily Challenge score: %d%s" % [int(result["daily_score"]), tag])
	for id: String in result.get("achievements", []):
		lines.append("★ Achievement: %s" % Progression.ACHIEVEMENTS[id][0])
	for text: String in result.get("challenges", []):
		lines.append("✔ Daily challenge done: %s" % text)
	for u: String in result.get("unlocks", []):
		lines.append("+ Unlocked %s" % u)
	return lines


func _on_level_up(level: int) -> void:
	_level_up.text = "Level up!  You're level %d" % level
	_level_up.scale = Vector2(1.4, 1.4)
	var tw := create_tween()
	tw.tween_property(_level_up, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	leveled_up.emit(level)


func refresh(sim: Simulation, local: Player) -> void:
	var state: GameState = sim.state
	var ended: bool = state.phase == Balance.PHASE_ENDED
	var dead: bool = local != null and not local.is_alive
	_current_key = "ended" if ended else ("dead" if dead else "")
	visible = _has_result and _current_key != "" and _current_key != _dismissed_key
	if not visible:
		return
	if ended:
		var w: Player = state.get_player(state.winner_id)
		if state.winner_id == sim.local_player_id:
			_title.text = "Victory!"
		elif w == null:
			_title.text = "Match ended"
		else:
			_title.text = "%s wins" % Look.name_with_title(w)
		_subtitle.text = state.win_reason
	else:
		_title.text = "Defeated"
		_subtitle.text = "Your Crown has fallen — you can watch the rest of the match."
	if local != null:
		_stats.text = "Time %s   •   Peak land %.1f%%   •   Crowns taken %d   •   Place %d of %d" % [
			GameState.format_time(state.match_time),
			100.0 * float(local.peak_land) / float(maxi(state.total_usable_tiles(), 1)),
			local.crowns_captured, place_of(state, local), state.players.size(),
		]


# 1 + everyone who did better: outlived you, or (if you're both still alive)
# won or holds more land.
static func place_of(state: GameState, local: Player) -> int:
	if state.winner_id == local.id:
		return 1
	var place: int = 1
	for p: Player in state.players:
		if p == local:
			continue
		if local.is_alive:
			if p.is_alive and (p.id == state.winner_id or p.land > local.land):
				place += 1
		elif p.is_alive or p.eliminated_at > local.eliminated_at:
			place += 1
	return place
