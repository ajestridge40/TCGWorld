extends Control
## Title screen: continue, or start a new game by picking a name and a starter deck.

var name_edit := LineEdit.new()
var starter_box := HBoxContainer.new()
var main_box := VBoxContainer.new()
var new_panel := PanelContainer.new()
var chosen := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	RenderingServer.set_default_clear_color(Color("2b2135"))
	var bg := TitleBackdrop.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := UIKit.label("TCG World", 64, Color("fff3d6"), HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_outline_color", Color("6b4a32"))
	title.add_theme_constant_override("outline_size", 14)
	title.position = Vector2(0, 50)
	title.size = Vector2(960, 80)
	add_child(title)
	var sub := UIKit.label("~ a cozy card-shop life in Maplebrook ~", 18, UIKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(0, 132)
	sub.size = Vector2(960, 30)
	add_child(sub)
	main_box.position = Vector2(380, 230)
	main_box.custom_minimum_size = Vector2(200, 0)
	main_box.add_theme_constant_override("separation", 10)
	add_child(main_box)
	if Game.has_save():
		main_box.add_child(UIKit.button("Continue", _continue))
	main_box.add_child(UIKit.button("New Game", _show_new))
	main_box.add_child(UIKit.button("Quit", func(): get_tree().quit()))
	_build_new_panel()


func _continue() -> void:
	if Game.load_game():
		Game.goto("world")


func _show_new() -> void:
	main_box.visible = false
	new_panel.visible = true
	name_edit.grab_focus()


func _build_new_panel() -> void:
	new_panel.position = Vector2(80, 180)
	new_panel.custom_minimum_size = Vector2(800, 340)
	new_panel.visible = false
	add_child(new_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	new_panel.add_child(v)
	var h := HBoxContainer.new()
	h.add_child(UIKit.label("Your name:", 18))
	name_edit.text = "Sam"
	name_edit.max_length = 14
	name_edit.custom_minimum_size.x = 200
	h.add_child(name_edit)
	v.add_child(h)
	v.add_child(UIKit.label("Choose your starter deck:", 18))
	starter_box.add_theme_constant_override("separation", 12)
	v.add_child(starter_box)
	for s in CardDB.starters:
		starter_box.add_child(_starter_card(s))
	var go := HBoxContainer.new()
	go.alignment = BoxContainer.ALIGNMENT_CENTER
	go.add_theme_constant_override("separation", 12)
	v.add_child(go)
	go.add_child(UIKit.button("Back", func():
		new_panel.visible = false
		main_box.visible = true, 100))


func _starter_card(s: Dictionary) -> Control:
	var p := UIKit.panel(Color("fffaf0"))
	p.custom_minimum_size = Vector2(248, 220)
	var v := VBoxContainer.new()
	p.add_child(v)
	var cols := HBoxContainer.new()
	for col in s["colors"]:
		var dot := ColorRect.new()
		dot.color = UIKit.CARD_COLORS[col]
		dot.custom_minimum_size = Vector2(16, 16)
		cols.add_child(dot)
	cols.add_child(UIKit.label("  " + " / ".join(s["colors"].map(func(c): return CardDef.COLOR_NAMES[c])), 13, UIKit.INK_SOFT))
	v.add_child(UIKit.label(s["name"], 18, UIKit.WOOD))
	v.add_child(cols)
	var blurb := UIKit.label(s["blurb"], 13)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.custom_minimum_size = Vector2(228, 70)
	v.add_child(blurb)
	# Show the rare as the deck's "face card".
	var face := ""
	for id in s["cards"]:
		var c: CardDef = CardDB.get_card(id)
		if c.rarity == "rare":
			face = id
	if face != "":
		var art := TextureRect.new()
		art.texture = CardArt.get_texture(CardDB.get_card(face))
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.custom_minimum_size = Vector2(96, 64)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		v.add_child(art)
	v.add_child(UIKit.button("Start with this deck", func(): _start(s["id"])))
	return p


func _start(starter_id: String) -> void:
	Game.new_game(name_edit.text, starter_id)
	Game.goto("world")


## Soft night sky over pixel hills, with drifting cards.
class TitleBackdrop:
	extends Control
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		_t += d
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		for i in 18:
			var c := Color("2b2135").lerp(Color("c86a6a"), i / 24.0)
			draw_rect(Rect2(0, i * h / 18.0, w, h / 18.0 + 1), c)
		var r := RandomNumberGenerator.new()
		r.seed = 3
		for i in 60:
			var a := 0.4 + 0.4 * sin(_t * 2.0 + i)
			draw_rect(Rect2(r.randf() * w, r.randf() * h * 0.5, 2, 2), Color(1, 1, 0.9, a))
		for i in 7:
			var x := fmod(r.randf() * w + _t * (10 + i * 3), w + 80) - 40
			var y := 180 + r.randf() * 140 + sin(_t + i) * 10
			var col: Color = UIKit.CARD_COLORS.values()[i % 5]
			draw_set_transform(Vector2(x, y), sin(_t * 0.5 + i) * 0.4)
			draw_rect(Rect2(-12, -17, 24, 34), Color("2a211c"))
			draw_rect(Rect2(-10, -15, 20, 30), col)
			draw_rect(Rect2(-8, -12, 16, 11), Color("fff3d6"))
		draw_set_transform(Vector2.ZERO)
		for layer in 3:
			var base := h - 90 + layer * 30
			var col2 := Color("3f5a3a").darkened(0.25 - layer * 0.12)
			for x in range(0, int(w), 4):
				var y2 := base + sin(x * 0.01 + layer * 2.0) * 18 + sin(x * 0.03) * 6
				draw_rect(Rect2(x, y2, 4, h - y2), col2)
		# Little shop with a warm window
		draw_rect(Rect2(700, h - 150, 120, 70), Color("f3e2b8"))
		draw_rect(Rect2(690, h - 182, 140, 34), Color("3f8f8a"))
		draw_rect(Rect2(720, h - 130, 26, 22), Color("ffe8a3"))
		draw_rect(Rect2(770, h - 128, 22, 48), Color("8a5a36"))
