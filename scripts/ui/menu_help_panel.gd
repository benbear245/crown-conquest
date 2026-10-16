class_name MenuHelpPanel
extends ColorRect

# "How to play": the rules on one page, with a shortcut to the tutorial.

signal tutorial_pressed

const W: int = 1100
const RULES: Array[Array] = [
	["Start", "Place your Crown on plains, forest or hills. Tap free land next to your border to grow."],
	["Troops", "The slider sets how many troops each tap sends. Troops grow fastest while the troop bar is green."],
	["Attack", "After the 1:00 peace, tap enemy land to attack. Take the centre of an enemy Crown to knock them out."],
	["Build & spy", "Long-press your own land to build. Long-press a rival to scout, spy or offer a truce."],
	["Extras", "Hold Shrines (◆) for bonuses. Tap ♛ Crown for upgrades and abilities."],
	["Win", "Be the last Crown standing, own 60% of the land, or lead when the 15:00 clock runs out."],
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.75)
	var panel := UI.card(UI.COLOR_WARN, 26)
	UI.centre(panel, W, 100)
	add_child(panel)
	var v := UI.vbox(14)
	panel.add_child(v)
	v.add_child(UI.label("How to play", 34, UI.COLOR_WARN))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	v.add_child(grid)
	for r in RULES:
		var head := UI.label(String(r[0]), 22, UI.COLOR_WARN)
		head.custom_minimum_size = Vector2(170, 0)
		grid.add_child(head)
		var body := UI.label(String(r[1]), 21)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(W - 52 - 194, 0)
		grid.add_child(body)
	var row := UI.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	var tut := UI.outline_button("Play the tutorial", UI.COLOR_WARN, 260, UI.BUTTON_H, 20)
	tut.pressed.connect(func() -> void:
		visible = false
		tutorial_pressed.emit())
	row.add_child(tut)
	var close := UI.primary_button("Got it", 200, UI.BUTTON_H, 22)
	close.pressed.connect(func() -> void: visible = false)
	row.add_child(close)
	visible = false
