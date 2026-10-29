class_name PackGenerator
extends RefCounted
## Builds booster packs from the slot rules declared in each set's JSON.
## A pulled card is a Dictionary: { "id": String, "foil": bool }.
## Packs come back sorted so the best card is revealed last.


static func open_pack(set_id: String, rng: RandomNumberGenerator, variant: String = "") -> Array:
	var set_info: Dictionary = CardDB.sets.get(set_id, {})
	if set_info.is_empty():
		push_error("Unknown set " + set_id)
		return []
	var rules: Dictionary = set_info.get("pack", {})
	if variant == "collector":
		rules = CardDB.products.get("collector_pack", rules)
	var pulled: Array = []
	var taken := {}
	for slot in rules.get("slots", []):
		for i in int(slot.get("count", 1)):
			var rarity: String = slot.get("rarity", "")
			if rarity == "":
				rarity = weighted_pick(slot.get("weights", {}), rng)
			var id := _pick_card(set_id, rarity, taken, rng)
			if id == "":
				continue
			taken[id] = true
			pulled.append({ "id": id, "foil": bool(slot.get("foil", false)) })
	# Foil slot: replaces one common with a foil of any rarity.
	if variant == "" and rng.randf() < float(rules.get("foil_chance", 0.0)):
		var idx := -1
		for i in pulled.size():
			if CardDB.get_card(pulled[i]["id"]).rarity == "common":
				idx = i
		if idx >= 0:
			var frar := weighted_pick(rules.get("foil_weights", { "common": 1 }), rng)
			var fid := _pick_card(set_id, frar, {}, rng)
			if fid != "":
				pulled[idx] = { "id": fid, "foil": true }
	pulled.sort_custom(func(a, b): return reveal_score(a) < reveal_score(b))
	return pulled


static func reveal_score(entry: Dictionary) -> int:
	var c: CardDef = CardDB.get_card(entry["id"])
	var r := CardDef.RARITIES.find(c.rarity) * 10
	return r + (5 if entry.get("foil", false) else 0)


static func weighted_pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := rng.randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return k
	return weights.keys().back()


static func _pick_card(set_id: String, rarity: String, exclude: Dictionary, rng: RandomNumberGenerator) -> String:
	var pool := CardDB.cards_of_rarity(set_id, rarity)
	var fresh := pool.filter(func(id): return not exclude.has(id))
	if fresh.is_empty():
		fresh = pool
	if fresh.is_empty():
		return ""
	return fresh[rng.randi_range(0, fresh.size() - 1)]
