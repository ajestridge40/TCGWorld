class_name CharacterSprite
extends RefCounted
## Generates 16x16 pixel characters from a "look" dictionary (skin, hair,
## shirt, pants, + optional beard/glasses/small). Frames are cached.
## dir: 0 down, 1 up, 2 side (faces left; flip for right). frame: 0 idle, 1-2 walk.

const PLAYER_LOOK := { "skin": "#f0c8a8", "hair": "#5a3a22", "shirt": "#e9b44c", "pants": "#3d5a80" }

static var _cache: Dictionary = {}


static func texture(look: Dictionary, dir: int, frame: int) -> Texture2D:
	var key := "%s|%d|%d" % [str(look), dir, frame]
	if not _cache.has(key):
		_cache[key] = ImageTexture.create_from_image(image(look, dir, frame))
	return _cache[key]


static func image(look: Dictionary, dir: int, frame: int) -> Image:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var skin := Color(look.get("skin", "#f0c8a8"))
	var hair := Color(look.get("hair", "#5a3a22"))
	var shirt := Color(look.get("shirt", "#6aa84f"))
	var pants := Color(look.get("pants", "#3d5a80"))
	var outline := Color("2a211c")
	var small: bool = look.get("small", false)
	var oy := 2 if small else 0
	var bob := 1 if frame == 1 or frame == 2 else 0
	# Shadow
	for x in range(4, 12):
		img.set_pixel(x, 15, Color(0, 0, 0, 0.25))
	# Legs
	var leg_y := 12 + (1 if small else 0)
	var l_off := 0
	var r_off := 0
	if frame == 1:
		l_off = -1
	elif frame == 2:
		r_off = -1
	for y in range(leg_y, 15):
		_p(img, 6, y + (l_off if y == 14 else 0), pants)
		_p(img, 9, y + (r_off if y == 14 else 0), pants)
		if dir != 2:
			_p(img, 5, y, pants.darkened(0.15))
			_p(img, 10, y, pants.darkened(0.15))
	_p(img, 6, 14 + l_off, outline)
	_p(img, 9, 14 + r_off, outline)
	# Body
	var body_top := 8 + oy - bob
	for y in range(body_top, leg_y):
		for x in range(4, 12):
			_p(img, x, y, shirt if x != 4 and x != 11 else shirt.darkened(0.2))
	# Arms
	for y in range(body_top + 1, body_top + 4):
		if dir != 2:
			_p(img, 3, y, shirt.darkened(0.2))
			_p(img, 12, y, shirt.darkened(0.2))
		_p(img, 3 if dir != 2 else 7, body_top + 4, skin)
		if dir != 2:
			_p(img, 12, body_top + 4, skin)
	# Head
	var head_top := 1 + oy - bob
	for y in range(head_top, head_top + 7):
		for x in range(4, 12):
			var edge := (y == head_top or y == head_top + 6) and (x == 4 or x == 11)
			if not edge:
				_p(img, x, y, skin)
	# Hair
	match dir:
		0:
			for x in range(4, 12):
				_p(img, x, head_top, hair)
				_p(img, x, head_top + 1, hair)
			_p(img, 4, head_top + 2, hair)
			_p(img, 11, head_top + 2, hair)
			_p(img, 4, head_top + 3, hair)
			_p(img, 11, head_top + 3, hair)
			# Eyes
			_p(img, 6, head_top + 4, outline)
			_p(img, 9, head_top + 4, outline)
			_p(img, 5, head_top + 5, Color("ff9a9a"))
			_p(img, 10, head_top + 5, Color("ff9a9a"))
			if look.get("glasses", false):
				for x in [5, 6, 7, 8, 9, 10]:
					_p(img, x, head_top + 3, outline)
			if look.get("beard", false):
				for x in range(5, 11):
					_p(img, x, head_top + 6, hair)
				_p(img, 7, head_top + 7, hair)
				_p(img, 8, head_top + 7, hair)
		1:
			for y in range(head_top, head_top + 6):
				for x in range(4, 12):
					_p(img, x, y, hair if y < head_top + 5 or (x > 4 and x < 11) else skin)
		2:
			for x in range(4, 12):
				_p(img, x, head_top, hair)
			for y in range(head_top, head_top + 5):
				_p(img, 9, y, hair)
				_p(img, 10, y, hair)
				_p(img, 11, y, hair)
			_p(img, 6, head_top + 4, outline)
			_p(img, 5, head_top + 5, Color("ff9a9a"))
			if look.get("glasses", false):
				_p(img, 5, head_top + 3, outline)
				_p(img, 6, head_top + 3, outline)
				_p(img, 7, head_top + 3, outline)
			if look.get("beard", false):
				for x in range(4, 9):
					_p(img, x, head_top + 6, hair)
	# Outline around head sides
	for y in range(head_top + 1, head_top + 6):
		_p(img, 3, y, outline)
		_p(img, 12, y, outline)
	for x in range(5, 11):
		_p(img, x, head_top - 1, outline)
	return img


static func _p(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < 16 and y < 16:
		img.set_pixel(x, y, c)
