class_name Deck
extends RefCounted
## A deck list: card id -> number of copies. Basic lands are unlimited and free.

const MIN_SIZE := 40
const MAX_SIZE := 60
const COPY_LIMITS := { "common": 4, "uncommon": 4, "rare": 2, "ultra": 1, "secret": 1 }

var name: String = "New Deck"
var cards: Dictionary = {}


static func copy_limit(id: String) -> int:
	var c: CardDef = CardDB.get_card(id)
	if c == null:
		return 0
	if c.is_basic():
		return 99
	return COPY_LIMITS.get(c.rarity, 4)


static func from_dict(d: Dictionary) -> Deck:
	var dk := Deck.new()
	dk.name = d.get("name", "Deck")
	for id in d.get("cards", {}):
		dk.cards[id] = int(d["cards"][id])
	return dk


func to_dict() -> Dictionary:
	return { "name": name, "cards": cards.duplicate() }


func size() -> int:
	var n := 0
	for id in cards:
		n += cards[id]
	return n


func add(id: String, n: int = 1) -> void:
	cards[id] = cards.get(id, 0) + n


func remove(id: String, n: int = 1) -> void:
	if not cards.has(id):
		return
	cards[id] -= n
	if cards[id] <= 0:
		cards.erase(id)


func land_count() -> int:
	var n := 0
	for id in cards:
		if CardDB.get_card(id).is_land():
			n += cards[id]
	return n


func colors() -> Array:
	var out: Array = []
	for id in cards:
		for col in CardDB.get_card(id).colors:
			if not out.has(col):
				out.append(col)
	return out


## Returns a list of human-readable problems. Empty means the deck is legal.
## Pass a Collection to also check the player actually owns the cards.
func validate(owned: Collection = null) -> Array:
	var errors: Array = []
	var n := size()
	if n < MIN_SIZE:
		errors.append("Needs at least %d cards (has %d)." % [MIN_SIZE, n])
	if n > MAX_SIZE:
		errors.append("No more than %d cards (has %d)." % [MAX_SIZE, n])
	for id in cards:
		var c: CardDef = CardDB.get_card(id)
		if c == null:
			errors.append("Unknown card: " + id)
			continue
		var lim := copy_limit(id)
		if cards[id] > lim:
			errors.append("%s: max %d copies (%s)." % [c.name, lim, CardDef.RARITY_NAMES[c.rarity]])
		if owned != null and not c.is_basic() and cards[id] > owned.count(id):
			errors.append("%s: you only own %d." % [c.name, owned.count(id)])
	return errors


## Flat list of card ids, one entry per copy, for shuffling into a library.
func to_list() -> Array:
	var out: Array = []
	for id in cards:
		for i in cards[id]:
			out.append(id)
	return out
