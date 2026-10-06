class_name EndOverlay
extends ColorRect

# Victory / defeat screen with stats, Play again and Watch. After "Watch" it
# stays hidden until a new ending event (or a new match).

signal play_again_pressed

var _sim: Simulation
var _title: Label
var _subtitle: Label
var _stats: Label
var _dismissed_id: int = -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.55)
	visible = false
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UIStyle.panel()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)
	_title = UIStyle.label("", 44)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title)
	_subtitle = UIStyle.label("", 20)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_subtitle)
	_stats = UIStyle.label("", 18)
	_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_stats)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vbox.add_child(row)
	var again := UIStyle.button("Play again", 170)
	again.alignment = HORIZONTAL_ALIGNMENT_CENTER
	again.pressed.connect(func() -> void: play_again_pressed.emit())
	row.add_child(again)
	var watch := UIStyle.button("Watch", 170)
	watch.alignment = HORIZONTAL_ALIGNMENT_CENTER
	watch.pressed.connect(func() -> void: _dismissed_id = _current_id())
	row.add_child(watch)


func setup(sim: Simulation) -> void:
	_sim = sim


func reset() -> void:
	_dismissed_id = -1


# A different id per ending situation, so a new event re-shows the overlay.
func _current_id() -> int:
	var state: GameState = _sim.state
	var id: int = 0
	if state.phase == Balance.PHASE_ENDED:
		id = 1000 + state.winner_id
	var me: Player = state.get_player(_sim.local_player_id)
	if me != null and not me.is_alive:
		id += 1
	return id


func update_view() -> void:
	if _sim == null:
		return
	var state: GameState = _sim.state
	var me: Player = state.get_player(_sim.local_player_id)
	var should_show: bool = state.phase == Balance.PHASE_ENDED or (me != null and not me.is_alive)
	if not should_show or _current_id() == _dismissed_id:
		visible = false
		return
	visible = true
	var title: String = "Defeated"
	var subtitle: String = "Your Crown has fallen — you can watch the rest of the match."
	if state.phase == Balance.PHASE_ENDED:
		subtitle = state.win_reason
		if state.winner_id == _sim.local_player_id:
			title = "Victory!"
		elif state.winner_id == 0:
			title = "Match ended"
		else:
			var w: Player = state.get_player(state.winner_id)
			title = "%s wins" % (w.display_name if w != null else "Someone")
	_title.text = title
	_subtitle.text = subtitle
	var peak_pct: float = 0.0
	var crowns: int = 0
	if me != null:
		peak_pct = 100.0 * float(me.peak_land) / float(maxi(state.total_usable_tiles(), 1))
		crowns = me.crowns_captured
	_stats.text = "Time %s    Peak land %.1f%%    Crowns taken %d" % [GameState.format_time(state.match_time), peak_pct, crowns]
