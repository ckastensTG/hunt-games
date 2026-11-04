class_name PlayerNames
extends RefCounted
## Names for online players (bible §5.2): no free text, so nothing to
## moderate. A name is {"key", "n"}: a word from a curated list plus a
## number, e.g. scribe 4821. Each device shows the word in its own language
## (the title translates the keys).

const KEYS := ["scribe", "traveller", "potter", "weaver", "shepherd", "boatman", "gardener", "builder"]


static func random(rng: RandomNumberGenerator) -> Dictionary:
	return {"key": KEYS[rng.randi_range(0, KEYS.size() - 1)], "n": rng.randi_range(1000, 9999)}


static func is_valid(name: Dictionary) -> bool:
	return KEYS.has(name.get("key", "")) and typeof(name.get("n")) == TYPE_INT and name.n >= 0 and name.n <= 99999
