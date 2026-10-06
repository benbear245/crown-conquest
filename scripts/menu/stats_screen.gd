class_name StatsScreen
extends MenuScreen

# Your record: level, matches, wins, win rate, Crowns, fastest win, best
# Daily score, per mode; and a way into the achievements.

var _grid: GridContainer


func _init(menu_root: MenuRoot) -> void:
	super(menu_root, "Stats")
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 40)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(_grid)
	add_child(back_and_action_row("Achievements", func() -> void: root.show_screen("achievements")))


func refresh() -> void:
	for c: Node in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	var st: Dictionary = SaveData.data.stats
	var info: Dictionary = Progression.level_info(SaveData.xp())
	var matches: int = int(st.matches)
	var wins: int = int(st.wins)
	var fastest: float = float(st.fastest_win_sec)
	var best_daily: int = SaveData.daily_best_ever()
	var by_mode: Dictionary = st.by_mode
	var rows: Array = [
		["Level", "%d  (%s / %s XP)" % [int(info.level), GameState.format_int(int(info.into)), GameState.format_int(int(info.need))]],
		["Total XP", GameState.format_int(SaveData.xp())],
		["Matches", str(matches)],
		["Wins", str(wins)],
		["Win rate", ("%d%%" % roundi(100.0 * wins / matches)) if matches > 0 else "—"],
		["Crowns captured", str(int(st.crowns))],
		["Fastest win", GameState.format_time(fastest) if fastest >= 0.0 else "—"],
		["Best peak land", "%.1f%%" % float(st.best_peak_pct)],
		["Best Daily score", str(best_daily) if int(SaveData.data.daily.played) > 0 else "—"],
		["Achievements", "%d / %d" % [(SaveData.data.achievements as Dictionary).size(), Progression.ACHIEVEMENTS.size()]],
		["Skirmish", _mode_line(by_mode.get("skirmish", [0, 0]))],
		["Teams", _mode_line(by_mode.get("teams", [0, 0]))],
		["Daily Challenge", _mode_line(by_mode.get("daily", [0, 0]))],
	]
	for r: Array in rows:
		var k := UIStyle.label(str(r[0]), 22, UIStyle.COLOR_DIM)
		k.custom_minimum_size = Vector2(230, 0)
		_grid.add_child(k)
		var v := UIStyle.label(str(r[1]), 24)
		v.custom_minimum_size = Vector2(260, 0)
		_grid.add_child(v)


static func _mode_line(pair: Array) -> String:
	return "%d played, %d won" % [int(pair[0]), int(pair[1])]
