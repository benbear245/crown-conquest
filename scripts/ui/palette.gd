class_name Palette
extends RefCounted

# Player colours as shown on screen: the normal set, or the colour-blind set
# when that setting is on. Presentation only (the sim never needs colours).


static func player(id: int) -> Color:
	var colors: PackedColorArray = Balance.PLAYER_COLORS_COLORBLIND if Settings.colorblind else Balance.PLAYER_COLORS
	if id <= 0 or id >= colors.size():
		return Color.BLACK
	return colors[id]


# How much terrain shows through owned land (less in colour-blind mode, so
# owner colours stay distinct).
static func owner_tint() -> float:
	return Balance.OWNER_TERRAIN_TINT_COLORBLIND if Settings.colorblind else Balance.OWNER_TERRAIN_TINT
