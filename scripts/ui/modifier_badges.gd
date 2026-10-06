class_name ModifierBadges
extends VBoxContainer

# Small icons next to the troop bar for every bonus or penalty affecting the
# local player (Underdog, gems, Empire upkeep, Rising Empire, Oathbreaker).
# Tap one to see what it does.

const MAX_BADGES: int = 6
const EXPLAIN_SEC: float = 5.0

var _sim: Simulation
var _row: HBoxContainer
var _badges: Array[Button] = []
var _icons: Array[IconView] = []
var _labels: Array[Label] = []
var _explain_texts: Array[String] = []
var _explain: Label
var _explain_left: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 6)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)
	for i in range(MAX_BADGES):
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.visible = false
		var box := HBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.add_theme_constant_override("separation", 4)
		box.offset_left = 6
		box.offset_right = -6
		var icon := IconView.new(IconView.Kind.UP, 26)
		box.add_child(icon)
		var lbl := UIStyle.label("", UIStyle.FONT_SMALL)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(lbl)
		b.add_child(box)
		var index: int = i
		b.pressed.connect(func() -> void: _show_explain(index))
		_row.add_child(b)
		_badges.append(b)
		_icons.append(icon)
		_labels.append(lbl)
		_explain_texts.append("")
	_explain = UIStyle.label("", UIStyle.FONT_SMALL)
	_explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_explain.custom_minimum_size = Vector2(520, 0)
	_explain.visible = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = UIStyle.PANEL_BG
	bg.set_corner_radius_all(8)
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 6
	bg.content_margin_bottom = 6
	_explain.add_theme_stylebox_override("normal", bg)
	add_child(_explain)


func setup(sim: Simulation) -> void:
	_sim = sim


func _process(delta: float) -> void:
	if _explain_left > 0.0:
		_explain_left -= delta
		if _explain_left <= 0.0:
			_explain.visible = false


func _show_explain(i: int) -> void:
	_explain.text = _explain_texts[i]
	_explain.visible = true
	_explain_left = EXPLAIN_SEC


# Each modifier: [icon kind, short text, tint, explanation].
func current_modifiers() -> Array[Array]:
	var out: Array[Array] = []
	if _sim == null:
		return out
	var st: GameState = _sim.state
	var me: Player = st.get_player(_sim.local_player_id)
	if me == null or not me.is_alive or st.phase != Balance.PHASE_MATCH:
		return out
	var now: float = st.match_time
	if _sim.is_underdog(me):
		out.append([IconView.Kind.UP, "+%d%%" % int(Balance.UNDERDOG_GROWTH_BONUS * 100.0), UIStyle.COLOR_GOOD,
			"Underdog: your land is under half the average of players still alive. Troop growth +%d%%, free land and Ruins cost %d%% less." % [
				int(Balance.UNDERDOG_GROWTH_BONUS * 100.0), int(Balance.UNDERDOG_CLAIM_DISCOUNT * 100.0)]])
	var gems: float = FairPlayOps.gem_bonus(me)
	if gems > 0.0:
		out.append([IconView.Kind.GEM, "+%d%%" % int(round(gems * 100.0)), UIStyle.COLOR_GOOD,
			"Gem fields: +%.1f%% troop growth per gem tile you own (max +%d%%). You have %d." % [
				Balance.GEM_GROWTH_BONUS_PER_TILE * 100.0, int(Balance.GEM_GROWTH_BONUS_MAX * 100.0), me.gem_tiles]])
	var upkeep: float = _sim.empire_upkeep(me)
	if upkeep < 0.0:
		out.append([IconView.Kind.DOWN, "%d%%" % int(round(upkeep * 100.0)), UIStyle.COLOR_BAD,
			"Empire upkeep: you own over %d%% of the map, so troop growth is %d%% (%d%% over %d%%)." % [
				int(Balance.EMPIRE_UPKEEP_LAND_THRESHOLD_1 * 100.0), int(Balance.EMPIRE_UPKEEP_PENALTY_1 * 100.0),
				int(Balance.EMPIRE_UPKEEP_PENALTY_2 * 100.0), int(Balance.EMPIRE_UPKEEP_LAND_THRESHOLD_2 * 100.0)]])
	var rising: int = _sim.rising_empire_id()
	if rising == me.id:
		out.append([IconView.Kind.STAR, "You", UIStyle.COLOR_BAD,
			"You are the Rising Empire (over %d%% of the map): everyone's attacks on you cost %d%% less, and bots target you." % [
				int(Balance.RISING_EMPIRE_LAND_THRESHOLD * 100.0), int(Balance.RISING_EMPIRE_ATTACK_DISCOUNT * 100.0)]])
	elif rising > 0:
		var rp: Player = st.get_player(rising)
		out.append([IconView.Kind.STAR, "-%d%%" % int(Balance.RISING_EMPIRE_ATTACK_DISCOUNT * 100.0), UIStyle.COLOR_GOOD,
			"%s is the Rising Empire: your attacks on them cost %d%% less per tile." % [
				rp.display_name if rp != null else "Someone", int(Balance.RISING_EMPIRE_ATTACK_DISCOUNT * 100.0)]])
	if TrucesOps.is_oathbreaker(me, now):
		out.append([IconView.Kind.BROKEN, "+%d%% %ds" % [int(Balance.OATHBREAKER_ATTACK_PENALTY * 100.0), int(ceilf(me.oathbreaker_until - now))], UIStyle.COLOR_BAD,
			"Oathbreaker: you broke a truce. Your attacks cost %d%% more for %d more seconds, and bots refuse your truces for the rest of the match." % [
				int(Balance.OATHBREAKER_ATTACK_PENALTY * 100.0), int(ceilf(me.oathbreaker_until - now))]])
	elif me.oathbroken:
		out.append([IconView.Kind.BROKEN, "No truces", UIStyle.COLOR_DIM,
			"You broke a truce earlier, so bots refuse your truces for the rest of this match."])
	return out


func update_view() -> void:
	var mods: Array[Array] = current_modifiers()
	# Hide the explanation once its badge is gone.
	if _explain.visible:
		var still_there: bool = false
		for m: Array in mods:
			still_there = still_there or str(m[3]).left(12) == _explain.text.left(12)
		if not still_there:
			_explain.visible = false
	for i in range(MAX_BADGES):
		var b: Button = _badges[i]
		if i >= mods.size():
			b.visible = false
			continue
		var m: Array = mods[i]
		b.visible = true
		_icons[i].kind = m[0]
		_icons[i].tint = m[2]
		_labels[i].text = m[1]
		_labels[i].add_theme_color_override("font_color", m[2])
		_explain_texts[i] = m[3]
		b.tooltip_text = m[3]
		b.custom_minimum_size.x = 26 + 16 + _labels[i].get_minimum_size().x
