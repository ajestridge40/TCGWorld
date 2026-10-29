extends Control
## Deck builder: pick a deck, click cards in your collection to add them,
## right-click (or click in the list) to remove.

const CARD_W := 74.0

var deck_idx := 0
var color_filter := "all"
var type_filter := "all"
var deck_select := OptionButton.new()
var name_edit := LineEdit.new()
var list_box := VBoxContainer.new()
var status := UIKit.label("", 13)
var count_label := UIKit.label("", 16)
var curve := CurveView.new()
var grid := GridContainer.new()
var preview_holder := Control.new()
var _preview: CardView
var active_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UIKit.backdrop(self, Color("2f3a32"))
	add_child(ToastLayer.new())
	if Game.decks.is_empty():
		var dk := Deck.new()
		dk.name = "My First Deck"
		Game.decks.append(dk)
	deck_idx = clampi(Game.active_deck, 0, Game.decks.size() - 1)
	_build_left()
	_build_pool()
	preview_holder.position = Vector2(752, 12)
	preview_holder.size = Vector2(196, 274)
	preview_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview_holder)
	var help := UIKit.panel()
	help.position = Vector2(752, 300)
	help.custom_minimum_size = Vector2(196, 0)
	add_child(help)
	var hl := UIKit.label("Click: add · Right-click: remove\nExactly 30 cards, up to 2 colors (colorless goes anywhere). Max 3 per common/uncommon, 2 per rare, 1 per ultra/secret. Aim for lots of 1-3 cost cards.", 11, UIKit.INK_SOFT)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.custom_minimum_size.x = 176
	help.add_child(hl)
	var back := UIKit.button("Done", _back, 196)
	back.position = Vector2(752, 494)
	add_child(back)
	_refresh_all()


func _deck() -> Deck:
	return Game.decks[deck_idx]


func _build_left() -> void:
	var left := UIKit.panel()
	left.position = Vector2(12, 12)
	left.custom_minimum_size = Vector2(260, 516)
	left.size = left.custom_minimum_size
	add_child(left)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	left.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	deck_select.custom_minimum_size.x = 128
	deck_select.clip_text = true
	deck_select.item_selected.connect(func(i):
		deck_idx = i
		_refresh_all())
	top.add_child(deck_select)
	top.add_child(UIKit.button("New", _new_deck))
	top.add_child(UIKit.button("Del", _delete_deck))
	name_edit.placeholder_text = "Deck name"
	name_edit.text_changed.connect(func(t):
		_deck().name = t
		deck_select.set_item_text(deck_idx, t))
	v.add_child(name_edit)
	var h := HBoxContainer.new()
	h.add_child(count_label)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	active_btn = UIKit.button("Use this deck", func():
		Game.active_deck = deck_idx
		_refresh_all())
	h.add_child(active_btn)
	v.add_child(h)
	curve.custom_minimum_size = Vector2(236, 46)
	v.add_child(curve)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(236, 300)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 1)
	sc.add_child(list_box)
	v.add_child(sc)
	v.add_child(status)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 236


func _build_pool() -> void:
	var right := UIKit.panel(Color("f3e8d0"))
	right.position = Vector2(282, 12)
	right.custom_minimum_size = Vector2(462, 516)
	right.size = right.custom_minimum_size
	add_child(right)
	var v := VBoxContainer.new()
	right.add_child(v)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 3)
	v.add_child(filters)
	for f in [["all", "All"], ["ember", "E"], ["tide", "T"], ["grove", "G"], ["sun", "S"], ["moon", "M"], ["colorless", "C"]]:
		var key: String = f[0]
		var b := UIKit.button(f[1], func():
			color_filter = key
			_refresh_pool())
		if key != "all":
			b.add_theme_color_override("font_color", UIKit.CARD_COLORS[key].darkened(0.3))
		filters.add_child(b)
	filters.add_child(VSeparator.new())
	for f in [["all", "Any"], ["creature", "Creature"], ["spell", "Spell"]]:
		var key2: String = f[0]
		filters.add_child(UIKit.button(f[1], func():
			type_filter = key2
			_refresh_pool()))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(436, 462)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	sc.add_child(grid)
	v.add_child(sc)


func _refresh_all() -> void:
	deck_select.clear()
	for i in Game.decks.size():
		var label: String = Game.decks[i].name + (" ★" if i == Game.active_deck else "")
		deck_select.add_item(label)
	deck_select.select(deck_idx)
	name_edit.text = _deck().name
	active_btn.disabled = deck_idx == Game.active_deck
	active_btn.text = "Active ★" if deck_idx == Game.active_deck else "Use this deck"
	_refresh_list()
	_refresh_pool()


func _refresh_list() -> void:
	for c in list_box.get_children():
		c.queue_free()
	var dk := _deck()
	var ids: Array = dk.cards.keys()
	ids.sort_custom(func(a, b):
		var ca: CardDef = CardDB.get_card(a)
		var cb: CardDef = CardDB.get_card(b)
		if ca.cost != cb.cost:
			return ca.cost < cb.cost
		return ca.name < cb.name)
	for id in ids:
		var c: CardDef = CardDB.get_card(id)
		var row := Button.new()
		row.text = "(%d)  %dx  %s" % [c.cost, dk.cards[id], c.name]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_font_size_override("font_size", 13)
		var st := UIKit.panel_style(UIKit.card_color(c).lightened(0.55), UIKit.card_color(c).darkened(0.2), 1, 3)
		st.content_margin_top = 1
		st.content_margin_bottom = 1
		st.shadow_size = 0
		row.add_theme_stylebox_override("normal", st)
		row.add_theme_stylebox_override("hover", st)
		row.custom_minimum_size = Vector2(228, 22)
		row.tooltip_text = c.text
		row.pressed.connect(func(): _remove(id))
		row.mouse_entered.connect(func(): _show_preview(c, false))
		list_box.add_child(row)
	var n := dk.size()
	var cols: Array = dk.colors().map(func(col): return CardDef.COLOR_NAMES[col])
	count_label.text = "%d/%d · %s" % [n, Deck.SIZE, " + ".join(cols) if not cols.is_empty() else "no colors"]
	var errs := dk.validate(Game.collection)
	if errs.is_empty():
		status.text = "✓ Deck is legal and ready to play."
		status.add_theme_color_override("font_color", Color("2e7d32"))
	else:
		status.text = "\n".join(errs.slice(0, 3))
		status.add_theme_color_override("font_color", Color("c0392b"))
	curve.deck = dk
	curve.queue_redraw()


func _pool_ids() -> Array:
	var out: Array = []
	for set_id in CardDB.set_order:
		for id in CardDB.set_card_ids(set_id):
			if Game.collection.count(id) == 0:
				continue
			var c: CardDef = CardDB.get_card(id)
			if color_filter != "all" and c.main_color() != color_filter:
				continue
			if type_filter != "all" and c.type != type_filter:
				continue
			out.append(id)
	out.sort_custom(func(a, b):
		var ca: CardDef = CardDB.get_card(a)
		var cb: CardDef = CardDB.get_card(b)
		if ca.cost != cb.cost:
			return ca.cost < cb.cost
		return ca.collector_number < cb.collector_number)
	return out


func _refresh_pool() -> void:
	for c in grid.get_children():
		c.queue_free()
	var dk := _deck()
	for id in _pool_ids():
		var c: CardDef = CardDB.get_card(id)
		var owned := Game.collection.count(id)
		var used: int = dk.cards.get(id, 0)
		var limit := mini(owned, Deck.copy_limit(id))
		var cv := CardView.make(c, CARD_W, Game.collection.has_foil(id))
		cv.badge = "%d/%d" % [used, limit]
		cv.badge_color = UIKit.TEAL if used < limit else UIKit.INK_SOFT
		cv.dim = used >= limit or not dk.color_allows(id)
		cv.clicked.connect(func(_v, btn):
			if btn == MOUSE_BUTTON_LEFT:
				_add(id)
			elif btn == MOUSE_BUTTON_RIGHT:
				_remove(id))
		cv.hovered.connect(func(v, on):
			if on:
				_show_preview(v.card, v.foil))
		grid.add_child(cv)
	if grid.get_child_count() == 0:
		grid.add_child(UIKit.label("No cards match. Open some packs!", 14, UIKit.INK_SOFT))


func _show_preview(c: CardDef, foil: bool) -> void:
	if _preview:
		_preview.queue_free()
	_preview = CardView.make(c, 196, foil)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_holder.add_child(_preview)


func _add(id: String) -> void:
	var dk := _deck()
	var c: CardDef = CardDB.get_card(id)
	var used: int = dk.cards.get(id, 0)
	if dk.size() >= Deck.SIZE:
		_warn("The deck is full (%d cards). Remove something first." % Deck.SIZE)
		return
	if used >= Game.collection.count(id) or used >= Deck.copy_limit(id):
		_warn("No more copies of %s allowed." % c.name)
		return
	if not dk.color_allows(id):
		_warn("Decks can only use %d colors (plus colorless)." % Deck.MAX_COLORS)
		return
	dk.add(id)
	Sfx.play("play", 1.2, -6.0)
	_refresh_list()
	_refresh_pool()


func _warn(msg: String) -> void:
	Sfx.play("nope")
	status.text = msg
	status.add_theme_color_override("font_color", Color("c0392b"))


func _remove(id: String) -> void:
	var dk := _deck()
	if not dk.cards.has(id):
		return
	dk.remove(id)
	Sfx.play("flip", 1.2, -6.0)
	_refresh_list()
	_refresh_pool()


func _new_deck() -> void:
	if Game.decks.size() >= Game.max_decks():
		Game.toast.emit("Deck slots full (%d). A Wooden Deck Box adds more." % Game.max_decks(), "info")
		Sfx.play("nope")
		return
	var dk := Deck.new()
	dk.name = "Deck %d" % (Game.decks.size() + 1)
	Game.decks.append(dk)
	deck_idx = Game.decks.size() - 1
	_refresh_all()


func _delete_deck() -> void:
	if Game.decks.size() <= 1:
		Sfx.play("nope")
		return
	Game.decks.remove_at(deck_idx)
	if Game.active_deck >= Game.decks.size() or Game.active_deck == deck_idx:
		Game.active_deck = 0
	elif Game.active_deck > deck_idx:
		Game.active_deck -= 1
	deck_idx = 0
	_refresh_all()


func _back() -> void:
	Game.save_game()
	Game.goto(Game.return_scene if Game.return_scene in ["world", "shop"] else "world")


## Spark curve histogram (cards by cost, 0..7+).
class CurveView:
	extends Control
	var deck: Deck

	func _draw() -> void:
		if deck == null:
			return
		var buckets := deck.curve()
		var most := 1
		for b in buckets:
			most = maxi(most, b)
		var font := get_theme_default_font()
		var n := buckets.size()
		var bw := size.x / n
		for i in n:
			var hgt: float = (size.y - 14) * buckets[i] / most
			draw_rect(Rect2(i * bw + 3, size.y - 12 - hgt, bw - 6, hgt), UIKit.GOLD.darkened(0.15))
			draw_string(font, Vector2(i * bw, size.y), str(i) if i < n - 1 else "%d+" % i, HORIZONTAL_ALIGNMENT_CENTER, bw, 10, UIKit.INK_SOFT)
			if buckets[i] > 0:
				draw_string(font, Vector2(i * bw, size.y - 14 - hgt), str(buckets[i]), HORIZONTAL_ALIGNMENT_CENTER, bw, 10, UIKit.INK)
