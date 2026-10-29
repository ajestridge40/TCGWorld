extends Node
## Loads all static game data (card sets, products, NPCs, maps) from res://data.
## New sets are picked up automatically: drop a JSON file into data/sets/.

const SETS_DIR := "res://data/sets/"

var cards: Dictionary = {}       # id -> CardDef
var sets: Dictionary = {}        # set_id -> { id, name, code, pack, card_ids, ... }
var set_order: Array = []
var products: Dictionary = {}    # raw products.json
var npcs: Dictionary = {}        # id -> npc dict
var npc_order: Array = []
var starters: Array = []
var achievements: Dictionary = {}
var maps: Dictionary = {}


func _ready() -> void:
	load_all()


func load_all() -> void:
	cards.clear()
	sets.clear()
	set_order.clear()
	_make_special_cards()
	var dir := DirAccess.open(SETS_DIR)
	if dir:
		var files := Array(dir.get_files())
		files.sort()
		for f in files:
			# Exported builds may list "x.json.remap"-style names; only load plain json.
			if f.ends_with(".json"):
				_load_set(SETS_DIR + f)
	products = _read_json("res://data/products.json")
	for n in _read_json("res://data/npcs.json").get("npcs", []):
		npcs[n["id"]] = n
		npc_order.append(n["id"])
	starters = _read_json("res://data/starters.json").get("starters", [])
	achievements = _read_json("res://data/achievements.json")
	for m in ["town", "shop", "home"]:
		maps[m] = _read_json("res://data/maps/%s.json" % m)


## Cards that exist outside of sets (given by the rules, never in packs).
func _make_special_cards() -> void:
	var penny := CardDef.from_dict({
		"id": "lucky_penny", "name": "Lucky Penny", "type": "spell", "cost": 0, "rarity": "token",
		"effects": [ { "on": "cast", "op": "spark", "amount": 1 } ],
		"flavor": "The player going second gets one. It's only fair.",
	}, "special")
	penny.is_token = true
	cards[penny.id] = penny


func _load_set(path: String) -> void:
	var data := _read_json(path)
	if data.is_empty():
		return
	var set_id: String = data["id"]
	var ids: Array = []
	var n := 0
	for cd in data.get("cards", []):
		var c := CardDef.from_dict(cd, set_id)
		n += 1
		c.collector_number = n
		cards[c.id] = c
		ids.append(c.id)
	var info := data.duplicate()
	info.erase("cards")
	info["card_ids"] = ids
	sets[set_id] = info
	set_order.append(set_id)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing data file: " + path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(txt)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		push_error("Bad JSON in " + path)
		return {}
	return parsed


func get_card(id: String) -> CardDef:
	return cards.get(id)


func set_card_ids(set_id: String) -> Array:
	return sets.get(set_id, {}).get("card_ids", [])


func cards_of_rarity(set_id: String, rarity: String) -> Array:
	var out: Array = []
	for id in set_card_ids(set_id):
		if cards[id].rarity == rarity:
			out.append(id)
	return out


## Sets that are on shelves by the given day (sets release over time).
func released_sets(day: int) -> Array:
	return set_order.filter(func(sid): return int(sets[sid].get("release_day", 0)) <= day)


func is_released(set_id: String, day: int) -> bool:
	return int(sets.get(set_id, {}).get("release_day", 0)) <= day


func product(id: String) -> Dictionary:
	for p in products.get("products", []):
		if p["id"] == id:
			return p
	return {}


func sell_price(card_id: String, foil: bool = false) -> int:
	var c := get_card(card_id)
	if c == null or c.is_token:
		return 0
	var base: int = int(products.get("sell_prices", {}).get(c.rarity, 1))
	return base * (int(products.get("foil_multiplier", 3)) if foil else 1)


func single_price(card_id: String, foil: bool = false) -> int:
	var c := get_card(card_id)
	if c == null:
		return 0
	var base: int = int(products.get("single_prices", {}).get(c.rarity, 5))
	return base * (int(products.get("foil_multiplier", 3)) if foil else 1)


func npc(id: String) -> Dictionary:
	return npcs.get(id, {})
