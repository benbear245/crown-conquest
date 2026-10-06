class_name DailyScreen
extends MenuScreen

# Daily Challenge: today's fixed map and settings, the score rule and your best.

var _info: Label
var _best: Label


func _init(menu_root: MenuRoot) -> void:
	super(menu_root, "Daily Challenge")
	_info = MenuScreen.text_block("", 1000, 24)
	add_child(_info)
	add_child(MenuScreen.text_block("Everyone gets the same map today. Score = your peak land % + a time bonus " +
		"if you win (up to %d, more the faster you win). Play as often as you like; your best counts." % int(Balance.DAILY_TIME_BONUS_MAX),
		1000, 20, UIStyle.COLOR_DIM))
	_best = MenuScreen.text_block("", 1000, 26, UIStyle.COLOR_WARN)
	add_child(_best)
	add_child(back_and_action_row("Play today's map", func() -> void: Session.play(today())))


static func today() -> MatchConfig:
	return MatchConfig.daily(Time.get_date_dict_from_system())


func refresh() -> void:
	var cfg: MatchConfig = today()
	_info.text = "%s\n%s" % [cfg.daily_date, cfg.describe()]
	var best: int = SaveData.daily_best(cfg.daily_date)
	var lines: Array[String] = []
	lines.append("Best today: %s" % (str(best) if best >= 0 else "not played yet"))
	var ever: int = SaveData.daily_best_ever()
	lines.append("Best ever: %s" % (str(ever) if int(SaveData.data.daily.played) > 0 else "—"))
	_best.text = "\n".join(lines)
