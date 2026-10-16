class_name Cosmetics
extends RefCounted

# Every look a player can unlock: territory colours, patterns, Crown icons,
# titles and victory effects. Looks never change the rules.
# The unlock schedule by level lives here too, so the catalogue is in one place.

const CAT_COLOR: String = "color"
const CAT_PATTERN: String = "pattern"
const CAT_CROWN: String = "crown"
const CAT_TITLE: String = "title"
const CAT_VICTORY: String = "victory"
const CATEGORIES: Array[String] = [CAT_COLOR, CAT_PATTERN, CAT_CROWN, CAT_TITLE, CAT_VICTORY]

const COLOR_NAMES: Array[String] = [
	"Royal Blue", "Crimson", "Emerald", "Gold", "Amethyst", "Ember", "Teal", "Rose",
	"Moss", "Bronze", "Snow", "Slate", "Midnight", "Coral", "Jade", "Obsidian",
]
static var COLORS: PackedColorArray = PackedColorArray([
	Color(0.25, 0.55, 1.00), Color(0.86, 0.16, 0.24), Color(0.18, 0.70, 0.40), Color(1.00, 0.78, 0.15),
	Color(0.62, 0.36, 0.92), Color(1.00, 0.45, 0.12), Color(0.12, 0.66, 0.66), Color(1.00, 0.52, 0.66),
	Color(0.45, 0.58, 0.22), Color(0.72, 0.48, 0.24), Color(0.94, 0.95, 1.00), Color(0.42, 0.48, 0.58),
	Color(0.14, 0.18, 0.46), Color(1.00, 0.50, 0.42), Color(0.30, 0.86, 0.64), Color(0.16, 0.14, 0.18),
])
const PATTERN_NAMES: Array[String] = ["Plain", "Stripes", "Dots", "Checks", "Waves", "Scales", "Bricks"]
const CROWN_NAMES: Array[String] = ["Crown", "Star", "Shield", "Tower", "Flame", "Gem", "Laurel", "High Crown"]
const TITLE_NAMES: Array[String] = [
	"", "Squire", "Knight", "Baron", "Warlord", "Emperor", "Legend",
	"Kingslayer", "Spymaster", "Underdog", "Island King", "Conqueror", "Graduate",
]
const VICTORY_NAMES: Array[String] = ["None", "Fireworks", "Confetti", "Golden Rain"]

# Level -> unlocks gained on reaching it ([category, index] pairs).
const LEVEL_UNLOCKS: Dictionary = {
	1: [["color", 0], ["color", 1], ["color", 2], ["color", 3], ["pattern", 0], ["crown", 0], ["title", 0], ["victory", 0]],
	2: [["color", 4], ["title", 1]],
	3: [["pattern", 1]],
	4: [["crown", 1]],
	5: [["color", 5], ["title", 2]],
	6: [["pattern", 2]],
	7: [["victory", 1]],
	8: [["color", 6]],
	9: [["crown", 2]],
	10: [["pattern", 3], ["title", 3]],
	11: [["color", 7]],
	12: [["crown", 3]],
	13: [["pattern", 4]],
	14: [["color", 8]],
	15: [["victory", 2], ["title", 4]],
	16: [["crown", 4]],
	17: [["color", 9]],
	18: [["pattern", 5]],
	19: [["color", 10]],
	20: [["crown", 5], ["title", 5]],
	21: [["color", 11]],
	22: [["pattern", 6]],
	23: [["color", 12]],
	24: [["crown", 6]],
	25: [["victory", 3], ["title", 6]],
	26: [["color", 13]],
	27: [["crown", 7]],
	28: [["color", 14]],
	30: [["color", 15]],
}


static func names_for(cat: String) -> Array[String]:
	match cat:
		CAT_COLOR:
			return COLOR_NAMES
		CAT_PATTERN:
			return PATTERN_NAMES
		CAT_CROWN:
			return CROWN_NAMES
		CAT_TITLE:
			return TITLE_NAMES
		_:
			return VICTORY_NAMES


static func label(cat: String, idx: int) -> String:
	var names: Array[String] = names_for(cat)
	if idx < 0 or idx >= names.size():
		return "?"
	var n: String = names[idx]
	if cat == CAT_TITLE and n == "":
		return "No title"
	return n


static func category_label(cat: String) -> String:
	return {CAT_COLOR: "Colour", CAT_PATTERN: "Pattern", CAT_CROWN: "Crown",
		CAT_TITLE: "Title", CAT_VICTORY: "Victory"}.get(cat, cat)


# Level at which an item unlocks, or -1 if it comes from an achievement.
static func unlock_level(cat: String, idx: int) -> int:
	for lvl: int in LEVEL_UNLOCKS.keys():
		for pair: Array in LEVEL_UNLOCKS[lvl]:
			if pair[0] == cat and int(pair[1]) == idx:
				return lvl
	return -1


# Keeps only known keys with in-range values, so a look from another phone
# can't break anything.
static func sanitize(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(v) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = v
	for cat in CATEGORIES:
		if d.has(cat) and (typeof(d[cat]) == TYPE_INT or typeof(d[cat]) == TYPE_FLOAT):
			out[cat] = clampi(int(d[cat]), 0, names_for(cat).size() - 1)
	return out
