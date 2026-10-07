class_name Shrine
extends RefCounted

# A contested map objective. Whoever owns the centre tile gets the Shrine's
# blessing. The surrounding 3x3 sanctum is holy ground with extra defense.

var kind: int = Balance.SHRINE_PLENTY
var x: int = 0
var y: int = 0
var tile_idx: int = 0
var holder_id: int = 0          # cached owner of the centre tile (0 = nobody)


static func kind_label(k: int) -> String:
	match k:
		Balance.SHRINE_PLENTY:
			return "Shrine of Plenty"
		Balance.SHRINE_WAR:
			return "Shrine of War"
		Balance.SHRINE_SIGHT:
			return "Shrine of Sight"
		_:
			return "Shrine"


static func kind_effect(k: int) -> String:
	match k:
		Balance.SHRINE_PLENTY:
			return "+%d%% troop growth" % int(Balance.SHRINE_PLENTY_GROWTH_BONUS * 100.0)
		Balance.SHRINE_WAR:
			return "attacks cost %d%% less" % int(Balance.SHRINE_WAR_ATTACK_DISCOUNT * 100.0)
		Balance.SHRINE_SIGHT:
			return "see every rival's troops (as a range)"
		_:
			return ""
