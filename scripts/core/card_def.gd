class_name CardDef
extends RefCounted
## Immutable definition of a Sparkfolk card, loaded from set JSON.
## One instance per card id. See docs/GAME_RULES.md for the rules themselves.

const COLORS := ["ember", "tide", "grove", "sun", "moon"]
const COLOR_NAMES := { "ember": "Ember", "tide": "Tide", "grove": "Grove", "sun": "Sun", "moon": "Moon", "colorless": "Colorless" }
const RARITIES := ["common", "uncommon", "rare", "ultra", "secret"]
const RARITY_NAMES := { "common": "Common", "uncommon": "Uncommon", "rare": "Rare", "ultra": "Ultra Rare", "secret": "Secret Rare", "token": "Token" }
const KEYWORD_NAMES := {
	"swift": "Swift", "soar": "Soar", "shield": "Shield",
	"reach": "Reach", "sweep": "Sweep", "move": "Move",
}
const KEYWORD_REMINDERS := {
	"swift": "Can attack the turn it's played.",
	"soar": "Flies over the creature across, unless it has Soar or Reach.",
	"shield": "Ignores the first damage it would take.",
	"reach": "Can fight creatures with Soar.",
	"sweep": "When attacking, also hits enemies in the neighboring lanes.",
	"move": "Once per turn, may step into a neighboring empty lane.",
}
const TRIGGER_NAMES := { "enter": "Enter", "dies": "Last Breath", "attack": "Strike" }
const TARGETED := ["any", "creature", "enemy_creature", "own_creature"]

var id: String
var set_id: String
var name: String
var type: String = "creature"   # "creature" or "spell"
var subtype: String = ""
var cost: int = 0
var color: String = "colorless"
var power: int = 0
var health: int = 0
var keywords: Array = []
var effects: Array = []
var rarity: String = "common"
var flavor: String = ""
var text: String = ""
var collector_number: int = 0
var is_token: bool = false


static func from_dict(d: Dictionary, p_set_id: String) -> CardDef:
	var c := CardDef.new()
	c.id = d.get("id", "")
	c.set_id = p_set_id
	c.name = d.get("name", c.id)
	c.type = d.get("type", "creature")
	c.subtype = d.get("subtype", "")
	c.cost = int(d.get("cost", 0))
	c.color = d.get("color", "colorless")
	c.power = int(d.get("power", 0))
	c.health = int(d.get("health", 0))
	c.keywords = d.get("keywords", []).duplicate()
	c.effects = d.get("effects", []).duplicate(true)
	c.rarity = d.get("rarity", "common")
	c.flavor = d.get("flavor", "")
	c.is_token = d.get("is_token", false)
	c.text = d.get("text", "")
	if c.text == "":
		c.text = c.generate_text()
	return c


## A creature definition for tokens created by effects.
static func make_token(tk: Dictionary, p_color: String) -> CardDef:
	var d := tk.duplicate()
	d["id"] = "token_" + str(tk.get("name", "token")).to_lower().replace(" ", "_")
	d["type"] = "creature"
	d["rarity"] = "token"
	d["is_token"] = true
	if not d.has("color"):
		d["color"] = p_color
	return from_dict(d, "token")


func is_creature() -> bool:
	return type == "creature"


func is_spell() -> bool:
	return type == "spell"


func has_keyword(k: String) -> bool:
	return keywords.has(k)


func main_color() -> String:
	return color


func type_line() -> String:
	var t := "Creature" if is_creature() else "Spell"
	if is_token:
		t = "Token " + t
	if subtype != "":
		t += " - " + subtype
	return t


## The one effect (if any) where the player picks a target. Every chosen-target
## effect on a card uses that same target.
func targeted_effect() -> Dictionary:
	for e in effects:
		if e.get("target", "") in TARGETED:
			return e
	return {}


func needs_target() -> bool:
	return not targeted_effect().is_empty()


func generate_text() -> String:
	var lines: PackedStringArray = []
	if not keywords.is_empty():
		var kw: PackedStringArray = []
		for k in keywords:
			kw.append(KEYWORD_NAMES.get(k, k.capitalize()))
		lines.append(", ".join(kw))
	var cast_parts: PackedStringArray = []
	for e in effects:
		var trig: String = e.get("on", "cast")
		var body := describe_effect(e)
		if trig == "cast":
			cast_parts.append(body)
		else:
			lines.append("%s: %s" % [TRIGGER_NAMES.get(trig, trig.capitalize()), body])
	if not cast_parts.is_empty():
		lines.append(" ".join(cast_parts))
	return "\n".join(lines)


## Reminder text for keywords and triggers, shown on large card views.
func reminder_text() -> String:
	var out: PackedStringArray = []
	for k in keywords:
		out.append("%s: %s" % [KEYWORD_NAMES[k], KEYWORD_REMINDERS[k]])
	for e in effects:
		match e.get("on", ""):
			"dies": out.append("Last Breath: happens when this dies.")
			"attack": out.append("Strike: happens each time this attacks.")
	for e in effects:
		var kw: String = e.get("keyword", "")
		if kw != "" and KEYWORD_REMINDERS.has(kw) and not keywords.has(kw):
			out.append("%s: %s" % [KEYWORD_NAMES[kw], KEYWORD_REMINDERS[kw]])
	var unique: PackedStringArray = []
	for s in out:
		if not unique.has(s):
			unique.append(s)
	return "\n".join(unique)


static func target_phrase(t: String) -> String:
	match t:
		"any": return "any target"
		"creature": return "a creature"
		"enemy_creature": return "an enemy creature"
		"own_creature": return "a creature you control"
		"this": return "this creature"
		"all_enemy_creatures": return "each enemy creature"
		"all_creatures": return "each creature"
		"enemy_player": return "your opponent"
		"random_enemy_creature": return "a random enemy creature"
	return t


func describe_effect(e: Dictionary) -> String:
	var tgt: String = e.get("target", "")
	var amt: int = int(e.get("amount", 0))
	var p := int(e.get("power", 0))
	var h := int(e.get("health", 0))
	var until := "" if e.get("permanent", true) else " this turn"
	match e.get("op", ""):
		"damage":
			return "Deal %d damage to %s." % [amt, target_phrase(tgt)]
		"heal":
			return "You gain %d Heart." % amt
		"draw":
			return "Draw a card." if amt == 1 else "Draw %d cards." % amt
		"lose_life":
			return "You lose %d Heart." % amt
		"drain":
			return "Your opponent loses %d Heart and you gain %d." % [amt, amt]
		"spark":
			return "Gain %d Spark this turn." % amt
		"buff":
			return "Give %s %s/%s%s." % [target_phrase(tgt), _signed(p), _signed(h), until]
		"grant":
			return "Give %s %s." % [target_phrase(tgt), KEYWORD_NAMES.get(e.get("keyword", ""), "")]
		"buff_all":
			var who := "your other creatures" if e.get("others", false) else "your creatures"
			return "Give %s %s/%s%s." % [who, _signed(p), _signed(h), until]
		"grant_all":
			var who2 := "your other creatures" if e.get("others", false) else "your creatures"
			return "Give %s %s." % [who2, KEYWORD_NAMES.get(e.get("keyword", ""), "")]
		"token":
			var tk: Dictionary = e.get("token", {})
			var cnt := int(e.get("count", 1))
			var noun := "%d/%d %s" % [int(tk.get("power", 1)), int(tk.get("health", 1)), tk.get("name", "Token")]
			var kws: Array = tk.get("keywords", [])
			if not kws.is_empty():
				noun += " with " + ", ".join(kws.map(func(k): return KEYWORD_NAMES.get(k, k)))
			return ("Summon a %s." % noun) if cnt == 1 else "Summon %s %ss." % [_number_word(cnt), noun]
		"destroy":
			var s := "Destroy %s" % target_phrase(tgt)
			if e.has("max_power"):
				s += " with %d or less power" % int(e["max_power"])
			return s + "."
		"destroy_all":
			return "Destroy each creature with %d or less power." % int(e.get("max_power", 0))
		"bounce":
			return "Return %s to its owner's hand." % target_phrase(tgt)
		"freeze":
			return "Freeze %s. (It can't attack on its next turn.)" % target_phrase(tgt)
		"push":
			return "Push %s into a neighboring empty lane." % target_phrase(tgt)
	return ""


static func _signed(n: int) -> String:
	return ("+%d" % n) if n >= 0 else str(n)


static func _number_word(n: int) -> String:
	var words := ["zero", "one", "two", "three", "four", "five"]
	return words[n] if n < words.size() else str(n)
