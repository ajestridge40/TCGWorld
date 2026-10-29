class_name CardBalance
extends RefCounted
## A simple "stat budget" model used to keep every card in line with its cost.
##
##   creature budget = 2 * cost + 1       (1 -> 3 stats, e.g. 2/1; 3 -> 7, e.g. 3/4)
##   spell budget    = 1.25 * cost + 1.5
##   + a small rarity allowance, so chase cards are a little better, never broken.
##
## A card's value is its stats plus the value of its keywords and effects.
## The test suite fails if any card's value drifts more than TOLERANCE from its
## budget, so new sets can't quietly power-creep. Tune the weights here, in one place.

const TOLERANCE := 1.25
const RARITY_ALLOWANCE := { "common": 0.0, "uncommon": 0.5, "rare": 1.0, "ultra": 1.5, "secret": 2.0, "token": 0.0 }

# Effects that repeat (Strike) are worth more; ones that need the card to die less.
const TRIGGER_MULT := { "enter": 1.0, "cast": 1.0, "dies": 0.75, "attack": 1.5 }


static func budget(c: CardDef) -> float:
	var base := 2.0 * c.cost + 1.0 if c.is_creature() else 1.25 * c.cost + 1.5
	return base + RARITY_ALLOWANCE.get(c.rarity, 0.0)


static func value(c: CardDef) -> float:
	var v := 0.0
	if c.is_creature():
		v += c.power + c.health
		# Wall tax: big health on low power stalls lanes for free.
		v += maxf(0.0, c.health - c.power - 2) * 0.5
		for k in c.keywords:
			v += keyword_value(k, c.power)
		# Evasion + protection compound: hard to block AND hard to remove.
		if c.has_keyword("soar") and c.has_keyword("shield"):
			v += 1.0
	for e in c.effects:
		v += effect_value(e) * TRIGGER_MULT.get(e.get("on", "cast"), 1.0)
	return v


static func deviation(c: CardDef) -> float:
	return value(c) - budget(c)


static func keyword_value(k: String, power: int) -> float:
	match k:
		"swift": return 1.0
		"soar": return 1.5 + 0.5 * power   # evasion is very strong in lanes
		"shield": return 2.5   # absorbs a whole hit while still striking back
		"reach": return 0.5
		"sweep": return 1.0 + 0.5 * power
		"move": return 0.75
	return 0.0


static func effect_value(e: Dictionary) -> float:
	var amt := float(e.get("amount", 0))
	var stats := float(e.get("power", 0)) + float(e.get("health", 0))
	var tgt: String = e.get("target", "")
	var permanent: bool = e.get("permanent", true)
	match e.get("op", ""):
		"damage":
			if tgt in ["all_enemy_creatures", "all_creatures"]:
				return 3.0 * amt
			if tgt == "enemy_player":
				return 1.0 * amt
			return 1.25 * amt
		"heal": return 1.0 * amt
		"draw": return 2.5 * amt
		"lose_life": return -0.5 * amt
		"drain": return 2.0 * amt
		"spark": return 1.0 * amt
		"buff": return stats * (0.9 if permanent else 0.6)
		"buff_all": return stats * (2.0 if permanent else 1.25)
		"grant": return keyword_value(e.get("keyword", ""), 2)
		"grant_all": return 2.0 * keyword_value(e.get("keyword", ""), 2)
		"token":
			var tk: Dictionary = e.get("token", {})
			var each := (float(tk.get("power", 1)) + float(tk.get("health", 1))) * 0.9
			for k in tk.get("keywords", []):
				each += keyword_value(k, int(tk.get("power", 1)))
			return each * int(e.get("count", 1))
		"destroy": return 6.5 if not e.has("max_power") else 3.0 + float(e["max_power"])
		"destroy_all": return 8.0
		"bounce": return 3.5
		"freeze": return 3.0 if tgt == "all_enemy_creatures" else 1.0
		"push": return 1.5
	return 0.0
