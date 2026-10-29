class_name CardDef
extends RefCounted
## Immutable definition of a card, loaded from set JSON. One instance per card id.

const COLORS := ["ember", "tide", "grove", "sun", "moon"]
const COLOR_LETTERS := { "E": "ember", "T": "tide", "G": "grove", "S": "sun", "M": "moon" }
const COLOR_NAMES := { "ember": "Ember", "tide": "Tide", "grove": "Grove", "sun": "Sun", "moon": "Moon" }
const RARITIES := ["common", "uncommon", "rare", "ultra", "secret"]
const RARITY_NAMES := { "common": "Common", "uncommon": "Uncommon", "rare": "Rare", "ultra": "Ultra Rare", "secret": "Secret Rare", "basic": "Basic" }
const KEYWORD_NAMES := {
	"flying": "Flying", "reach": "Reach", "haste": "Haste", "lifelink": "Lifelink",
	"deathtouch": "Deathtouch", "trample": "Trample", "vigilance": "Vigilance",
	"defender": "Defender", "first_strike": "First Strike",
}

var id: String
var set_id: String
var name: String
var type: String            # "creature", "spell", "land"
var subtype: String = ""
var speed: String = "sorcery"  # spells only: "instant" or "sorcery"
var cost_generic: int = 0
var cost_colors: Dictionary = {}  # color -> count
var cost_string: String = ""
var colors: Array = []
var power: int = 0
var toughness: int = 0
var keywords: Array = []
var effects: Array = []
var rarity: String = "common"
var flavor: String = ""
var text: String = ""
var produces: String = ""   # lands: color of mana produced
var collector_number: int = 0
var is_token: bool = false


static func from_dict(d: Dictionary, p_set_id: String) -> CardDef:
	var c := CardDef.new()
	c.id = d.get("id", "")
	c.set_id = p_set_id
	c.name = d.get("name", c.id)
	c.type = d.get("type", "creature")
	c.subtype = d.get("subtype", "")
	c.speed = d.get("speed", "sorcery")
	c.power = int(d.get("power", 0))
	c.toughness = int(d.get("toughness", 0))
	c.keywords = d.get("keywords", []).duplicate()
	c.effects = d.get("effects", []).duplicate(true)
	c.rarity = d.get("rarity", "common")
	c.flavor = d.get("flavor", "")
	c.produces = d.get("produces", "")
	c.is_token = d.get("is_token", false)
	c.set_cost(d.get("cost", ""))
	if d.has("colors"):
		c.colors = d["colors"].duplicate()
	c.text = d.get("text", "")
	if c.text == "":
		c.text = c.generate_text()
	return c


func set_cost(s: String) -> void:
	cost_string = s
	cost_generic = 0
	cost_colors = {}
	colors = []
	var digits := ""
	for ch in s:
		if ch >= "0" and ch <= "9":
			digits += ch
		elif COLOR_LETTERS.has(ch):
			var col: String = COLOR_LETTERS[ch]
			cost_colors[col] = cost_colors.get(col, 0) + 1
			if not colors.has(col):
				colors.append(col)
	if digits != "":
		cost_generic = int(digits)


func mana_value() -> int:
	var total := cost_generic
	for col in cost_colors:
		total += cost_colors[col]
	return total


func is_creature() -> bool:
	return type == "creature"


func is_land() -> bool:
	return type == "land"


func is_spell() -> bool:
	return type == "spell"


func is_instant() -> bool:
	return type == "spell" and speed == "instant"


func is_basic() -> bool:
	return rarity == "basic"


func has_keyword(k: String) -> bool:
	return keywords.has(k)


func main_color() -> String:
	if colors.size() == 1:
		return colors[0]
	if colors.size() > 1:
		return "multi"
	if is_land():
		return produces
	return "colorless"


func type_line() -> String:
	var t := ""
	match type:
		"creature": t = "Creature"
		"land": t = "Basic Land" if is_basic() else "Land"
		"spell": t = "Instant" if speed == "instant" else "Sorcery"
	if is_token:
		t = "Token " + t
	if subtype != "":
		t += " - " + subtype
	return t


## The one effect (if any) that needs the player to pick a target.
func targeted_effect() -> Dictionary:
	for e in effects:
		var tgt: String = e.get("target", "")
		if tgt in ["any", "creature", "enemy_creature", "own_creature"]:
			return e
	return {}


func needs_target() -> bool:
	return not targeted_effect().is_empty()


func generate_text() -> String:
	var lines: PackedStringArray = []
	if is_land():
		return "Tap: add one %s mana." % COLOR_NAMES.get(produces, produces)
	if not keywords.is_empty():
		var kw: PackedStringArray = []
		for k in keywords:
			kw.append(KEYWORD_NAMES.get(k, k.capitalize()))
		lines.append(", ".join(kw))
	var cast_parts: PackedStringArray = []
	for e in effects:
		var trig: String = e.get("on", "cast")
		var body := describe_effect(e)
		match trig:
			"cast":
				cast_parts.append(body)
			"etb":
				lines.append("When this enters, " + body.substr(0, 1).to_lower() + body.substr(1))
			"attack":
				lines.append("Whenever this attacks, " + body.substr(0, 1).to_lower() + body.substr(1))
			"dies":
				lines.append("When this dies, " + body.substr(0, 1).to_lower() + body.substr(1))
	if not cast_parts.is_empty():
		lines.append(" ".join(cast_parts))
	return "\n".join(lines)


static func target_phrase(t: String) -> String:
	match t:
		"any": return "any target"
		"creature": return "target creature"
		"enemy_creature": return "target enemy creature"
		"own_creature": return "target creature you control"
		"this": return "this creature"
		"all_enemy_creatures": return "each enemy creature"
		"all_creatures": return "each creature"
		"enemy_player": return "your opponent"
	return t


func describe_effect(e: Dictionary) -> String:
	var tgt: String = e.get("target", "")
	var amt: int = int(e.get("amount", 0))
	match e.get("op", ""):
		"damage":
			return "Deal %d damage to %s." % [amt, target_phrase(tgt)]
		"heal":
			return "You gain %d life." % amt
		"draw":
			return "Draw a card." if amt == 1 else "Draw %d cards." % amt
		"lose_life":
			return "You lose %d life." % amt
		"drain":
			return "Your opponent loses %d life and you gain %d life." % [amt, amt]
		"discard":
			return "Your opponent discards a card at random."
		"bounce":
			return "Return %s to its owner's hand." % target_phrase(tgt)
		"tap":
			return "Tap %s." % target_phrase(tgt)
		"destroy":
			var s := "Destroy %s" % target_phrase(tgt)
			if e.has("min_power"):
				s += " with power %d or greater" % int(e["min_power"])
			return s + "."
		"pump":
			var p := int(e.get("power", 0))
			var t := int(e.get("toughness", 0))
			var who := target_phrase(tgt)
			who = who.substr(0, 1).to_upper() + who.substr(1)
			return "%s gets %s/%s until end of turn." % [who, _signed(p), _signed(t)]
		"grant":
			var kw: String = KEYWORD_NAMES.get(e.get("keyword", ""), e.get("keyword", ""))
			return "It gains %s until end of turn." % kw.to_lower()
		"buff_all":
			var p2 := int(e.get("power", 0))
			var t2 := int(e.get("toughness", 0))
			var who2 := "Your other creatures" if e.get("others", false) else "Creatures you control"
			if e.get("permanent", false):
				return "Put a +%d/+%d counter on each creature you control." % [p2, t2]
			return "%s get %s/%s until end of turn." % [who2, _signed(p2), _signed(t2)]
		"token":
			var tk: Dictionary = e.get("token", {})
			var cnt := int(e.get("count", 1))
			var noun := "%d/%d %s" % [int(tk.get("power", 1)), int(tk.get("toughness", 1)), tk.get("name", "Token")]
			if cnt == 1:
				return "Create a %s token." % noun
			return "Create %s %s tokens." % [_number_word(cnt), noun]
		"ramp":
			return "Put a basic land of your choice onto the battlefield tapped."
	return ""


static func _signed(n: int) -> String:
	return ("+%d" % n) if n >= 0 else str(n)


static func _number_word(n: int) -> String:
	var words := ["zero", "one", "two", "three", "four", "five"]
	return words[n] if n < words.size() else str(n)
