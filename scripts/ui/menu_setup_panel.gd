class_name MenuSetupPanel
extends ColorRect

# "Play vs bots" options: map size, map type, number of bots and difficulty.
# Starting remembers the choice for Quick play.

signal start(setup: MatchSetup)
signal back

const W: int = 860

var _setup: MatchSetup = MatchSetup.new()
var _rows: Dictionary = {}          # option name -> Array[Button]
var _bots_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	color = Color(0.03, 0.04, 0.07, 1.0)
	var panel := UI.panel(22)
	UI.centre(panel, W, 100)
	add_child(panel)
	var v := UI.vbox(16)
	panel.add_child(v)
	v.add_child(UI.label("Play vs bots", 34, UI.COLOR_WARN))
	_add_choice(v, "size", "Map size", ["Small", "Medium", "Large"])
	_add_choice(v, "type", "Map type", ["Continent", "Archipelago", "Highlands", "Random"])
	_add_choice(v, "difficulty", "Bots", ["Mixed", "Easy", "Normal", "Hard"])
	var bots_row := UI.hbox(12)
	v.add_child(bots_row)
	var bl := UI.label("How many", 20, UI.COLOR_DIM)
	bl.custom_minimum_size = Vector2(150, 0)
	bots_row.add_child(bl)
	var minus := UI.button("−", 72)
	minus.pressed.connect(func() -> void: _change_bots(-1))
	bots_row.add_child(minus)
	_bots_label = UI.label("", 24)
	_bots_label.custom_minimum_size = Vector2(150, 0)
	_bots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bots_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bots_row.add_child(_bots_label)
	var plus := UI.button("+", 72)
	plus.pressed.connect(func() -> void: _change_bots(1))
	bots_row.add_child(plus)
	var row := UI.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var back_btn := UI.button("Back", 200, UI.BUTTON_H, 20)
	back_btn.pressed.connect(func() -> void: back.emit())
	row.add_child(back_btn)
	var go := UI.button("Start match", 320, UI.BUTTON_H + 8, 24)
	go.pressed.connect(func() -> void:
		var s: MatchSetup = _setup.clamped()
		s.mode = MatchSetup.MODE_SKIRMISH
		start.emit(s))
	row.add_child(go)
	visible = false


func open(s: MatchSetup) -> void:
	_setup = s.clamped()
	_refresh()
	visible = true


func _add_choice(parent: VBoxContainer, key: String, title: String, options: Array) -> void:
	var row := UI.hbox(8)
	parent.add_child(row)
	var l := UI.label(title, 20, UI.COLOR_DIM)
	l.custom_minimum_size = Vector2(150, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var buttons: Array[Button] = []
	for i in range(options.size()):
		var b := UI.toggle(String(options[i]), 150, UI.BUTTON_H, 19)
		var value: int = i - 1 if key == "difficulty" else i      # difficulty starts at Mixed (-1)
		b.pressed.connect(func() -> void: _choose(key, value))
		row.add_child(b)
		buttons.append(b)
	_rows[key] = buttons


func _choose(key: String, value: int) -> void:
	match key:
		"size":
			_setup.size = value
		"type":
			_setup.map_type = value
		"difficulty":
			_setup.difficulty = value
	_setup = _setup.clamped()
	_refresh()


func _change_bots(d: int) -> void:
	_setup.bots += d
	_setup = _setup.clamped()
	_refresh()


func _refresh() -> void:
	_mark("size", _setup.size)
	_mark("type", _setup.map_type)
	_mark("difficulty", _setup.difficulty + 1)
	_bots_label.text = "%d bot%s" % [_setup.bots, "" if _setup.bots == 1 else "s"]


func _mark(key: String, index: int) -> void:
	var buttons: Array[Button] = _rows[key]
	for i in range(buttons.size()):
		buttons[i].set_pressed_no_signal(i == index)
