class_name Palette
extends RefCounted

# Player colours as shown on screen: the normal set, or the colour-blind set
# when that setting is on. Presentation only (the sim never needs colours).
# Your chosen territory colour (Customize) replaces yours; a bot whose colour
# is too close to it gets a spare colour instead. The colour-blind palette
# always wins over a custom colour.

const CLASH_DISTANCE: float = 0.45

static var _custom: Variant = null          # Color or null
static var _local_id: int = 1
static var _swaps: Dictionary = {}          # player id -> Color


# Called at the start of each match.
static func configure(local_id: int, custom: Variant, player_count: int) -> void:
	_local_id = local_id
	_custom = custom
	_swaps.clear()
	if custom == null:
		return
	var used: Array[Color] = [custom as Color]
	var spares: Array[Color] = [Balance.PLAYER_COLORS[local_id]]
	for c: Color in Progression.COLORS:
		spares.append(c)
	for id in range(1, player_count + 1):
		if id == local_id:
			continue
		var c: Color = Balance.PLAYER_COLORS[id]
		if _distance(c, custom as Color) >= CLASH_DISTANCE:
			used.append(c)
			continue
		for s: Color in spares:
			var free: bool = true
			for u: Color in used:
				free = free and _distance(s, u) >= CLASH_DISTANCE
			for other in range(id + 1, player_count + 1):
				free = free and _distance(s, Balance.PLAYER_COLORS[other]) >= CLASH_DISTANCE * 0.6
			if free:
				_swaps[id] = s
				used.append(s)
				break


static func player(id: int) -> Color:
	if Settings.colorblind:
		var cb: PackedColorArray = Balance.PLAYER_COLORS_COLORBLIND
		return cb[id] if id > 0 and id < cb.size() else Color.BLACK
	if id == _local_id and _custom != null:
		return _custom
	if _swaps.has(id):
		return _swaps[id]
	var colors: PackedColorArray = Balance.PLAYER_COLORS
	if id <= 0 or id >= colors.size():
		return Color.BLACK
	return colors[id]


# How much terrain shows through owned land (less in colour-blind mode, so
# owner colours stay distinct).
static func owner_tint() -> float:
	return Balance.OWNER_TERRAIN_TINT_COLORBLIND if Settings.colorblind else Balance.OWNER_TERRAIN_TINT


static func _distance(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
