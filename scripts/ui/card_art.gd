class_name CardArt
extends RefCounted
## Procedural 48x32 pixel-art illustrations, seeded by card id, so every card
## has a stable, unique placeholder picture until real art is commissioned.
## To use real art, drop a PNG at res://assets/cards/<card_id>.png.

const W := 48
const H := 32

static var _cache: Dictionary = {}

const SKIES := {
	"ember": [Color("f7b267"), Color("f25c54")],
	"tide": [Color("bde0fe"), Color("6fa8dc")],
	"grove": [Color("d8f3a8"), Color("8cc084")],
	"sun": [Color("fff3b0"), Color("f6c66a")],
	"moon": [Color("4b3f72"), Color("1f1d36")],
	"colorless": [Color("e6e1d6"), Color("b8b0a0")],
	"multi": [Color("ffe8a3"), Color("e0a3ff")],
}
const GROUNDS := {
	"ember": Color("8c3b2a"), "tide": Color("2f6690"), "grove": Color("3f7d3a"),
	"sun": Color("9bc25a"), "moon": Color("2e294e"), "colorless": Color("8a8070"), "multi": Color("7a5c8a"),
}


static func get_texture(card: CardDef) -> Texture2D:
	if _cache.has(card.id):
		return _cache[card.id]
	var path := "res://assets/cards/%s.png" % card.id
	var tex: Texture2D
	if ResourceLoader.exists(path):
		tex = load(path)
	else:
		tex = ImageTexture.create_from_image(generate(card))
	_cache[card.id] = tex
	return tex


static func generate(card: CardDef) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var r := RandomNumberGenerator.new()
	r.seed = hash(card.id)
	var col := card.main_color()
	if not SKIES.has(col):
		col = "colorless"
	var sky: Array = SKIES[col]
	for y in H:
		var t := float(y) / H
		var c: Color = sky[0].lerp(sky[1], t)
		for x in W:
			img.set_pixel(x, y, c)
	# Stars for night, sun disc for day.
	if col == "moon":
		for i in 14:
			img.set_pixel(r.randi_range(0, W - 1), r.randi_range(0, 14), Color(1, 1, 0.85, r.randf_range(0.5, 1)))
		_disc(img, 38, 7, 4, Color("f4f1de"))
		_disc(img, 40, 6, 3, sky[0].lerp(sky[1], 0.2))
	else:
		_disc(img, r.randi_range(6, 42), r.randi_range(4, 9), 3, Color(1, 1, 0.85, 0.85))
	# Rolling hills.
	var ground: Color = GROUNDS[col]
	var phase := r.randf() * TAU
	var hill_h := r.randi_range(20, 24)
	for x in W:
		var hy := hill_h + int(sin(x * 0.18 + phase) * 2.0)
		for y in range(hy, H):
			var shade := 1.0 - (y - hy) * 0.02
			img.set_pixel(x, y, Color(ground.r * shade, ground.g * shade, ground.b * shade))
		var far := hy - 4 + int(sin(x * 0.1 + phase * 2.0) * 2.0)
		for y in range(far, hy):
			img.set_pixel(x, y, img.get_pixel(x, y).lerp(ground.lightened(0.25), 0.6))
	if card.is_creature():
		_creature(img, card, r)
	else:
		_spell(img, card, r)
	return img


static func _disc(img: Image, cx: int, cy: int, rad: int, c: Color) -> void:
	for y in range(cy - rad, cy + rad + 1):
		for x in range(cx - rad, cx + rad + 1):
			if x >= 0 and y >= 0 and x < W and y < H and Vector2(x - cx, y - cy).length() <= rad + 0.3:
				img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, c)


static func _creature(img: Image, card: CardDef, r: RandomNumberGenerator) -> void:
	var body: Color = UIKit.card_color(card).lightened(r.randf_range(0.0, 0.3))
	if card.main_color() == "moon":
		body = body.lightened(0.25)
	var dark := body.darkened(0.35)
	var size := clampf(3.0 + card.power * 0.7 + card.health * 0.4, 5.0, 11.0)
	var cx := 24.0 + r.randf_range(-4, 4)
	var ground_y := 26.0
	var flying := card.has_keyword("soar")
	var cy := ground_y - size * 0.8 - (6.0 if flying else 0.0)
	# Shadow
	_ellipse(img, cx, ground_y + 1, size * 0.9, 1.5, Color(0, 0, 0, 0.25))
	# Wings
	if flying:
		_ellipse(img, cx - size * 0.9, cy - 2, size * 0.7, size * 0.35, dark)
		_ellipse(img, cx + size * 0.9, cy - 2, size * 0.7, size * 0.35, dark)
	# Tail
	if r.randf() < 0.5:
		_ellipse(img, cx + size * 0.9, cy + size * 0.2, size * 0.5, size * 0.25, dark)
	# Body + belly
	_ellipse(img, cx, cy, size, size * 0.8, body)
	_ellipse(img, cx, cy + size * 0.25, size * 0.55, size * 0.45, body.lightened(0.35))
	# Ears / horns / leaves by hash
	var style := r.randi_range(0, 3)
	for side in [-1, 1]:
		var ex: float = cx + side * size * 0.55
		var ey: float = cy - size * 0.7
		match style:
			0:  # pointy ears
				for i in 4:
					for j in range(-3 + i, 4 - i):
						var px := int(ex + j * 0.5)
						var py := int(ey - i)
						if px >= 0 and px < W and py >= 0:
							img.set_pixel(px, py, dark)
			1:  # round ears
				_ellipse(img, ex, ey, 2, 2, dark)
			2:  # antlers / sprouts
				for i in 4:
					var py := int(ey - i)
					if py >= 0:
						img.set_pixel(int(ex + side * i * 0.5), py, Color("8a6a3a") if card.main_color() != "grove" else Color("7bc96f"))
			3:
				pass
	# Feet
	if not flying:
		_ellipse(img, cx - size * 0.45, cy + size * 0.75, 1.6, 1.2, dark)
		_ellipse(img, cx + size * 0.45, cy + size * 0.75, 1.6, 1.2, dark)
	# Face
	var eye_y := int(cy - size * 0.15)
	var eye_dx := maxi(2, int(size * 0.35))
	for side in [-1, 1]:
		var ex2: int = int(cx) + side * eye_dx
		img.set_pixel(ex2, eye_y, Color("1d1a22"))
		img.set_pixel(ex2, eye_y + 1, Color("1d1a22"))
		if ex2 + 1 < W:
			img.set_pixel(ex2 + (1 if side < 0 else -1), eye_y, Color.WHITE)
	# Rosy cheeks
	img.set_pixel(int(cx) - eye_dx - 1, eye_y + 2, Color("ff8fa3"))
	img.set_pixel(int(cx) + eye_dx + 1, eye_y + 2, Color("ff8fa3"))
	# Little smile
	img.set_pixel(int(cx), eye_y + 3, Color("1d1a22"))


static func _spell(img: Image, card: CardDef, r: RandomNumberGenerator) -> void:
	var c := UIKit.card_color(card).lightened(0.3)
	var op: String = card.effects[0].get("op", "") if not card.effects.is_empty() else ""
	var cx := 24
	var cy := 15
	match op:
		"damage":
			for i in 10:
				var a := r.randf() * TAU
				var l := r.randf_range(5, 11)
				for s in int(l):
					var px := cx + int(cos(a) * s)
					var py := cy + int(sin(a) * s)
					if px >= 0 and px < W and py >= 0 and py < H:
						img.set_pixel(px, py, Color("ffd166").lerp(Color("ef476f"), s / l))
			_disc(img, cx, cy, 3, Color("fff3b0"))
		"draw":
			_ellipse(img, cx, cy + 2, 9, 6, Color("f6ead0"))
			for x in range(cx - 7, cx + 8):
				img.set_pixel(x, cy + 2, Color("6b4a32"))
			for i in 6:
				img.set_pixel(r.randi_range(cx - 8, cx + 8), r.randi_range(cy - 8, cy - 2), Color(1, 1, 0.7))
		"destroy", "lose_life":
			_disc(img, cx, cy, 7, Color("1f1d36"))
			_disc(img, cx + 3, cy - 2, 6, img.get_pixel(0, 0))
		"bounce", "tap":
			for i in 40:
				var a := i * 0.4
				var rr := 1.0 + i * 0.22
				var px := cx + int(cos(a) * rr)
				var py := cy + int(sin(a) * rr * 0.7)
				if px >= 0 and px < W and py >= 0 and py < H:
					img.set_pixel(px, py, c)
		"token":
			for i in 3:
				_ellipse(img, 12 + i * 12, 22, 4, 3, c.darkened(0.2))
				img.set_pixel(11 + i * 12, 21, Color.BLACK)
				img.set_pixel(13 + i * 12, 21, Color.BLACK)
		_:
			for i in 16:
				var a := i * TAU / 16
				for s in range(4, 9 + (i % 2) * 3):
					var px := cx + int(cos(a) * s)
					var py := cy + int(sin(a) * s)
					if px >= 0 and px < W and py >= 0 and py < H:
						img.set_pixel(px, py, c)
			_disc(img, cx, cy, 4, Color(1, 1, 0.9))
