class_name TradePopup
extends Control
## Modal showing an NPC's trade offer side by side. Emits decided(accepted).

signal decided(accepted: bool)

var _npc_name := ""
var _offer := {}


func setup(npc_name: String, offer: Dictionary) -> void:
	_npc_name = npc_name
	_offer = offer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var p := UIKit.panel()
	p.position = Vector2(230, 60)
	p.custom_minimum_size = Vector2(500, 420)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(UIKit.label("%s wants to trade!" % _npc_name, 20, UIKit.WOOD, HORIZONTAL_ALIGNMENT_CENTER))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 24)
	v.add_child(h)
	var give: CardDef = CardDB.get_card(_offer["give"])
	var want: CardDef = CardDB.get_card(_offer["want"])
	h.add_child(_side("You get", give, false, Game.collection.count(give.id) == 0))
	h.add_child(UIKit.label("⇄", 32, UIKit.WOOD))
	h.add_child(_side("You give", want, _offer["want_foil"], false))
	var left := Game.collection.count(want.id) - 1
	v.add_child(UIKit.label("You'll have %d %s left." % [left, want.name], 13, UIKit.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 16)
	v.add_child(btns)
	btns.add_child(UIKit.button("Accept", func(): _done(true), 120))
	btns.add_child(UIKit.button("No thanks", func(): _done(false), 120))


func _side(title: String, c: CardDef, foil: bool, is_new: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_child(UIKit.label(title, 15, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	var cv := CardView.make(c, 180, foil)
	if is_new:
		cv.badge = "NEW"
	v.add_child(cv)
	v.add_child(UIKit.label(CardDef.RARITY_NAMES[c.rarity] + (" · Foil" if foil else ""), 13, UIKit.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	return v


func _done(ok: bool) -> void:
	decided.emit(ok)
	queue_free()
