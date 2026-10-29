extends Control
## Collection binder: two 3x3 pages per spread, ordered by collector number.
## Unowned cards show as numbered empty pockets so you can see what's missing.

const PER_PAGE := 9
const CARD_W := 88.0

var set_id := "hvb"
var filter := "all"
var page := 0
var ids: Array = []
var spread := HBoxContainer.new()
var page_label := UIKit.label("", 14, Color("f6ead0"), HORIZONTAL_ALIGNMENT_CENTER)
var completion_label := UIKit.label("", 16)
var bar := ProgressBar.new()
var inspect_layer := Control.new()
var rarity_box := VBoxContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var leather := Game.supplies.has("binder_leather")
	UIKit.backdrop(self, Color("3b2c3f"))
	add_child(ToastLayer.new())
	# Sidebar
	var side := UIKit.panel()
	side.position = Vector2(12, 12)
	side.custom_minimum_size = Vector2(196, 516)
	add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 6)
	side.add_child(sv)
	sv.add_child(UIKit.label("My Binder", 22, UIKit.WOOD))
	sv.add_child(UIKit.label(CardDB.sets[set_id]["name"], 13, UIKit.INK_SOFT))
	sv.add_child(completion_label)
	bar.custom_minimum_size = Vector2(170, 14)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = UIKit.LEAF
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("fill", fill)
	var bgs := StyleBoxFlat.new()
	bgs.bg_color = UIKit.PAPER_DARK
	bgs.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bgs)
	sv.add_child(bar)
	sv.add_child(rarity_box)
	sv.add_child(UIKit.label("Show", 14, UIKit.INK_SOFT))
	var fgrid := GridContainer.new()
	fgrid.columns = 2
	sv.add_child(fgrid)
	for f in [["all", "All"], ["owned", "Owned"], ["missing", "Missing"], ["foil", "Foils"], ["ember", "Ember"], ["tide", "Tide"],
			["grove", "Grove"], ["sun", "Sun"], ["moon", "Moon"], ["colorless", "Colorless"]]:
		var key: String = f[0]
		var b := UIKit.button(f[1], func(): _set_filter(key), 84)
		fgrid.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sv.add_child(spacer)
	sv.add_child(UIKit.button("Deck Builder", func(): Game.goto("decks")))
	sv.add_child(UIKit.button("Back", _back))
	# Binder spread
	var cover := Panel.new()
	cover.add_theme_stylebox_override("panel", UIKit.panel_style(Color("6b3a2a") if leather else Color("3d5a80"), Color("2a211c"), 4, 10))
	cover.position = Vector2(220, 12)
	cover.size = Vector2(728, 480)
	add_child(cover)
	spread.position = Vector2(232, 22)
	spread.add_theme_constant_override("separation", 16)
	add_child(spread)
	var nav := HBoxContainer.new()
	nav.position = Vector2(220, 498)
	nav.size = Vector2(728, 32)
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 16)
	add_child(nav)
	nav.add_child(UIKit.button("◀  Prev", func(): _flip(-1), 100))
	page_label.custom_minimum_size.x = 160
	nav.add_child(page_label)
	nav.add_child(UIKit.button("Next  ▶", func(): _flip(1), 100))
	inspect_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspect_layer.visible = false
	add_child(inspect_layer)
	_rebuild()


func _back() -> void:
	Game.save_game()
	Game.goto(Game.return_scene if Game.return_scene in ["world", "shop"] else "world")


func _set_filter(f: String) -> void:
	filter = f
	page = 0
	_rebuild()


func _flip(d: int) -> void:
	var pages := maxi(1, ceili(ids.size() / float(PER_PAGE)))
	var np := clampi(page + d * 2, 0, maxi(0, pages - 1))
	np -= np % 2
	if np != page:
		page = np
		Sfx.play("flip", 0.8)
		_rebuild()


func _matches(id: String) -> bool:
	var c: CardDef = CardDB.get_card(id)
	var owned := Game.collection.count(id) > 0
	match filter:
		"owned": return owned
		"missing": return not owned
		"foil": return Game.collection.has_foil(id)
		"all": return true
		_: return c.main_color() == filter


func _rebuild() -> void:
	ids = CardDB.set_card_ids(set_id).filter(_matches)
	var total := CardDB.set_card_ids(set_id).size()
	var owned := Game.collection.owned_unique(set_id)
	completion_label.text = "%d / %d collected (%d%%)" % [owned, total, int(100.0 * owned / total)]
	bar.max_value = total
	bar.value = owned
	for c in rarity_box.get_children():
		c.queue_free()
	for r in CardDef.RARITIES:
		var all := CardDB.cards_of_rarity(set_id, r)
		var have := all.filter(func(id): return Game.collection.count(id) > 0).size()
		var l := UIKit.label("◆ %s  %d/%d" % [CardDef.RARITY_NAMES[r], have, all.size()], 13, UIKit.RARITY_COLORS[r].darkened(0.45))
		rarity_box.add_child(l)
	for c in spread.get_children():
		c.queue_free()
	for side in 2:
		var pg := page + side
		var sheet := Panel.new()
		sheet.add_theme_stylebox_override("panel", UIKit.panel_style(Color("efe4cc"), Color("b8a888"), 2, 4))
		sheet.custom_minimum_size = Vector2(340, 460)
		spread.add_child(sheet)
		var grid := GridContainer.new()
		grid.columns = 3
		grid.position = Vector2(14, 12)
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 18)
		sheet.add_child(grid)
		for i in PER_PAGE:
			var idx := pg * PER_PAGE + i
			var pocket := Control.new()
			pocket.custom_minimum_size = Vector2(CARD_W, CARD_W * 1.4)
			grid.add_child(pocket)
			if idx >= ids.size():
				continue
			var id: String = ids[idx]
			var c: CardDef = CardDB.get_card(id)
			var n := Game.collection.count(id)
			var cv := CardView.make(c, CARD_W, Game.collection.has_foil(id))
			cv.silhouette = n == 0
			if n > 1:
				cv.badge = "x%d" % n
				cv.badge_color = UIKit.TEAL
			cv.clicked.connect(func(v, _b): _inspect(v.card))
			pocket.add_child(cv)
	var pages := maxi(1, ceili(ids.size() / float(PER_PAGE)))
	page_label.text = "Pages %d-%d of %d" % [page + 1, mini(page + 2, pages), pages]


func _inspect(c: CardDef) -> void:
	Sfx.play("click")
	for ch in inspect_layer.get_children():
		ch.queue_free()
	inspect_layer.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			inspect_layer.visible = false)
	inspect_layer.add_child(dim)
	var n := Game.collection.count(c.id)
	var cv := CardView.make(c, 280, Game.collection.has_foil(c.id))
	cv.silhouette = n == 0
	cv.position = Vector2(200, 50)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspect_layer.add_child(cv)
	var info := UIKit.panel()
	info.position = Vector2(510, 80)
	info.custom_minimum_size = Vector2(260, 0)
	inspect_layer.add_child(info)
	var v := VBoxContainer.new()
	info.add_child(v)
	v.add_child(UIKit.label(c.name if n > 0 else "??? (#%d)" % c.collector_number, 18, UIKit.WOOD))
	v.add_child(UIKit.label(CardDef.RARITY_NAMES[c.rarity], 14, UIKit.RARITY_COLORS[c.rarity].darkened(0.4)))
	v.add_child(UIKit.label("Near Mint: %d" % Game.collection.count_variant(c.id, false), 14))
	v.add_child(UIKit.label("Foil: %d" % Game.collection.count_variant(c.id, true), 14))
	v.add_child(UIKit.label("Gus buys at: %s" % UIKit.coins_text(CardDB.sell_price(c.id)), 14))
	v.add_child(UIKit.label("Deck limit: %d copies" % Deck.copy_limit(c.id), 14))
	if n == 0:
		v.add_child(UIKit.label("Not collected yet. Keep ripping!", 13, UIKit.INK_SOFT))
	v.add_child(UIKit.label("(click anywhere to close)", 12, UIKit.INK_SOFT))
