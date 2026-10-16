class_name BotNames
extends RefCounted

# Fantasy names for bots: a title and a name, like "Duke Ashford".

const TITLES: Array[String] = [
	"Duke", "Duchess", "Lord", "Lady", "Baron", "Baroness",
	"King", "Queen", "Count", "Countess", "Earl", "Princess",
]
const NAMES: Array[String] = [
	"Ashford", "Vex", "Thorne", "Blackwood", "Ravenhill",
	"Stormhold", "Grimm", "Darkmere", "Fenwick", "Fairfax",
	"Crow", "Vane", "Wulf", "Ironside", "Shade", "Starling",
	"Marrow", "Hollow", "Rook", "Hale", "Drake", "Ember",
]


static func generate(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [TITLES[rng.randi() % TITLES.size()], NAMES[rng.randi() % NAMES.size()]]
