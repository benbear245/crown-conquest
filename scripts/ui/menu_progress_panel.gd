class_name MenuProgressPanel
extends ColorRect

# Your level, lifetime stats, today's daily challenges and the trophy shelf
# of achievements.

signal back

const W: int = 1400

var _bar: XpBar
var _stats: Label
var _challenges: VBoxContainer
var _shelf: GridContainer
var _shelf_title: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.03, 0.04, 0.07, 1.0)
	var panel := UI.panel(22)
	UI.centre(panel, W, 100)
	add_child(panel)
	var v := UI.vbox(14)
	panel.add_child(v)
	var head := UI.hbox(16)
	v.add_child(head)
	head.add_child(UI.label("Progress", 34, UI.COLOR_WARN))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var back_btn := UI.outline_button("Back", UI.COLOR_DIM, 180)
	back_btn.pressed.connect(func() -> void: back.emit())
	head.add_child(back_btn)
	var body := UI.hbox(28)
	v.add_child(body)
	var left := UI.vbox(10)
	left.custom_minimum_size = Vector2(430, 0)
	body.add_child(left)
	_bar = XpBar.new(34, 18)
	left.add_child(_bar)
	_stats = UI.label("", 18)
	left.add_child(_stats)
	left.add_child(UI.label("Today's challenges", 22, UI.COLOR_WARN))
	_challenges = UI.vbox(6)
	left.add_child(_challenges)
	var right := UI.vbox(10)
	body.add_child(right)
	_shelf_title = UI.label("", 22, UI.COLOR_WARN)
	right.add_child(_shelf_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_shelf = GridContainer.new()
	_shelf.columns = 4
	_shelf.add_theme_constant_override("h_separation", 10)
	_shelf.add_theme_constant_override("v_separation", 10)
	scroll.add_child(_shelf)
	visible = false


func open() -> void:
	visible = true
	_bar.set_total(int(Profile.data["xp"]))
	var st: Dictionary = Profile.stats()
	var fastest: float = float(st["fastest_win"])
	_stats.text = "Matches played: %d\nWins: %d\nCrowns taken: %d\nBest land: %.1f%%\nFastest win: %s\nOnline matches: %d" % [
		int(st["matches"]), int(st["wins"]), int(st["crowns"]), float(st["best_peak_pct"]),
		GameState.format_time(fastest) if fastest > 0.0 else "—", int(st["online_matches"]),
	]
	fill_challenges(_challenges, 17)
	UI.clear_children(_shelf)
	var earned: int = 0
	for id: String in Progression.ACHIEVEMENTS.keys():
		var a: Array = Progression.ACHIEVEMENTS[id]
		var has: bool = Profile.has_achievement(id)
		earned += 1 if has else 0
		_shelf.add_child(_trophy(String(a[0]), String(a[1]), has))
	_shelf_title.text = "Trophy shelf — %d / %d" % [earned, Progression.ACHIEVEMENTS.size()]


# Lists today's challenges with progress into box (also used by the start menu).
static func fill_challenges(box: VBoxContainer, font_size: int, footer: bool = true) -> void:
	UI.clear_children(box)
	for c: Dictionary in Profile.daily_challenges():
		var done: bool = bool(c["done"])
		var prog: String = "done" if done else "%d / %d" % [int(c["progress"]), int(c["target"])]
		var l := UI.label("%s %s  (%s)" % ["✔" if done else "•", String(c["text"]), prog], font_size,
			UI.COLOR_GOOD if done else UI.COLOR_TEXT)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
	if footer:
		box.add_child(UI.label("+%d XP each. New ones every day." % Balance.XP_PER_DAILY_CHALLENGE, font_size - 2, UI.COLOR_DIM))


static func _trophy(title: String, desc: String, earned: bool) -> PanelContainer:
	var p := UI.panel(10)
	p.custom_minimum_size = Vector2(205, 112)
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel").duplicate()
	sb.bg_color = Color(0.30, 0.24, 0.08, 0.95) if earned else Color(0.12, 0.13, 0.16, 0.95)
	p.add_theme_stylebox_override("panel", sb)
	var v := UI.vbox(4)
	p.add_child(v)
	v.add_child(UI.label(("★ " if earned else "☆ ") + title, 17, UI.COLOR_WARN if earned else UI.COLOR_DIM))
	var d := UI.label(desc, 14, UI.COLOR_TEXT if earned else UI.COLOR_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(185, 0)
	v.add_child(d)
	return p
