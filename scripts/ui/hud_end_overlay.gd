class_name HudEndOverlay
extends ColorRect

# Victory / defeat screen with a short recap of the match.

signal play_again_pressed

var _title: Label
var _subtitle: Label
var _stats: Label
var _dismissed_key: String = ""
var _current_key: String = ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.55)
	var panel := UI.panel(18)
	UI.centre(panel, 600, 100)
	add_child(panel)
	var v := UI.vbox(12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	_title = UI.label("", 44)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_subtitle = UI.label("", 20)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_subtitle)
	_stats = UI.label("", 18, UI.COLOR_DIM)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_stats)
	var row := UI.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var again := UI.button("Play again", 180)
	again.pressed.connect(func() -> void: play_again_pressed.emit())
	row.add_child(again)
	var watch := UI.button("Watch", 180)
	watch.pressed.connect(func() -> void: _dismissed_key = _current_key)
	row.add_child(watch)
	visible = false


func reset() -> void:
	_dismissed_key = ""


func refresh(sim: Simulation, local: Player) -> void:
	var state: GameState = sim.state
	var ended: bool = state.phase == Balance.PHASE_ENDED
	var dead: bool = local != null and not local.is_alive
	_current_key = "ended" if ended else ("dead" if dead else "")
	visible = _current_key != "" and _current_key != _dismissed_key
	if not visible:
		return
	if ended:
		var w: Player = state.get_player(state.winner_id)
		if state.winner_id == sim.local_player_id:
			_title.text = "Victory!"
		elif w == null:
			_title.text = "Match ended"
		else:
			_title.text = "%s wins" % w.display_name
		_subtitle.text = state.win_reason
	else:
		_title.text = "Defeated"
		_subtitle.text = "Your Crown has fallen — you can watch the rest of the match."
	if local != null:
		_stats.text = "Time %s   •   Peak land %.1f%%   •   Crowns taken %d   •   Place %d of %d" % [
			GameState.format_time(state.match_time),
			100.0 * float(local.peak_land) / float(maxi(state.total_usable_tiles(), 1)),
			local.crowns_captured, _place(state, local), state.players.size(),
		]


# 1 + everyone who did better: outlived you, or (if you're both still alive)
# won or holds more land.
static func _place(state: GameState, local: Player) -> int:
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
