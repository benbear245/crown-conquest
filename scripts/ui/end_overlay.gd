class_name EndOverlay
extends ColorRect

# Victory / defeat screen with stats, Play again, Watch and Main menu. After
# "Watch" it stays hidden until a new ending event (or a new match).

signal play_again_pressed
signal menu_pressed

# Extra line under the stats (the Daily Challenge score). Set by game.gd.
var extra_text: String = ""
var xp_panel: XpPanel
var victory_effect: VictoryEffect
var _extra: Label
var _again: Button
var _effect_played: bool = false

var _sim: Simulation
var _title: Label
var _subtitle: Label
var _stats: Label
var _dismissed_id: int = -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.55)
	visible = false
	victory_effect = VictoryEffect.new()
	add_child(victory_effect)
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
	_extra = UIStyle.label("", 22, UIStyle.COLOR_WARN)
	_extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_extra)
	xp_panel = XpPanel.new()
	vbox.add_child(xp_panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vbox.add_child(row)
	_again = UIStyle.button("Play again", 170)
	_again.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_again.pressed.connect(func() -> void: play_again_pressed.emit())
	row.add_child(_again)
	var watch := UIStyle.button("Watch", 170)
	watch.alignment = HORIZONTAL_ALIGNMENT_CENTER
	watch.pressed.connect(func() -> void: _dismissed_id = _current_id())
	row.add_child(watch)
	var menu := UIStyle.button("Main menu", 170)
	menu.alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.pressed.connect(func() -> void: menu_pressed.emit())
	row.add_child(menu)


func setup(sim: Simulation) -> void:
	_sim = sim


func reset() -> void:
	_dismissed_id = -1
	extra_text = ""
	_effect_played = false
	xp_panel.clear()
	victory_effect.play(0)


# XP, level-ups, unlocks and achievements for this match (game.gd calls it
# once, when the match is over for you).
func show_progress(summary: Dictionary, achievements: Array[String]) -> void:
	xp_panel.play(summary, achievements)


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
	var ally: Player = _sim.ally_of(me)
	if ally != null and ally.is_alive:
		subtitle = "Your Crown has fallen — your ally %s fights on." % ally.display_name
	if state.phase == Balance.PHASE_ENDED:
		subtitle = state.win_reason
		if _sim.local_won():
			title = "Your team wins!" if state.teams_mode else "Victory!"
			if not _effect_played:
				_effect_played = true
				var fx: int = int(SaveData.cosmetic("effect"))
				victory_effect.play(fx if SaveData.effect_unlocked(fx) else 0)
		elif state.winner_id == 0:
			title = "Match ended"
		elif state.teams_mode:
			title = "Team %s wins" % _sim.team_name(state.winner_team)
		else:
			var w: Player = state.get_player(state.winner_id)
			title = "%s wins" % (w.display_name if w != null else "Someone")
	var daily: bool = _sim.config != null and _sim.config.mode == MatchConfig.Mode.DAILY
	_again.text = "Try again" if daily else "Play again"
	_extra.text = extra_text
	_extra.visible = extra_text != ""
	_title.text = title
	_subtitle.text = subtitle
	var peak_pct: float = 0.0
	var crowns: int = 0
	if me != null:
		peak_pct = 100.0 * float(me.peak_land) / float(maxi(state.total_usable_tiles(), 1))
		crowns = me.crowns_captured
	_stats.text = "Time %s    Peak land %.1f%%    Crowns taken %d" % [GameState.format_time(state.match_time), peak_pct, crowns]
