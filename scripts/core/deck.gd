class_name Deck
extends RefCounted
## A Sparkfolk deck list: card id -> number of copies.
## Rules: exactly 30 cards, at most two colors (colorless fits anywhere),
## and copy limits by rarity.

const SIZE := 30
const MAX_COLORS := 2
const COPY_LIMITS := { "common": 3, "uncommon": 3, "rare": 2, "ultra": 1, "secret": 1 }

var name: String = "New Deck"
var cards: Dictionary = {}


static func copy_limit(id: String) -> int:
	var c: CardDef = CardDB.get_card(id)
	if c == null or c.is_token:
		return 0
	return COPY_LIMITS.get(c.rarity, 3)


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


func colors() -> Array:
	var out: Array = []
	for id in cards:
		var col: String = CardDB.get_card(id).color
		if col != "colorless" and not out.has(col):
			out.append(col)
	return out


## Would adding this card break the two-color rule?
func color_allows(id: String) -> bool:
	var col: String = CardDB.get_card(id).color
	var cols := colors()
	return col == "colorless" or cols.has(col) or cols.size() < MAX_COLORS


## Returns a list of human-readable problems. Empty means the deck is legal.
## Pass a Collection to also check the player actually owns the cards.
func validate(owned: Collection = null) -> Array:
	var errors: Array = []
	var n := size()
	if n != SIZE:
		errors.append("Needs exactly %d cards (has %d)." % [SIZE, n])
	var cols := colors()
	if cols.size() > MAX_COLORS:
		errors.append("Too many colors (%d). Use at most %d plus colorless." % [cols.size(), MAX_COLORS])
	for id in cards:
		var c: CardDef = CardDB.get_card(id)
		if c == null:
			errors.append("Unknown card: " + id)
			continue
		var lim := copy_limit(id)
		if cards[id] > lim:
			errors.append("%s: max %d copies (%s)." % [c.name, lim, CardDef.RARITY_NAMES[c.rarity]])
		if owned != null and cards[id] > owned.count(id):
			errors.append("%s: you only own %d." % [c.name, owned.count(id)])
	return errors


## Flat list of card ids, one entry per copy, for shuffling into a library.
func to_list() -> Array:
	var out: Array = []
	for id in cards:
		for i in cards[id]:
			out.append(id)
	return out


## Spark curve: counts of cards by cost, bucketed 0..7+.
func curve() -> Array:
	var b := [0, 0, 0, 0, 0, 0, 0, 0]
	for id in cards:
		b[mini(7, CardDB.get_card(id).cost)] += cards[id]
	return b
