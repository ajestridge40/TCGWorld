extends Control
## The Gilded Deck counter: buy packs/supplies/singles, sell cards, work shifts.

var gus_line := RichTextLabel.new()
var coins_label := UIKit.label("", 18)
var sealed_btn: Button
var shift_btn: Button
var tabs := TabContainer.new()
var preview_holder := Control.new()
var _preview: CardView

const GUS_LINES := {
	"welcome": ["What'll it be?", "Fresh box came in this morning. Smells like ink and dreams.", "Take your time. The cards aren't going anywhere. Well, the good ones might."],
	"buy_pack": ["Good luck. Not that luck has anything to do with it. It does. It's all luck.", "May your rares be shiny.", "Rip it here if you want. I like watching."],
	"poor": ["You're a little short there, friend.", "Come back when your pockets are heavier."],
	"sell": ["I'll give you a fair price. Fair for me, anyway.", "Into the bulk bin it goes."],
	"supply": ["Good choice. Protect your investment.", "A player with a nice playmat is a player who plays more. Science."],
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UIKit.backdrop(self, Color("4a3428"))
	_wood_wall()
	add_child(ToastLayer.new())
	# Left: Gus behind the counter.
	var left := UIKit.panel()
	left.position = Vector2(12, 12)
	left.custom_minimum_size = Vector2(220, 516)
	add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left.add_child(lv)
	lv.add_child(UIKit.label("The Gilded Deck", 20, UIKit.WOOD, HORIZONTAL_ALIGNMENT_CENTER))
	var portrait := TextureRect.new()
	portrait.texture = CharacterSprite.texture(CardDB.npc("gus")["look"], 0, 0)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size = Vector2(128, 128)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	lv.add_child(portrait)
	var bubble := UIKit.panel(Color("fffaf0"), UIKit.WOOD)
	gus_line.bbcode_enabled = true
	gus_line.fit_content = true
	gus_line.custom_minimum_size = Vector2(180, 60)
	gus_line.add_theme_color_override("default_color", UIKit.INK)
	gus_line.add_theme_font_size_override("normal_font_size", 14)
	bubble.add_child(gus_line)
	lv.add_child(bubble)
	lv.add_child(coins_label)
	sealed_btn = UIKit.button("", _open_sealed)
	lv.add_child(sealed_btn)
	shift_btn = UIKit.button("Work a shift", _work_shift)
	lv.add_child(shift_btn)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(spacer)
	lv.add_child(UIKit.button("Leave", _leave))
	# Right: tabs.
	tabs.position = Vector2(244, 12)
	tabs.custom_minimum_size = Vector2(500, 516)
	tabs.size = tabs.custom_minimum_size
	add_child(tabs)
	preview_holder.position = Vector2(752, 40)
	preview_holder.size = Vector2(200, 280)
	preview_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview_holder)
	var hint := UIKit.label("Hover a card to inspect it.", 13, Color("e8d5ae"), HORIZONTAL_ALIGNMENT_CENTER)
	hint.position = Vector2(752, 330)
	hint.size = Vector2(200, 20)
	add_child(hint)
	_build_tabs()
	_say("welcome")
	var newest := Game.newest_set()
	var rd := int(CardDB.sets[newest].get("release_day", 0))
	if rd > 0 and Game.day - rd < 7:
		gus_line.text = "%s just hit the shelves! New tricks in this one: %s. Kids have been lined up since dawn." % [
			CardDB.sets[newest]["name"], ", ".join(CardDB.sets[newest].get("new_mechanics", []).slice(0, 3))]
	_refresh()
	if Game.shop_tab != "":
		for i in tabs.get_tab_count():
			if tabs.get_tab_title(i) == Game.shop_tab:
				tabs.current_tab = i
		Game.shop_tab = ""


func _wood_wall() -> void:
	for i in 12:
		var plank := ColorRect.new()
		plank.color = Color("5a3e2b") if i % 2 == 0 else Color("523826")
		plank.position = Vector2(0, i * 45)
		plank.size = Vector2(960, 44)
		plank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(plank)


func _say(kind: String) -> void:
	var lines: Array = GUS_LINES[kind]
	gus_line.text = lines[randi() % lines.size()]


func _refresh() -> void:
	coins_label.text = "Coins: " + UIKit.coins_text(Game.coins)
	var n := Game.sealed_total()
	sealed_btn.text = "Open my packs (%d)" % n
	sealed_btn.disabled = n == 0
	var sh: Dictionary = CardDB.products["shift"]
	var h := Game.hour()
	var can_shift := Game.hearts("gus") >= int(sh["min_hearts"]) and h >= float(sh["open"]) and h + float(sh["hours"]) <= float(sh["close"])
	shift_btn.disabled = not can_shift
	shift_btn.text = "Work a shift (+%dc, %dh)" % [int(sh["pay"]), int(sh["hours"])]
	if Game.hearts("gus") < int(sh["min_hearts"]):
		shift_btn.tooltip_text = "Gus needs to know you a little better (%d hearts)." % int(sh["min_hearts"])
	else:
		shift_btn.tooltip_text = "Shifts start between %d:00 and %d:00." % [int(sh["open"]), int(sh["close"]) - int(sh["hours"])]


func _build_tabs() -> void:
	for c in tabs.get_children():
		c.queue_free()
	tabs.add_child(_packs_tab())
	tabs.add_child(_supplies_tab())
	tabs.add_child(_singles_tab())
	tabs.add_child(_sell_tab())


func _scroll(title: String) -> Array:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	sc.add_child(v)
	return [sc, v]


func _row(title: String, desc: String, right: Control) -> Control:
	var p := UIKit.panel(Color("fffaf0"), Color("c8a878"))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UIKit.label(title, 16))
	var d := UIKit.label(desc, 12, UIKit.INK_SOFT)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size.x = 300
	v.add_child(d)
	h.add_child(v)
	h.add_child(right)
	return p


func _packs_tab() -> Control:
	var s := _scroll("Packs")
	for p in CardDB.products["products"]:
		if p["kind"] == "supply":
			continue
		if p.has("set") and not CardDB.is_released(p["set"], Game.day):
			continue
		var locked: bool = Game.rank < int(p.get("min_rank", 1))
		var b := UIKit.button("Rank %d" % int(p["min_rank"]) if locked else UIKit.coins_text(int(p["price"])), func(): _buy(p), 100)
		b.disabled = locked
		var desc: String = p["desc"]
		if p.has("set") and p["set"] == Game.newest_set() and Game.released_sets().size() > 1:
			desc = "NEW! " + desc
		s[1].add_child(_row(p["name"], desc, b))
	for set_id in Game.released_sets():
		var info: Dictionary = CardDB.sets[set_id]
		var w: Dictionary = info["pack"]["slots"].back().get("weights", {})
		var odds := UIKit.label("%s: Rare %d%% · Ultra %d%% · Secret %d%% per pack. New mechanics: %s." % [
			info["name"], int(w.get("rare", 0)), int(w.get("ultra", 0)), int(w.get("secret", 0)), ", ".join(info.get("new_mechanics", []))], 12, UIKit.INK_SOFT)
		odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s[1].add_child(odds)
	for set_id in CardDB.set_order:
		var rd := int(CardDB.sets[set_id].get("release_day", 0))
		if rd > Game.day:
			var days := rd - Game.day
			var teaser := UIKit.label("Coming soon: %s, in %d day%s. %s" % [CardDB.sets[set_id]["name"], days, "" if days == 1 else "s", CardDB.sets[set_id].get("description", "")], 12, UIKit.TEAL.darkened(0.3))
			teaser.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			s[1].add_child(teaser)
	return s[0]


func _supplies_tab() -> Control:
	var s := _scroll("Supplies")
	for p in CardDB.products["products"]:
		if p["kind"] != "supply":
			continue
		var owned: bool = Game.supplies.has(p["id"])
		var locked: bool = Game.rank < int(p.get("min_rank", 1))
		var b: Button
		if owned and p["id"].begins_with("playmat"):
			var equipped: bool = Game.playmat == p["id"]
			b = UIKit.button("Unequip" if equipped else "Equip", func():
				Game.playmat = "" if equipped else p["id"]
				_build_tabs_keep(1), 100)
		elif owned:
			b = UIKit.button("Owned", func(): pass, 100)
			b.disabled = true
		else:
			b = UIKit.button("Rank %d" % int(p["min_rank"]) if locked else UIKit.coins_text(int(p["price"])), func(): _buy(p), 100)
			b.disabled = locked
		s[1].add_child(_row(p["name"], p["desc"], b))
	return s[0]


func _singles_tab() -> Control:
	var s := _scroll("Singles")
	s[1].add_child(UIKit.label("Gus's display case. New stock every morning.", 13, UIKit.INK_SOFT))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	s[1].add_child(grid)
	for i in Game.daily_singles.size():
		var sg: Dictionary = Game.daily_singles[i]
		var c: CardDef = CardDB.get_card(sg["id"])
		var v := VBoxContainer.new()
		var cv := CardView.make(c, 120, sg["foil"])
		cv.hovered.connect(_on_hover)
		if Game.collection.count(c.id) == 0:
			cv.badge = "NEW"
		v.add_child(cv)
		if sg.get("sold", false):
			var b0 := UIKit.button("Sold", func(): pass)
			b0.disabled = true
			v.add_child(b0)
		else:
			v.add_child(UIKit.button(UIKit.coins_text(int(sg["price"])), func(): _buy_single(i)))
		grid.add_child(v)
	return s[0]


func _sell_tab() -> Control:
	var s := _scroll("Sell")
	var extras_total := 0
	var extras_n := 0
	var keys: Array = Game.collection.counts.keys()
	keys.sort_custom(func(a, b):
		var ca: CardDef = CardDB.get_card(Collection.split_key(a)[0])
		var cb: CardDef = CardDB.get_card(Collection.split_key(b)[0])
		return CardDef.RARITIES.find(ca.rarity) * 1000 + ca.collector_number > CardDef.RARITIES.find(cb.rarity) * 1000 + cb.collector_number)
	for k in keys:
		var parts := Collection.split_key(k)
		var id: String = parts[0]
		var e := Game.collection.extras(id)
		if e > 0 and not parts[1]:
			extras_n += mini(e, Game.collection.count_variant(id, false))
			extras_total += mini(e, Game.collection.count_variant(id, false)) * CardDB.sell_price(id, false)
	var top := HBoxContainer.new()
	top.add_child(UIKit.label("Extras beyond a playset: %d cards" % extras_n, 14))
	var sell_all := UIKit.button("Sell extras (+%s)" % UIKit.coins_text(extras_total), _sell_extras)
	sell_all.disabled = extras_n == 0
	top.add_child(sell_all)
	s[1].add_child(top)
	for k in keys:
		var parts := Collection.split_key(k)
		var id: String = parts[0]
		var foil: bool = parts[1]
		var c: CardDef = CardDB.get_card(id)
		if c == null or c.is_token:
			continue
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var cv := CardView.make(c, 36, foil)
		cv.hovered.connect(_on_hover)
		h.add_child(cv)
		var name_l := UIKit.label("%s%s" % [c.name, " (Foil)" if foil else ""], 14)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.add_theme_color_override("font_color", UIKit.INK if c.rarity in ["common", "uncommon"] else UIKit.RARITY_COLORS[c.rarity].darkened(0.45))
		h.add_child(name_l)
		h.add_child(UIKit.label("x%d" % Game.collection.counts[k], 14, UIKit.INK_SOFT))
		var in_decks := _in_decks(id)
		var b := UIKit.button("Sell %s" % UIKit.coins_text(CardDB.sell_price(id, foil)), func(): _sell(id, foil), 96)
		if Game.collection.count(id) <= in_decks:
			b.tooltip_text = "Careful: this copy is in one of your decks."
		h.add_child(b)
		s[1].add_child(h)
	return s[0]


func _in_decks(id: String) -> int:
	var most := 0
	for dk in Game.decks:
		most = maxi(most, int(dk.cards.get(id, 0)))
	return most


func _on_hover(cv: CardView, on: bool) -> void:
	if _preview:
		_preview.queue_free()
		_preview = null
	if on:
		_preview = CardView.make(cv.card, 200, cv.foil)
		_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview_holder.add_child(_preview)


func _build_tabs_keep(idx: int = -1) -> void:
	var cur := tabs.current_tab if idx < 0 else idx
	_build_tabs()
	await get_tree().process_frame
	tabs.current_tab = cur
	_refresh()


# ---------------------------------------------------------------- actions

func _buy(p: Dictionary) -> void:
	if not Game.spend(int(p["price"])):
		Sfx.play("nope")
		_say("poor")
		return
	Sfx.play("coin")
	match p["kind"]:
		"pack":
			Game.add_sealed(p["set"], p.get("variant", ""))
			_say("buy_pack")
		"bundle":
			Game.add_sealed(p["set"], "", int(p["packs"]))
			_say("buy_pack")
		"mystery":
			_mystery(p)
		"supply":
			Game.supplies.append(p["id"])
			if p["id"].begins_with("playmat"):
				Game.playmat = p["id"]
			_say("supply")
	Game.save_game()
	_build_tabs_keep()


func _mystery(p: Dictionary) -> void:
	var r := Game.rng
	var sets := Game.released_sets()
	var set_id: String = sets[r.randi_range(0, sets.size() - 1)]
	if r.randf() < 0.7:
		var n := r.randi_range(2, 5)
		Game.add_sealed(set_id, "", n)
		gus_line.text = "Ha! %d %s packs in that one. Not bad, not bad." % [n, CardDB.sets[set_id]["name"]]
	else:
		var rar := PackGenerator.weighted_pick({ "rare": 75, "ultra": 20, "secret": 5 }, r)
		var pool := CardDB.cards_of_rarity(set_id, rar)
		var id: String = pool[r.randi_range(0, pool.size() - 1)]
		Game.add_pulls([{ "id": id, "foil": false }], false)
		gus_line.text = "A single! [b]%s[/b]. %s" % [CardDB.get_card(id).name, "Whoa." if rar != "rare" else "Nice."]
		Game.toast.emit("Mystery Box: " + CardDB.get_card(id).name, "achievement" if rar != "rare" else "info")


func _buy_single(i: int) -> void:
	var sg: Dictionary = Game.daily_singles[i]
	if not Game.spend(int(sg["price"])):
		Sfx.play("nope")
		_say("poor")
		return
	Sfx.play("coin")
	Game.add_pulls([{ "id": sg["id"], "foil": sg["foil"] }], false)
	sg["sold"] = true
	gus_line.text = "Pleasure. Sleeve that one right away."
	Game.save_game()
	_build_tabs_keep()


func _sell(id: String, foil: bool) -> void:
	if Game.collection.remove(id, foil):
		Game.add_coins(CardDB.sell_price(id, foil))
		Sfx.play("coin")
		_say("sell")
		_fix_decks()
		_build_tabs_keep()


func _sell_extras() -> void:
	var total := 0
	for k in Game.collection.counts.keys():
		var parts := Collection.split_key(k)
		if parts[1]:
			continue
		var id: String = parts[0]
		var n := mini(Game.collection.extras(id), Game.collection.count_variant(id, false))
		if n > 0:
			Game.collection.remove(id, false, n)
			total += n * CardDB.sell_price(id, false)
	Game.add_coins(total)
	Sfx.play("coin")
	gus_line.text = "That's %s. Into the bulk bin they go." % UIKit.coins_text(total)
	_build_tabs_keep()


## Selling can leave a deck needing cards you no longer own; trim it.
func _fix_decks() -> void:
	for dk in Game.decks:
		for id in dk.cards.keys():
			var c: CardDef = CardDB.get_card(id)
			if dk.cards[id] > Game.collection.count(id):
				dk.cards[id] = Game.collection.count(id)
				if dk.cards[id] <= 0:
					dk.cards.erase(id)


func _work_shift() -> void:
	var sh: Dictionary = CardDB.products["shift"]
	Game.advance_time(int(sh["hours"]) * 60)
	Game.add_coins(int(sh["pay"]))
	Game.add_friendship("gus", int(sh["friend_points"]))
	Game.stats["shifts"] = int(Game.stats.get("shifts", 0)) + 1
	Game.unlock("first_shift")
	Sfx.play("coin")
	var stories := [
		"You restock the pack wall, alphabetize the bulk bins and help a kid pick their first deck. Gus nods approvingly.",
		"You sort three thousand commons. Somewhere in there was a foil. Gus lets you keep it. (He doesn't.)",
		"A rush after school! You sell nine packs and settle a heated debate about whether Soar beats Reach.",
	]
	gus_line.text = stories[Game.stats["shifts"] % stories.size()] + " [b]+%dc[/b]" % int(sh["pay"])
	_refresh()


func _open_sealed() -> void:
	Game.open_packs(Game.take_sealed_all(), "shop")


func _leave() -> void:
	Game.save_game()
	Game.goto("world")
