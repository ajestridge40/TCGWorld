class_name WorldMap
extends RefCounted
## A tile map built from data/maps/*.json. Handles collision + interactables
## and paints the whole map into pixel-art Images (ground + overlay) once,
## so no tileset assets are required. Real tilesets can replace `render()` later.

const T := 16

var id: String
var w: int
var h: int
var outdoor: bool = true
var tiles: Array = []          # [y][x] -> tile name
var blocked: Dictionary = {}   # Vector2i -> true
var interact: Dictionary = {}  # Vector2i -> { "kind", ... }
var doors: Array = []          # { pos, to, spawn }
var data: Dictionary
var _rng := RandomNumberGenerator.new()


func load_map(d: Dictionary) -> void:
	data = d
	id = d.get("id", "")
	w = int(d["w"])
	h = int(d["h"])
	outdoor = d.get("outdoor", true)
	tiles = []
	for y in h:
		var row: Array = []
		for x in w:
			row.append(d.get("base", "grass"))
		tiles.append(row)
	for r in d.get("rects", []):
		_fill(r["r"], r["tile"])
	if d.get("border", "") == "tree":
		for x in w:
			_block(Vector2i(x, 0))
			_block(Vector2i(x, h - 1))
		for y in h:
			_block(Vector2i(0, y))
			_block(Vector2i(w - 1, y))
	for y in h:
		for x in w:
			if tiles[y][x] in ["water", "wall"]:
				_block(Vector2i(x, y))
	for t in d.get("trees", []):
		_block(Vector2i(t[0], t[1]))
	for b in d.get("buildings", []):
		var r: Array = b["r"]
		for y in range(r[1], r[1] + r[3]):
			for x in range(r[0], r[0] + r[2]):
				_block(Vector2i(x, y))
		var door := Vector2i(b["door"][0], b["door"][1])
		if b.has("locked"):
			interact[door] = { "kind": "text", "text": b["locked"] }
		else:
			blocked.erase(door)
			doors.append({ "pos": door, "to": b["to"], "spawn": b["spawn"] })
	for dd in d.get("doors", []):
		var p := Vector2i(dd["pos"][0], dd["pos"][1])
		blocked.erase(p)
		tiles[p.y][p.x] = data.get("base", "wood")
		doors.append({ "pos": p, "to": dd["to"], "spawn": dd["spawn"] })
	for dec in d.get("decor", []):
		var cells := _decor_cells(dec)
		var walkable: bool = dec["type"] in ["rug", "poster", "window", "pack_wall"]
		for c in cells:
			if not walkable:
				_block(c)
			if dec.has("action"):
				interact[c] = { "kind": "action", "action": dec["action"] }
			elif dec.has("text"):
				interact[c] = { "kind": "text", "text": dec["text"] }


func _decor_cells(dec: Dictionary) -> Array:
	var out: Array = []
	if dec.has("r"):
		var r: Array = dec["r"]
		for y in range(r[1], r[1] + r[3]):
			for x in range(r[0], r[0] + r[2]):
				out.append(Vector2i(x, y))
	elif dec.has("pos"):
		out.append(Vector2i(dec["pos"][0], dec["pos"][1]))
	return out


func _fill(r: Array, tile: String) -> void:
	for y in range(r[1], r[1] + r[3]):
		for x in range(r[0], r[0] + r[2]):
			if x >= 0 and y >= 0 and x < w and y < h:
				tiles[y][x] = tile


func _block(p: Vector2i) -> void:
	blocked[p] = true


func is_blocked(p: Vector2i) -> bool:
	if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
		return true
	return blocked.has(p)


func door_at(p: Vector2i) -> Dictionary:
	for d in doors:
		if d["pos"] == p:
			return d
	return {}


func tile(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= w or y >= h:
		return ""
	return tiles[y][x]


# ================================================================ rendering

func render() -> Array:
	var ground := Image.create(w * T, h * T, false, Image.FORMAT_RGBA8)
	var overlay := Image.create(w * T, h * T, false, Image.FORMAT_RGBA8)
	_rng.seed = hash(id)
	for y in h:
		for x in w:
			_paint_tile(ground, x, y, tiles[y][x])
	if data.get("border", "") == "tree":
		for x in w:
			_tree(ground, overlay, x, 0)
			_tree(ground, overlay, x, h - 1)
		for y in range(1, h - 1):
			_tree(ground, overlay, 0, y)
			_tree(ground, overlay, w - 1, y)
	for dec in data.get("decor", []):
		_paint_decor(ground, overlay, dec)
	for b in data.get("buildings", []):
		_building(ground, b)
	var trees: Array = data.get("trees", []).duplicate()
	trees.sort_custom(func(a, b): return a[1] < b[1])
	for t in trees:
		_tree(ground, overlay, t[0], t[1])
	return [ground, overlay]


func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		if c.a >= 1.0:
			img.set_pixel(x, y, c)
		else:
			img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


func _rect(img: Image, x: int, y: int, rw: int, rh: int, c: Color) -> void:
	for yy in range(y, y + rh):
		for xx in range(x, x + rw):
			_px(img, xx, yy, c)


func _circle(img: Image, cx: float, cy: float, r: float, c: Color) -> void:
	for yy in range(int(cy - r) - 1, int(cy + r) + 2):
		for xx in range(int(cx - r) - 1, int(cx + r) + 2):
			if Vector2(xx + 0.5 - cx, yy + 0.5 - cy).length() <= r:
				_px(img, xx, yy, c)


func _paint_tile(img: Image, tx: int, ty: int, kind: String) -> void:
	var ox := tx * T
	var oy := ty * T
	match kind:
		"grass", "flowers":
			_rect(img, ox, oy, T, T, Color("7fb35a"))
			for i in 7:
				var c: Color = [Color("8cc063"), Color("6fa14d"), Color("94c96b")][i % 3]
				var gx := ox + _rng.randi_range(0, T - 1)
				var gy := oy + _rng.randi_range(0, T - 2)
				_px(img, gx, gy, c)
				_px(img, gx, gy + 1, c)
			if kind == "flowers" or _rng.randf() < 0.04:
				for i in (4 if kind == "flowers" else 1):
					var fc: Color = [Color("ffd6e0"), Color("ffe066"), Color("f4a6c0"), Color.WHITE, Color("b5a8ff")][_rng.randi_range(0, 4)]
					var fx := ox + _rng.randi_range(2, T - 3)
					var fy := oy + _rng.randi_range(2, T - 3)
					_px(img, fx, fy, fc)
					_px(img, fx + 1, fy, fc)
					_px(img, fx, fy + 1, fc)
					_px(img, fx + 1, fy + 1, fc.darkened(0.15))
		"path":
			_rect(img, ox, oy, T, T, Color("d9b98a"))
			for i in 5:
				_px(img, ox + _rng.randi_range(0, T - 1), oy + _rng.randi_range(0, T - 1), Color("c4a274"))
			_px(img, ox + _rng.randi_range(1, T - 2), oy + _rng.randi_range(1, T - 2), Color("e8cfa6"))
			# Soft edges into grass
			for e in [[0, -1], [0, 1], [-1, 0], [1, 0]]:
				var n := tile(tx + e[0], ty + e[1])
				if n in ["grass", "flowers"]:
					for i in T:
						var ex: int = ox + (i if e[0] == 0 else (0 if e[0] < 0 else T - 1))
						var ey: int = oy + (i if e[1] == 0 else (0 if e[1] < 0 else T - 1))
						_px(img, ex, ey, Color("b8a070") if _rng.randf() < 0.6 else Color("8cb860"))
		"sand":
			_rect(img, ox, oy, T, T, Color("ecd9a0"))
			for i in 4:
				_px(img, ox + _rng.randi_range(0, T - 1), oy + _rng.randi_range(0, T - 1), Color("dcc68a"))
		"water":
			_rect(img, ox, oy, T, T, Color("5aa0d8"))
			for i in 3:
				var wx := ox + _rng.randi_range(0, T - 5)
				var wy := oy + _rng.randi_range(1, T - 2)
				_rect(img, wx, wy, 4, 1, Color("8cc4ec"))
			if tile(tx, ty - 1) != "water":
				_rect(img, ox, oy, T, 2, Color("a8d8f0"))
		"wood":
			_rect(img, ox, oy, T, T, Color("b07a4a"))
			for row in 4:
				var yy := oy + row * 4
				_rect(img, ox, yy + 3, T, 1, Color("8c5e36"))
				var seam := ox + ((tx * 7 + row * 5) % T)
				_px(img, seam, yy, Color("8c5e36"))
				_px(img, seam, yy + 1, Color("8c5e36"))
				_px(img, seam, yy + 2, Color("8c5e36"))
			_px(img, ox + _rng.randi_range(0, T - 1), oy + _rng.randi_range(0, T - 1), Color("c08a58"))
		"wall":
			var below := tile(tx, ty + 1)
			_rect(img, ox, oy, T, T, Color("e8d5ae"))
			for i in range(0, T, 4):
				_rect(img, ox + i, oy, 2, T, Color("dcc69c"))
			if below != "wall" and below != "":
				_rect(img, ox, oy + T - 4, T, 4, Color("6b4a32"))
				_rect(img, ox, oy + T - 4, T, 1, Color("8a6240"))
			if tile(tx, ty - 1) == "":
				_rect(img, ox, oy, T, 3, Color("4a3222"))
		"rug":
			_rect(img, ox, oy, T, T, Color("b8505a"))
			_rect(img, ox + 2, oy + 2, T - 4, T - 4, Color("c86a6a"))
			_px(img, ox + 7, oy + 7, Color("f2c14e"))
			_px(img, ox + 8, oy + 8, Color("f2c14e"))
		_:
			_rect(img, ox, oy, T, T, Color("7fb35a"))


func _tree(ground: Image, overlay: Image, tx: int, ty: int) -> void:
	var ox := tx * T
	var oy := ty * T
	var r := _rng.randf_range(8.0, 10.0)
	var tint := _rng.randf_range(-0.06, 0.06)
	_circle(ground, ox + 8, oy + 14, 7, Color(0, 0, 0, 0.18))
	_rect(ground, ox + 6, oy + 6, 4, 9, Color("6b4a32"))
	_rect(ground, ox + 6, oy + 6, 1, 9, Color("8a6240"))
	var base := Color("3f7d3a").lightened(tint) if tint > 0 else Color("3f7d3a").darkened(-tint)
	_circle(overlay, ox + 8, oy + 1, r, base.darkened(0.25))
	_circle(overlay, ox + 7, oy, r - 1.5, base)
	_circle(overlay, ox + 5, oy - 3, r * 0.45, base.lightened(0.18))
	if _rng.randf() < 0.3:
		for i in 3:
			_px(overlay, ox + _rng.randi_range(2, 13), oy + _rng.randi_range(-6, 6), Color("e85d5d"))


func _building(img: Image, b: Dictionary) -> void:
	var r: Array = b["r"]
	var x0: int = r[0] * T
	var y0: int = r[1] * T
	var bw: int = r[2] * T
	var bh: int = r[3] * T
	var style: String = b.get("style", "home")
	var roof: Color = { "home": Color("c0504d"), "shop": Color("3f8f8a"), "center": Color("6aa84f"),
		"bakery": Color("e69a4c"), "cottage": Color("b57ac8") }.get(style, Color("c0504d"))
	var wall: Color = { "shop": Color("f3e2b8"), "center": Color("e6d8c0"), "bakery": Color("f6e7d0") }.get(style, Color("efe0c4"))
	var wall_h := 2 * T + 4
	var roof_h := bh - wall_h
	# Shadow
	_rect(img, x0 + 3, y0 + bh - 2, bw, 4, Color(0, 0, 0, 0.2))
	# Walls
	_rect(img, x0, y0 + roof_h, bw, wall_h, wall)
	for xx in range(x0, x0 + bw, 8):
		_rect(img, xx, y0 + roof_h, 1, wall_h, wall.darkened(0.08))
	_rect(img, x0, y0 + bh - 3, bw, 3, wall.darkened(0.3))
	# Roof with overhang and shingles
	_rect(img, x0 - 3, y0, bw + 6, roof_h + 3, roof.darkened(0.3))
	_rect(img, x0 - 2, y0, bw + 4, roof_h, roof)
	for row in range(0, roof_h, 5):
		var off := (row / 5) % 2 * 4
		for xx in range(x0 - 2 + off, x0 + bw + 2, 8):
			_rect(img, xx, y0 + row + 4, 1, 1, roof.darkened(0.2))
		_rect(img, x0 - 2, y0 + row + 4, bw + 4, 1, roof.darkened(0.12))
	_rect(img, x0 - 2, y0, bw + 4, 2, roof.lightened(0.2))
	# Chimney for homes
	if style in ["home", "cottage", "bakery"]:
		_rect(img, x0 + bw - 18, y0 - 6, 7, 10, Color("8a6a5a"))
		_rect(img, x0 + bw - 19, y0 - 7, 9, 2, Color("6a4a3a"))
	# Door
	var dx: int = b["door"][0] * T
	var dy: int = y0 + bh - 22
	_rect(img, dx + 2, dy, 12, 22, Color("4a3222"))
	_rect(img, dx + 3, dy + 1, 10, 21, Color("8a5a36") if not b.has("locked") else Color("7a5a46"))
	_px(img, dx + 11, dy + 12, UIKit.GOLD)
	_rect(img, dx + 1, dy + 21, 14, 1, Color("4a3222"))
	# Windows either side of the door
	var wy := y0 + roof_h + 8
	for wx in range(x0 + 6, x0 + bw - 14, 24):
		if absi(wx - dx) < 20:
			continue
		_rect(img, wx, wy, 14, 12, Color("4a3222"))
		_rect(img, wx + 1, wy + 1, 12, 10, Color("ffe8a3") if style == "shop" else Color("9fd3ec"))
		_rect(img, wx + 7, wy + 1, 1, 10, Color("4a3222"))
		_rect(img, wx + 1, wy + 6, 12, 1, Color("4a3222"))
		_rect(img, wx - 1, wy + 12, 16, 2, Color("8a6240"))
		if style != "shop":
			_px(img, wx + 2, wy + 13, Color("e85d5d"))
			_px(img, wx + 6, wy + 13, Color("ffd166"))
			_px(img, wx + 11, wy + 13, Color("e85d5d"))
	# Shop: striped awning + card sign
	if style == "shop":
		var ay := y0 + roof_h - 2
		for xx in range(x0, x0 + bw, 8):
			_rect(img, xx, ay, 4, 7, Color("f6ead0"))
			_rect(img, xx + 4, ay, 4, 7, Color("3f8f8a"))
		for xx in range(x0, x0 + bw, 4):
			_px(img, xx + 1, ay + 7, Color("2f6f6a"))
		var sx := x0 + bw / 2 - 26
		var sy := y0 + 6
		_rect(img, sx, sy, 52, 16, Color("4a3222"))
		_rect(img, sx + 1, sy + 1, 50, 14, Color("6b4a32"))
		for i in 3:
			var cx := sx + 10 + i * 12
			_rect(img, cx, sy + 3, 8, 10, Color("2a211c"))
			_rect(img, cx + 1, sy + 4, 6, 8, [Color("d9653b"), Color("e9b44c"), Color("3d8fc4")][i])
			_rect(img, cx + 2, sy + 5, 4, 3, Color("fff3b0"))
	elif style == "bakery":
		var sx2 := dx - 10
		_rect(img, sx2, y0 + roof_h - 4, 36, 6, Color("f6ead0"))
		_circle(img, sx2 + 18, y0 + roof_h - 1, 3, Color("c08a58"))
	elif style == "center":
		_rect(img, x0 + bw / 2 - 20, y0 + 8, 40, 10, Color("f6ead0"))
		_rect(img, x0 + bw / 2 - 19, y0 + 9, 38, 8, Color("e9b44c"))
		# Boarded window: it's under repair.
		_rect(img, x0 + 10, y0 + roof_h + 10, 16, 2, Color("8a6240"))
		_rect(img, x0 + 10, y0 + roof_h + 14, 16, 2, Color("8a6240"))


func _paint_decor(img: Image, overlay: Image, dec: Dictionary) -> void:
	var cells := _decor_cells(dec)
	if cells.is_empty():
		return
	var p: Vector2i = cells[0]
	var ox := p.x * T
	var oy := p.y * T
	var rw := T
	var rh := T
	if dec.has("r"):
		rw = int(dec["r"][2]) * T
		rh = int(dec["r"][3]) * T
	match dec["type"]:
		"lamp":
			_rect(img, ox + 7, oy + 2, 2, 13, Color("3a3040"))
			_rect(img, ox + 5, oy + 14, 6, 2, Color("3a3040"))
			_rect(overlay, ox + 5, oy - 4, 6, 6, Color("3a3040"))
			_rect(overlay, ox + 6, oy - 3, 4, 4, Color("ffe08a"))
		"bench":
			_rect(img, ox + 1, oy + 6, 14, 3, Color("8a5a36"))
			_rect(img, ox + 1, oy + 10, 14, 3, Color("a06a40"))
			_rect(img, ox + 2, oy + 13, 2, 3, Color("4a3222"))
			_rect(img, ox + 12, oy + 13, 2, 3, Color("4a3222"))
		"sign":
			_rect(img, ox + 7, oy + 8, 2, 8, Color("6b4a32"))
			_rect(img, ox + 2, oy + 2, 12, 8, Color("4a3222"))
			_rect(img, ox + 3, oy + 3, 10, 6, Color("c08a58"))
			_rect(img, ox + 4, oy + 5, 8, 1, Color("6b4a32"))
		"mailbox":
			_rect(img, ox + 7, oy + 8, 2, 8, Color("6b4a32"))
			_rect(img, ox + 4, oy + 3, 8, 6, Color("3d5a80"))
			_rect(img, ox + 11, oy + 2, 1, 4, Color("e85d5d"))
		"fountain":
			var c := Vector2(ox + rw / 2.0, oy + rh / 2.0)
			_circle(img, c.x, c.y + 2, rw / 2.0, Color(0, 0, 0, 0.2))
			_circle(img, c.x, c.y, rw / 2.0 - 1, Color("a8a29a"))
			_circle(img, c.x, c.y, rw / 2.0 - 4, Color("5aa0d8"))
			_circle(img, c.x, c.y, 5, Color("a8a29a"))
			_circle(overlay, c.x, c.y - 6, 3, Color("bfe4f8"))
			_rect(overlay, int(c.x) - 1, int(c.y) - 10, 2, 10, Color("8cc4ec"))
		"pack_wall":
			for i in range(0, rw, 8):
				for row in 2:
					var col: Color = [Color("d9653b"), Color("3d8fc4"), Color("4f9a4a"), Color("e3be4f"), Color("6e55a0")][(i / 8 + row) % 5]
					_rect(img, ox + i + 1, oy + 4 + row * 13, 6, 9, col)
					_rect(img, ox + i + 2, oy + 5 + row * 13, 4, 2, Color(1, 1, 1, 0.5))
				_rect(img, ox + i, oy + 13, 8, 2, Color("6b4a32"))
				_rect(img, ox + i, oy + 26, 8, 2, Color("6b4a32"))
		"poster":
			_rect(img, ox + 2, oy + 2, 12, 14, Color("2a211c"))
			_rect(img, ox + 3, oy + 3, 10, 12, [Color("f7b267"), Color("6fa8dc"), Color("b5a8ff")][(p.x + p.y) % 3])
			_circle(img, ox + 8, oy + 8, 3, Color("fff3b0"))
		"board":
			_rect(img, ox, oy + 1, 16, 14, Color("6b4a32"))
			_rect(img, ox + 1, oy + 2, 14, 12, Color("c8a070"))
			_rect(img, ox + 2, oy + 3, 5, 6, Color.WHITE)
			_rect(img, ox + 8, oy + 4, 6, 5, Color("ffe066"))
			_rect(img, ox + 4, oy + 9, 6, 4, Color("ffd6e0"))
		"counter", "case":
			_rect(img, ox, oy + 2, rw, rh - 2, Color("6b4a32"))
			_rect(img, ox, oy, rw, 5, Color("a06a40"))
			_rect(img, ox, oy + 5, rw, 1, Color("4a3222"))
			if dec["type"] == "case":
				_rect(img, ox + 2, oy + 6, rw - 4, rh - 9, Color("bfe4f8"))
				for i in range(4, rw - 8, 10):
					_rect(img, ox + i, oy + 8, 6, 6, [Color("f2c14e"), Color("ff86d6"), Color("9fd6e0")][(i / 10) % 3])
		"register":
			_rect(img, ox + 3, oy - 2, 10, 8, Color("3a3040"))
			_rect(img, ox + 4, oy - 1, 8, 3, Color("9fe0a0"))
			_rect(img, ox + 2, oy + 6, 12, 2, Color("4a3222"))
		"table":
			_rect(img, ox + 2, oy + rh - 4, rw - 4, 4, Color(0, 0, 0, 0.2))
			_rect(img, ox, oy, rw, rh - 2, Color("6b4a32"))
			_rect(img, ox + 2, oy + 2, rw - 4, rh - 6, Color("3f7d5a"))
			for i in 4:
				_rect(img, ox + 6 + i * 9, oy + 6 + (i % 2) * 8, 6, 8, Color("f6ead0"))
				_rect(img, ox + 7 + i * 9, oy + 7 + (i % 2) * 8, 4, 3, UIKit.CARD_COLORS.values()[i])
		"plant":
			_rect(img, ox + 4, oy + 9, 8, 7, Color("b5651d"))
			_circle(img, ox + 8, oy + 6, 5, Color("4f9a4a"))
			_circle(img, ox + 6, oy + 4, 2, Color("6aa84f"))
		"coffee":
			_rect(img, ox + 1, oy + 4, 14, 10, Color("8a5a36"))
			_rect(img, ox + 4, oy - 2, 7, 8, Color("3a3040"))
			_rect(img, ox + 5, oy + 1, 5, 3, Color("6b3d1f"))
		"bed":
			_rect(img, ox, oy, rw, rh, Color("6b4a32"))
			_rect(img, ox + 2, oy + 2, rw - 4, rh - 4, Color("6fa8dc"))
			_rect(img, ox + 4, oy + 3, rw - 8, 7, Color("f6ead0"))
			for i in range(0, rw - 4, 4):
				_rect(img, ox + 2 + i, oy + 14, 2, rh - 16, Color("5a8fc0"))
		"desk":
			_rect(img, ox, oy, rw, rh, Color("8a5a36"))
			_rect(img, ox + 2, oy + 1, 8, 6, Color("3d8fc4"))
			_rect(img, ox + 14, oy + 2, 10, 4, Color("f6ead0"))
		"trophy_shelf":
			_rect(img, ox, oy + rh - 12, rw, 3, Color("6b4a32"))
			_rect(img, ox, oy + rh - 26, rw, 3, Color("6b4a32"))
			var n := Game.trophies.size()
			for i in mini(n, 5):
				var tx := ox + 4 + i * 9
				_rect(img, tx, oy + rh - 20, 6, 5, UIKit.GOLD)
				_rect(img, tx + 2, oy + rh - 15, 2, 3, UIKit.GOLD.darkened(0.2))
			if n == 0:
				_rect(img, ox + 8, oy + rh - 18, 6, 6, Color("d8ccb4"))
		"window":
			_rect(img, ox + 1, oy + 2, 14, 12, Color("4a3222"))
			_rect(img, ox + 2, oy + 3, 12, 10, Color("9fd3ec"))
			_rect(img, ox + 7, oy + 3, 1, 10, Color("4a3222"))
