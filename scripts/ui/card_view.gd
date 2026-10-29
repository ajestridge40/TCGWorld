class_name CardView
extends Control
## Draws a Sparkfolk card at any size. Small sizes show art + stats, large sizes
## add rules text, keyword reminders and flavor. The battle scene also uses the
## overlay fields (damage, shield, frozen, highlight) for creatures in lanes.

signal clicked(view: CardView, button: int)
signal hovered(view: CardView, on: bool)

const FOIL_SHADER := preload("res://assets/shaders/foil.gdshader")
const SPARK := Color("f2c14e")
const POWER_COL := Color("d9653b")
const HEALTH_COL := Color("4f9a4a")

var card: CardDef
var foil: bool = false
var face_down: bool = false
var back_style: String = ""
var highlight: Color = Color(0, 0, 0, 0)
var dim: bool = false
var glow: float = 0.0             # rarity glow intensity (pack reveal)
var power_override: int = -999
var health_override: int = -999   # max health incl. buffs
var damage: int = 0
var shielded: bool = false
var frozen: bool = false
var badge: String = ""            # small corner text, e.g. "x3" or "NEW"
var badge_color: Color = UIKit.ROSE
var silhouette: bool = false      # unowned card in the binder
var instance_uid: int = -1


static func make(c: CardDef, w: float, p_foil: bool = false) -> CardView:
	var v := CardView.new()
	v.card = c
	v.foil = p_foil
	v.shielded = c.has_keyword("shield") if c else false
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
	if silhouette:
		_rounded(Rect2(0, 0, w, h), r, Color("cfc3ab"))
		_rounded(Rect2(3, 3, w - 6, h - 6), r - 2, Color("e4d9c2"))
		var fs0 := clampi(int(w * 0.09), 8, 16)
		draw_string(font, Vector2(0, h * 0.5), "#%d" % card.collector_number, HORIZONTAL_ALIGNMENT_CENTER, w, fs0, Color("a89a80"))
		draw_string(font, Vector2(4, h * 0.5 + fs0 + 4), card.name, HORIZONTAL_ALIGNMENT_CENTER, w - 8, maxi(7, fs0 - 3), Color("a89a80"))
		return
	var frame := UIKit.card_color(card)
	# Outer border + colored frame
	_rounded(Rect2(0, 0, w, h), r, Color("2a211c"))
	var pad := maxf(2.0, w * 0.035)
	_rounded(Rect2(pad, pad, w - pad * 2, h - pad * 2), r * 0.7, frame)
	var inner_x := pad * 2.0
	var inner_w := w - pad * 4.0
	# Name bar, leaving room for the cost gem on the left
	var name_h := maxf(10.0, w * 0.13)
	var gem_r := name_h * 0.62
	var name_x := inner_x + gem_r * 1.5
	_rounded(Rect2(name_x, pad * 2.0, inner_x + inner_w - name_x, name_h), 3, UIKit.PAPER)
	if w >= 70:
		var name_fs := clampi(int(w * 0.075), 7, 17)
		var room := inner_x + inner_w - name_x - 6
		while name_fs > 7 and font.get_string_size(card.name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs).x > room:
			name_fs -= 1
		draw_string(font, Vector2(name_x + 4, pad * 2.0 + name_h * 0.5 + name_fs * 0.36), card.name,
				HORIZONTAL_ALIGNMENT_LEFT, room, name_fs, UIKit.INK)
	# Art
	var art_y := pad * 2.0 + name_h + pad
	var art_h := inner_w / 1.5
	var art_rect := Rect2(inner_x, art_y, inner_w, art_h)
	draw_rect(art_rect.grow(1), Color("2a211c"))
	draw_texture_rect(CardArt.get_texture(card), art_rect, false, Color(0.55, 0.55, 0.55) if dim else Color.WHITE)
	# Cost gem drawn over the name bar corner
	_spark_gem(Vector2(inner_x + gem_r * 0.6, pad * 2.0 + name_h * 0.5), gem_r, str(card.cost))
	var type_y := art_y + art_h + pad
	var type_h := maxf(8.0, w * 0.1)
	var small_fs := clampi(int(w * 0.06), 7, 14)
	if w >= 110:
		_rounded(Rect2(inner_x, type_y, inner_w, type_h), 2, UIKit.PAPER_DARK)
		draw_string(font, Vector2(inner_x + 3, type_y + type_h * 0.5 + small_fs * 0.36), card.type_line(),
				HORIZONTAL_ALIGNMENT_LEFT, inner_w - 16, small_fs, UIKit.INK)
		_rarity_gem(Vector2(inner_x + inner_w - 7, type_y + type_h * 0.5), type_h * 0.3)
		var box_y := type_y + type_h + pad
		var box_h := h - box_y - pad * 2.0
		_rounded(Rect2(inner_x, box_y, inner_w, box_h), 3, Color("fbf4e2"))
		var text_fs := clampi(int(w * 0.058), 8, 14)
		var line_h := text_fs + 2
		var max_lines := int((box_h - 4) / line_h)
		var y := box_y + text_fs + 2
		var used := _text_block(font, card.text, Vector2(inner_x + 4, y), inner_w - 8, text_fs, max_lines, UIKit.INK)
		y += used * line_h
		if w >= 180:
			var rem := card.reminder_text()
			if rem != "" and used < max_lines:
				used += _text_block(font, rem, Vector2(inner_x + 4, y + 2), inner_w - 8, text_fs - 2, max_lines - used, UIKit.INK_SOFT)
				y += _lines_for(font, rem, inner_w - 8, text_fs - 2) * (text_fs) + 2
			if card.flavor != "" and y + text_fs < box_y + box_h - 2:
				var left := int((box_y + box_h - y - 2) / (text_fs + 1))
				if left > 0:
					draw_multiline_string(font, Vector2(inner_x + 4, y + 4), card.flavor, HORIZONTAL_ALIGNMENT_LEFT,
							inner_w - 8, text_fs - 1, left, Color(UIKit.INK_SOFT, 0.8))
	else:
		var kws: PackedStringArray = []
		for k in card.keywords:
			kws.append(CardDef.KEYWORD_NAMES.get(k, k).substr(0, 2))
		if not card.effects.is_empty() and card.is_creature():
			kws.append("*")
		if not kws.is_empty():
			draw_string(font, Vector2(inner_x + 1, type_y + small_fs), " ".join(kws), HORIZONTAL_ALIGNMENT_LEFT, inner_w, small_fs, Color("fffaf0"))
		if card.is_spell():
			draw_string(font, Vector2(inner_x, h - pad * 3), "Spell", HORIZONTAL_ALIGNMENT_CENTER, inner_w, small_fs, Color("fffaf0"))
	# Power (left) and health (right)
	if card.is_creature():
		var pw := card.power if power_override == -999 else power_override
		var mh := card.health if health_override == -999 else health_override
		var hp := mh - damage
		var br := clampf(w * 0.11, 6.0, 20.0)
		var fs := clampi(int(br * 1.15), 8, 22)
		var pc := Vector2(pad + br * 0.9, h - pad - br * 0.9)
		var hc := Vector2(w - pad - br * 0.9, h - pad - br * 0.9)
		draw_circle(pc, br + 1.5, Color("2a211c"))
		draw_circle(pc, br, POWER_COL)
		draw_string(font, Vector2(pc.x - br, pc.y + fs * 0.36), str(pw), HORIZONTAL_ALIGNMENT_CENTER, br * 2, fs,
				Color("fff3b0") if pw > card.power else Color.WHITE)
		if shielded:
			draw_circle(hc, br + 5.0, Color("9fe4ff", 0.85))
		draw_circle(hc, br + 1.5, Color("2a211c"))
		draw_circle(hc, br, HEALTH_COL if damage == 0 else Color("c0392b"))
		draw_string(font, Vector2(hc.x - br, hc.y + fs * 0.36), str(hp), HORIZONTAL_ALIGNMENT_CENTER, br * 2, fs,
				Color("fff3b0") if mh > card.health and damage == 0 else Color.WHITE)
	if w < 110:
		_rarity_gem(Vector2(w * 0.5, h - pad * 3.0), maxf(2.0, w * 0.035))
	if frozen:
		_rounded(Rect2(0, 0, w, h), r, Color(0.6, 0.85, 1.0, 0.45))
		draw_string(font, Vector2(0, h * 0.42), "❄", HORIZONTAL_ALIGNMENT_CENTER, w, int(w * 0.3), Color.WHITE)
	if dim:
		_rounded(Rect2(0, 0, w, h), r, Color(0.1, 0.08, 0.12, 0.35))
	if badge != "":
		var bfs := clampi(int(w * 0.09), 9, 16)
		var bw2 := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs).x + 8
		_rounded(Rect2(w - bw2 + 4, -6, bw2, bfs + 6), 4, badge_color)
		draw_string(font, Vector2(w - bw2 + 8, bfs - 3), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, bfs, Color.WHITE)


func _text_block(font: Font, txt: String, at: Vector2, width: float, fs: int, max_lines: int, col: Color) -> int:
	if max_lines <= 0 or txt == "":
		return 0
	draw_multiline_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, width, fs, max_lines, col)
	return mini(max_lines, _lines_for(font, txt, width, fs))


func _lines_for(font: Font, txt: String, width: float, fs: int) -> int:
	return int(font.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, width, fs).y / font.get_height(fs) + 0.5)


func _spark_gem(c: Vector2, rad: float, txt: String) -> void:
	draw_circle(c, rad + 1.5, Color("2a211c"))
	draw_circle(c, rad, SPARK)
	draw_circle(c + Vector2(-rad * 0.3, -rad * 0.3), rad * 0.35, Color(1, 1, 1, 0.45))
	var fs := maxi(7, int(rad * 1.3))
	draw_string(get_theme_default_font(), Vector2(c.x - rad, c.y + fs * 0.36), txt, HORIZONTAL_ALIGNMENT_CENTER, rad * 2, fs, UIKit.INK)


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


func _rarity_gem(center: Vector2, rad: float) -> void:
	var c: Color = UIKit.RARITY_COLORS.get(card.rarity, Color.WHITE)
	var pts := PackedVector2Array([center + Vector2(0, -rad * 1.3), center + Vector2(rad, 0), center + Vector2(0, rad * 1.3), center + Vector2(-rad, 0)])
	draw_colored_polygon(pts, Color("2a211c"))
	var pts2 := PackedVector2Array([center + Vector2(0, -rad), center + Vector2(rad * 0.7, 0), center + Vector2(0, rad), center + Vector2(-rad * 0.7, 0)])
	draw_colored_polygon(pts2, c)
