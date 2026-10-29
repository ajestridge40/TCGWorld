class_name CardView
extends Control
## Draws a card at any size. Small sizes show art + stats, large sizes add
## rules text and flavor. Also used for the battlefield, with overlays for
## tapped / damage / attacking state driven by the battle scene.

signal clicked(view: CardView, button: int)
signal hovered(view: CardView, on: bool)

const FOIL_SHADER := preload("res://assets/shaders/foil.gdshader")

var card: CardDef
var foil: bool = false
var face_down: bool = false
var back_style: String = ""
var highlight: Color = Color(0, 0, 0, 0)
var dim: bool = false
var glow: float = 0.0             # rarity glow intensity (pack reveal)
var power_override: int = -999
var toughness_override: int = -999
var damage: int = 0
var badge: String = ""            # small corner text, e.g. "x3" or "NEW"
var badge_color: Color = UIKit.ROSE
var silhouette: bool = false      # unowned card in the binder
var instance_uid: int = -1


static func make(c: CardDef, w: float, p_foil: bool = false) -> CardView:
	var v := CardView.new()
	v.card = c
	v.foil = p_foil
	v.custom_minimum_size = Vector2(w, roundf(w * 1.4))
	v.size = v.custom_minimum_size
	return v


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): hovered.emit(self, true))
	mouse_exited.connect(func(): hovered.emit(self, false))
	_update_material()


func set_foil(on: bool) -> void:
	foil = on
	_update_material()
	queue_redraw()


func _update_material() -> void:
	if foil and not face_down and not silhouette:
		var m := ShaderMaterial.new()
		m.shader = FOIL_SHADER
		m.set_shader_parameter("prism", 1.0 if card and card.rarity == "secret" else 0.0)
		material = m
	else:
		material = null


func set_face_down(on: bool) -> void:
	face_down = on
	_update_material()
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		clicked.emit(self, ev.button_index)
		accept_event()


func _process(_d: float) -> void:
	if glow > 0.0 or foil:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var font := get_theme_default_font()
	var r := maxf(3.0, w * 0.06)
	if glow > 0.0 and card:
		var gc: Color = UIKit.RARITY_COLORS.get(card.rarity, Color.WHITE)
		if card.rarity in ["ultra", "secret"]:
			gc = Color.from_hsv(fmod(Time.get_ticks_msec() / 1500.0, 1.0), 0.5, 1.0)
		for i in range(6, 0, -1):
			var g := float(i) * 3.0 * glow
			_rounded(Rect2(-g, -g, w + g * 2, h + g * 2), r + g, Color(gc, 0.10 * glow))
	if highlight.a > 0.0:
		_rounded(Rect2(-4, -4, w + 8, h + 8), r + 4, highlight)
	if face_down or card == null:
		_draw_back(w, h, r)
		return
	var frame := UIKit.card_color(card)
	if card.is_land():
		frame = frame.lerp(Color("8a7058"), 0.35)
	if silhouette:
		_rounded(Rect2(0, 0, w, h), r, Color("cfc3ab"))
		_rounded(Rect2(3, 3, w - 6, h - 6), r - 2, Color("e4d9c2"))
		var fs0 := clampi(int(w * 0.09), 8, 16)
		draw_string(font, Vector2(0, h * 0.5), "#%d" % card.collector_number, HORIZONTAL_ALIGNMENT_CENTER, w, fs0, Color("a89a80"))
		draw_string(font, Vector2(4, h * 0.5 + fs0 + 4), card.name, HORIZONTAL_ALIGNMENT_CENTER, w - 8, maxi(7, fs0 - 3), Color("a89a80"))
		return
	# Outer border + colored frame
	_rounded(Rect2(0, 0, w, h), r, Color("2a211c"))
	var pad := maxf(2.0, w * 0.035)
	_rounded(Rect2(pad, pad, w - pad * 2, h - pad * 2), r * 0.7, frame)
	var inner_x := pad * 2.0
	var inner_w := w - pad * 4.0
	# Name bar
	var name_h := maxf(10.0, w * 0.13)
	var name_fs := clampi(int(w * 0.075), 7, 17)
	_rounded(Rect2(inner_x, pad * 2.0, inner_w, name_h), 3, UIKit.PAPER)
	var pip_space := _draw_cost(Vector2(inner_x + inner_w - 2, pad * 2.0 + name_h * 0.5), name_h * 0.36)
	if w >= 70:
		var room := inner_w - pip_space - 6
		while name_fs > 7 and font.get_string_size(card.name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs).x > room:
			name_fs -= 1
		draw_string(font, Vector2(inner_x + 3, pad * 2.0 + name_h * 0.5 + name_fs * 0.36), card.name,
				HORIZONTAL_ALIGNMENT_LEFT, room, name_fs, UIKit.INK)
	# Art
	var art_y := pad * 2.0 + name_h + pad
	var art_h := inner_w / 1.5
	var art_rect := Rect2(inner_x, art_y, inner_w, art_h)
	draw_rect(art_rect.grow(1), Color("2a211c"))
	draw_texture_rect(CardArt.get_texture(card), art_rect, false, Color(0.55, 0.55, 0.55) if dim else Color.WHITE)
	# Type line
	var type_y := art_y + art_h + pad
	var type_h := maxf(8.0, w * 0.1)
	var small_fs := clampi(int(w * 0.06), 7, 14)
	if w >= 110:
		_rounded(Rect2(inner_x, type_y, inner_w, type_h), 2, UIKit.PAPER_DARK)
		draw_string(font, Vector2(inner_x + 3, type_y + type_h * 0.5 + small_fs * 0.36), card.type_line(),
				HORIZONTAL_ALIGNMENT_LEFT, inner_w - 16, small_fs, UIKit.INK)
		_rarity_gem(Vector2(inner_x + inner_w - 7, type_y + type_h * 0.5), type_h * 0.3)
		# Rules text box
		var box_y := type_y + type_h + pad
		var box_h := h - box_y - pad * 2.0
		_rounded(Rect2(inner_x, box_y, inner_w, box_h), 3, Color("fbf4e2"))
		var txt := card.text
		var text_fs := clampi(int(w * 0.058), 8, 14)
		draw_multiline_string(font, Vector2(inner_x + 4, box_y + text_fs + 2), txt, HORIZONTAL_ALIGNMENT_LEFT,
				inner_w - 8, text_fs, 6, UIKit.INK)
		if card.flavor != "" and w >= 180:
			var lines := txt.count("\n") + 1 + int(txt.length() * text_fs * 0.55 / (inner_w - 8))
			var fy := box_y + text_fs + 2 + lines * (text_fs + 2) + 4
			if fy < box_y + box_h - text_fs:
				draw_multiline_string(font, Vector2(inner_x + 4, fy), card.flavor, HORIZONTAL_ALIGNMENT_LEFT,
						inner_w - 8, text_fs - 1, int((box_y + box_h - fy) / (text_fs + 1)), UIKit.INK_SOFT)
	else:
		# Compact: keyword initials under the art
		var kws: PackedStringArray = []
		for k in card.keywords:
			kws.append(CardDef.KEYWORD_NAMES.get(k, k).substr(0, 1))
		if not card.effects.is_empty():
			kws.append("*")
		if not kws.is_empty():
			draw_string(font, Vector2(inner_x + 1, type_y + small_fs), " ".join(kws), HORIZONTAL_ALIGNMENT_LEFT, inner_w, small_fs, Color("fffaf0"))
		if card.is_land():
			draw_string(font, Vector2(inner_x, h - pad * 3), CardDef.COLOR_NAMES.get(card.produces, ""), HORIZONTAL_ALIGNMENT_CENTER, inner_w, small_fs, Color("fffaf0"))
		elif not card.is_creature():
			draw_string(font, Vector2(inner_x, h - pad * 3), "Instant" if card.is_instant() else "Sorcery", HORIZONTAL_ALIGNMENT_CENTER, inner_w, small_fs, Color("fffaf0"))
	# Power / toughness
	if card.is_creature():
		var pw := card.power if power_override == -999 else power_override
		var tg := card.toughness if toughness_override == -999 else toughness_override
		var pt_fs := clampi(int(w * 0.11), 9, 20)
		var bw := pt_fs * 2.6
		var bh := pt_fs * 1.35
		var bx := w - pad - bw
		var by := h - pad - bh
		_rounded(Rect2(bx, by, bw, bh), 3, Color("2a211c"))
		_rounded(Rect2(bx + 1.5, by + 1.5, bw - 3, bh - 3), 2, UIKit.PAPER)
		var pt_col := UIKit.INK
		if pw > card.power or tg > card.toughness:
			pt_col = Color("2e7d32")
		elif pw < card.power or tg - damage < card.toughness:
			pt_col = Color("c0392b")
		draw_string(font, Vector2(bx, by + bh * 0.5 + pt_fs * 0.36), "%d/%d" % [pw, tg - damage],
				HORIZONTAL_ALIGNMENT_CENTER, bw, pt_fs, pt_col)
	if w < 110 and not card.is_land():
		_rarity_gem(Vector2(pad * 3.5, h - pad * 3.5), maxf(2.0, w * 0.035))
	if dim:
		_rounded(Rect2(0, 0, w, h), r, Color(0.1, 0.08, 0.12, 0.35))
	if badge != "":
		var bfs := clampi(int(w * 0.09), 9, 16)
		var bw2 := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x + 8
		_rounded(Rect2(w - bw2 + 4, -6, bw2, bfs + 6), 4, badge_color)
		draw_string(font, Vector2(w - bw2 + 8, bfs - 3), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, Color.WHITE)


func _draw_back(w: float, h: float, r: float) -> void:
	var maple := back_style == "maple" or (back_style == "" and Game.supplies.has("sleeves_maple"))
	var base := Color("8c3b2a") if maple else Color("3d5a80")
	_rounded(Rect2(0, 0, w, h), r, Color("2a211c"))
	_rounded(Rect2(3, 3, w - 6, h - 6), r * 0.7, base)
	var inner := base.lightened(0.15)
	_rounded(Rect2(w * 0.15, h * 0.12, w * 0.7, h * 0.76), r * 0.5, inner)
	var c := Vector2(w * 0.5, h * 0.5)
	var s := w * 0.18
	var pts := PackedVector2Array([c + Vector2(0, -s * 1.3), c + Vector2(s, 0), c + Vector2(0, s * 1.3), c + Vector2(-s, 0)])
	draw_colored_polygon(pts, UIKit.GOLD)
	draw_circle(c, s * 0.35, base.darkened(0.2))


func _rounded(rect: Rect2, radius: float, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = false
	draw_style_box(sb, rect)


## Draws mana pips right-to-left ending at `right`. Returns the width used.
func _draw_cost(right: Vector2, rad: float) -> float:
	if card.is_land():
		return 0.0
	var pips: Array = []
	if card.cost_generic > 0 or card.cost_colors.is_empty():
		pips.append(["n", card.cost_generic])
	for col in CardDef.COLORS:
		for i in int(card.cost_colors.get(col, 0)):
			pips.append([col, 0])
	var x := right.x - rad
	var font := get_theme_default_font()
	var fs := maxi(6, int(rad * 1.6))
	for i in range(pips.size() - 1, -1, -1):
		var p: Array = pips[i]
		if p[0] == "n":
			draw_circle(Vector2(x, right.y), rad, Color("cfc6b8"))
			draw_string(font, Vector2(x - rad, right.y + fs * 0.36), str(p[1]), HORIZONTAL_ALIGNMENT_CENTER, rad * 2, fs, UIKit.INK)
		else:
			draw_circle(Vector2(x, right.y), rad, UIKit.CARD_COLORS[p[0]])
			draw_circle(Vector2(x - rad * 0.3, right.y - rad * 0.3), rad * 0.3, Color(1, 1, 1, 0.5))
		x -= rad * 2.0 + 1.0
	return right.x - x - rad


func _rarity_gem(center: Vector2, rad: float) -> void:
	var c: Color = UIKit.RARITY_COLORS.get(card.rarity, Color.WHITE)
	var pts := PackedVector2Array([center + Vector2(0, -rad * 1.3), center + Vector2(rad, 0), center + Vector2(0, rad * 1.3), center + Vector2(-rad, 0)])
	draw_colored_polygon(pts, Color("2a211c"))
	var pts2 := PackedVector2Array([center + Vector2(0, -rad), center + Vector2(rad * 0.7, 0), center + Vector2(0, rad), center + Vector2(-rad * 0.7, 0)])
	draw_colored_polygon(pts2, c)
