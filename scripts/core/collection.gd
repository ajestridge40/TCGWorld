class_name Collection
extends RefCounted
## The player's cards. Foils and non-foils are tracked separately so they can
## be shown, traded and sold separately, but either copy counts for decks.

signal changed

var counts: Dictionary = {}  # key ("id" or "id*f") -> int


static func key(id: String, foil: bool) -> String:
	return id + ("*f" if foil else "")


static func split_key(k: String) -> Array:
	if k.ends_with("*f"):
		return [k.substr(0, k.length() - 2), true]
	return [k, false]


func add(id: String, foil: bool = false, n: int = 1) -> void:
	var k := key(id, foil)
	counts[k] = counts.get(k, 0) + n
	changed.emit()


func remove(id: String, foil: bool = false, n: int = 1) -> bool:
	var k := key(id, foil)
	if counts.get(k, 0) < n:
		return false
	counts[k] -= n
	if counts[k] <= 0:
		counts.erase(k)
	changed.emit()
	return true


func count(id: String) -> int:
	return counts.get(id, 0) + counts.get(id + "*f", 0)


func count_variant(id: String, foil: bool) -> int:
	return counts.get(key(id, foil), 0)


func has_foil(id: String) -> bool:
	return counts.get(id + "*f", 0) > 0


func owned_unique(set_id: String) -> int:
	var n := 0
	for id in CardDB.set_card_ids(set_id):
		if count(id) > 0:
			n += 1
	return n


func completion(set_id: String) -> float:
	var total := CardDB.set_card_ids(set_id).size()
	return 0.0 if total == 0 else float(owned_unique(set_id)) / total


## Copies beyond what a deck could ever use (the copy limit) - safe to sell or trade.
func extras(id: String) -> int:
	return maxi(0, count(id) - Deck.copy_limit(id))


func total_cards() -> int:
	var n := 0
	for k in counts:
		n += counts[k]
	return n


func to_dict() -> Dictionary:
	return counts.duplicate()


func load_dict(d: Dictionary) -> void:
	counts.clear()
	for k in d:
		counts[k] = int(d[k])
	changed.emit()
