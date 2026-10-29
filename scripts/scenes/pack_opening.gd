extends Control
## Opens every pack in Game.pending_packs, one at a time.
## Drag across the top of the pack (or press Space) to rip it, then click to
## reveal cards one by one. Rarer cards get longer anticipation, glow, flashes
## and sparkles; the best card is always last.

enum State { PACK, RIPPING, STACK, REVEALING, SUMMARY, BUSY }

const CENTER := Vector2(480, 250)
const PACK_SIZE := Vector2(200, 300)
const BIG_W := 220.0
const ROW_W := 54.0

var state := State.BUSY
var pulls: Array = []
var fresh: Array = []
var reveal_idx := 0
var pack_info := {}
var completion_before := 0.0
var _packs_total := 0

var pack: PackVisual
var stack: Array = []           # face-down CardViews
var revealed: Array = []        # CardViews in the bottom row
var current: CardView
var flash := ColorRect.new()
var title := UIKit.label("", 22, Color("fff3d6"), HORIZONTAL_ALIGNMENT_CENTER)
var prompt := UIKit.label("", 15, Color("e8d5ae"), HORIZONTAL_ALIGNMENT_CENTER)
var rarity_label := UIKit.label("", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
var info_label := UIKit.label("", 14, Color("e8d5ae"), HORIZONTAL_ALIGNMENT_CENTER)
var buttons := HBoxContainer.new()
var skip_btn: Button
var summary_box := Control.new()
var _drag_start := -1.0
var _shake := 0.0
var _world := Control.new()     # everything that shakes


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("241a2b")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(0.5, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color("6b4a5a"))
	g.set_color(1, Color(0.14, 0.1, 0.17, 0))
	gt.gradient = g
	gt.width = 256
	gt.height = 256
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	add_child(_dust())
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)
	title.position = Vector2(0, 14)
	title.size = Vector2(960, 30)
	add_child(title)
	prompt.position = Vector2(0, 422)
	prompt.size = Vector2(960, 24)
	add_child(prompt)
	rarity_label.position = Vector2(0, 46)
	rarity_label.size = Vector2(960, 26)
	rarity_label.add_theme_color_override("font_outline_color", Color("2a211c"))
	rarity_label.add_theme_constant_override("outline_size", 6)
	_world.add_child(rarity_label)
	info_label.position = Vector2(0, 400)
	info_label.size = Vector2(960, 20)
	add_child(info_label)
	summary_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	summary_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(summary_box)
	buttons.position = Vector2(0, 494)
	buttons.size = Vector2(960, 36)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	add_child(buttons)
	skip_btn = UIKit.button("Reveal all", _reveal_all)
	skip_btn.position = Vector2(840, 12)
	skip_btn.visible = false
	add_child(skip_btn)
	flash.color = Color(1, 1, 1, 0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	add_child(ToastLayer.new())
	_packs_total = Game.pending_packs.size()
	_next_pack()


func _dust() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = Vector2(480, 560)
	p.amount = 40
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(500, 10)
	p.direction = Vector2(0, -1)
	p.spread = 15
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 20
	p.initial_velocity_max = 50
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = Color(1, 0.9, 0.7, 0.25)
	return p


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.0)
		_world.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 10.0
	else:
		_world.position = Vector2.ZERO


# ---------------------------------------------------------------- pack

func _next_pack() -> void:
	for c in _world.get_children():
		if c != rarity_label:
			c.queue_free()
	for c in summary_box.get_children():
		c.queue_free()
	for c in buttons.get_children():
		c.queue_free()
	stack.clear()
	revealed.clear()
	current = null
	rarity_label.text = ""
	info_label.text = ""
	if Game.pending_packs.is_empty():
		Game.save_game()
		Game.goto(Game.return_scene)
		return
	pack_info = Game.pending_packs.pop_front()
	var set_info: Dictionary = CardDB.sets[pack_info["set"]]
	var collector: bool = pack_info.get("variant", "") == "collector"
	var done := _packs_total - Game.pending_packs.size()
	title.text = "%s%s   (%d of %d)" % [set_info["name"], " · Collector Booster" if collector else "", done, _packs_total]
	pack = PackVisual.new()
	pack.set_name_text = set_info["name"]
	pack.mascot = set_info.get("mascot", "")
	var pc: Array = set_info.get("pack_colors", ["#e0703c", "#b84a2e"])
	pack.top_color = Color(pc[0])
	pack.bottom_color = Color(pc[1])
	pulls = PackGenerator.open_pack(pack_info["set"], Game.rng, pack_info.get("variant", ""))
	pack.card_count = pulls.size()
	pack.collector = collector
	pack.size = PACK_SIZE
	pack.position = CENTER - PACK_SIZE / 2 + Vector2(0, 400)
	pack.rotation_degrees = -4
	pack.pivot_offset = PACK_SIZE / 2
	_world.add_child(pack)
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(pack, "position", CENTER - PACK_SIZE / 2, 0.6)
	tw.parallel().tween_property(pack, "rotation_degrees", 0.0, 0.6)
	tw.tween_callback(func():
		state = State.PACK
		prompt.text = "Drag across the top of the pack to rip it open  ·  or press Space")
	completion_before = Game.collection.completion(pack_info["set"])
	fresh = []


func _gui_input(ev: InputEvent) -> void:
	if state == State.PACK and pack:
		var local: Vector2 = ev.position - pack.position if ev is InputEventMouse else Vector2.ZERO
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed and local.y >= -10 and local.y <= PACK_SIZE.y * 0.3 and local.x > -30 and local.x < PACK_SIZE.x + 30:
				_drag_start = local.x
			elif not ev.pressed:
				_drag_start = -1.0
				if pack.tear < 1.0:
					create_tween().tween_property(pack, "tear", 0.0, 0.2)
		elif ev is InputEventMouseMotion and _drag_start >= 0.0:
			var prog := clampf((local.x - _drag_start) / (PACK_SIZE.x * 0.75), 0.0, 1.0)
			if prog > pack.tear:
				if int(prog * 10) != int(pack.tear * 10):
					Sfx.play("flip", randf_range(1.2, 1.6), -10.0)
				pack.tear = prog
				pack.wobble = 1.0
			if pack.tear >= 1.0:
				_rip()
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_advance()


func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("interact") or ev.is_action_pressed("ui_accept"):
		if state == State.PACK:
			_rip()
		else:
			_advance()
		get_viewport().set_input_as_handled()


func _advance() -> void:
	if state == State.STACK:
		_reveal_next()
	elif state == State.REVEALING:
		_reveal_next()


func _rip() -> void:
	if state != State.PACK:
		return
	state = State.BUSY
	_drag_start = -1.0
	prompt.text = ""
	pack.tear = 1.0
	Sfx.play("rip")
	fresh = Game.add_pulls(pulls)
	# Top strip flies off.
	var strip := pack.detach_top()
	_world.add_child(strip)
	strip.global_position = pack.global_position
	var tw := create_tween().set_parallel()
	tw.tween_property(strip, "position", strip.position + Vector2(260, -220), 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(strip, "rotation_degrees", 70.0, 0.7)
	tw.tween_property(strip, "modulate:a", 0.0, 0.7)
	_burst(pack.position + Vector2(PACK_SIZE.x / 2, 30), Color("f6ead0"), 30)
	await get_tree().create_timer(0.25).timeout
	# Cards slide up out of the pack into a stack.
	for i in pulls.size():
		var p: Dictionary = pulls[i]
		var cv := CardView.make(CardDB.get_card(p["id"]), BIG_W * 0.8, false)
		cv.face_down = true
		cv.pivot_offset = cv.size / 2
		cv.position = CENTER - cv.size / 2 + Vector2(0, 40)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_world.add_child(cv)
		_world.move_child(cv, pack.get_index())
		stack.append(cv)
		var ct := create_tween()
		ct.tween_interval(i * 0.03)
		ct.tween_property(cv, "position", CENTER - cv.size / 2 + Vector2(i * 0.6, -10 - i * 1.2), 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ct.parallel().tween_property(cv, "rotation_degrees", randf_range(-3, 3), 0.35)
	var pt := create_tween().set_parallel()
	pt.tween_property(pack, "position", pack.position + Vector2(0, 360), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	pt.tween_property(pack, "modulate:a", 0.0, 0.6)
	await pt.finished
	pack.queue_free()
	pack = null
	stack.reverse()  # reveal order: stack[0] is the first (worst) card
	_reorder_stack()
	state = State.STACK
	skip_btn.visible = true
	prompt.text = "Click to reveal  ·  %d cards" % stack.size()


func _reorder_stack() -> void:
	# The next card to reveal must be drawn on top.
	for i in range(stack.size() - 1, -1, -1):
		_world.move_child(stack[i], -1)


# ---------------------------------------------------------------- reveal

func _reveal_next() -> void:
	if state != State.STACK and state != State.REVEALING:
		return
	if current:
		_tuck_current()
	if reveal_idx >= pulls.size():
		_show_summary()
		return
	state = State.BUSY
	var entry: Dictionary = pulls[reveal_idx]
	var c: CardDef = CardDB.get_card(entry["id"])
	var cv: CardView = stack.pop_front()
	current = cv
	reveal_idx += 1
	prompt.text = ""
	rarity_label.text = ""
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var target_pos := CENTER - Vector2(BIG_W, BIG_W * 1.4) / 2 - Vector2(0, 26)
	var tw := create_tween().set_parallel()
	tw.tween_property(cv, "position", target_pos, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "rotation_degrees", 0.0, 0.18)
	tw.tween_property(cv, "custom_minimum_size", Vector2(BIG_W, BIG_W * 1.4), 0.18)
	tw.tween_property(cv, "size", Vector2(BIG_W, BIG_W * 1.4), 0.18)
	await tw.finished
	cv.pivot_offset = cv.size / 2
	# Anticipation scales with rarity.
	var tier := CardDef.RARITIES.find(c.rarity)
	if entry["foil"]:
		tier = maxi(tier, 2)
	if tier >= 2:
		var hold: float = [0.0, 0.0, 0.35, 0.8, 1.4][tier]
		Sfx.play("thump", 0.8)
		var shake_tw := create_tween()
		var steps := int(hold / 0.05)
		for i in steps:
			var amp := 2.0 + i * 0.25
			shake_tw.tween_property(cv, "rotation_degrees", amp if i % 2 == 0 else -amp, 0.05)
		shake_tw.tween_property(cv, "rotation_degrees", 0.0, 0.05)
		var glow_tw := create_tween()
		cv.glow = 0.0
		cv.card = c  # needed for glow colour while still face down
		glow_tw.tween_property(cv, "glow", 0.6, hold)
		await shake_tw.finished
	# Flip.
	Sfx.play("flip", randf_range(0.9, 1.1))
	var flip := create_tween()
	flip.tween_property(cv, "scale:x", 0.0, 0.09)
	await flip.finished
	cv.set_face_down(false)
	cv.set_foil(entry["foil"])
	if fresh.has(c.id):
		cv.badge = "NEW!"
		fresh.erase(c.id)  # only the first copy is "new"
	var flip2 := create_tween()
	flip2.tween_property(cv, "scale:x", 1.0, 0.11)
	match c.rarity:
		"uncommon":
			Sfx.play("reveal_uncommon")
		"rare":
			Sfx.play("reveal_rare")
			cv.glow = 1.0
			_burst(cv.position + cv.size / 2, UIKit.RARITY_COLORS["rare"], 30)
		"ultra":
			Sfx.play("reveal_ultra")
			cv.glow = 1.0
			_flash(Color(1, 0.85, 0.95), 0.5)
			_shake = 0.5
			_burst(cv.position + cv.size / 2, UIKit.RARITY_COLORS["ultra"], 60)
		"secret":
			Sfx.play("reveal_secret")
			cv.glow = 1.0
			_flash(Color.WHITE, 0.9)
			_shake = 1.0
			for i in 3:
				_burst(cv.position + cv.size / 2, Color.from_hsv(i / 3.0, 0.5, 1.0), 60)
		_:
			Sfx.play("flip", 1.3, -6.0)
	if entry["foil"] and c.rarity in ["common", "uncommon"]:
		Sfx.play("reveal_uncommon", 1.5)
		_burst(cv.position + cv.size / 2, Color("b8fff4"), 25)
	var pop := create_tween()
	pop.tween_property(cv, "scale", Vector2(1.08, 1.08), 0.1)
	pop.tween_property(cv, "scale", Vector2.ONE, 0.15)
	var rname: String = CardDef.RARITY_NAMES[c.rarity]
	rarity_label.text = ("✦ FOIL ✦  " if entry["foil"] else "") + rname.to_upper() + ("!" if CardDef.RARITIES.find(c.rarity) >= 2 else "")
	rarity_label.add_theme_color_override("font_color", UIKit.RARITY_COLORS[c.rarity])
	var owned := Game.collection.count(c.id)
	info_label.text = "%s  ·  #%d  ·  you own %d" % [c.name, c.collector_number, owned]
	await pop.finished
	state = State.REVEALING
	prompt.text = "Click for the next card (%d left)" % stack.size() if not stack.is_empty() else "Click to see your pull"


func _tuck_current() -> void:
	var cv := current
	current = null
	var i := revealed.size()
	revealed.append(cv)
	cv.glow = minf(cv.glow, 0.35)
	var row_x := 480 - (pulls.size() * (ROW_W + 6)) / 2.0 + i * (ROW_W + 6)
	var tw := create_tween().set_parallel()
	tw.tween_property(cv, "position", Vector2(row_x, 452), 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "size", Vector2(ROW_W, ROW_W * 1.4), 0.25)
	tw.tween_property(cv, "custom_minimum_size", Vector2(ROW_W, ROW_W * 1.4), 0.25)
	tw.tween_property(cv, "rotation_degrees", 0.0, 0.25)


func _reveal_all() -> void:
	if state != State.STACK and state != State.REVEALING:
		return
	if current:
		_tuck_current()
	while not stack.is_empty():
		var entry: Dictionary = pulls[reveal_idx]
		var cv: CardView = stack.pop_front()
		cv.card = CardDB.get_card(entry["id"])
		cv.set_face_down(false)
		cv.set_foil(entry["foil"])
		if fresh.has(cv.card.id):
			cv.badge = "NEW!"
			fresh.erase(cv.card.id)
		reveal_idx += 1
		current = cv
		_tuck_current()
	Sfx.play("reveal_uncommon")
	await get_tree().create_timer(0.3).timeout
	_show_summary()


# ---------------------------------------------------------------- summary

func _show_summary() -> void:
	state = State.SUMMARY
	skip_btn.visible = false
	prompt.text = ""
	rarity_label.text = ""
	var new_count := 0
	for cv in revealed:
		if cv.badge != "":
			new_count += 1
	var best: CardDef = revealed.back().card if not revealed.is_empty() else null
	var after := Game.collection.completion(pack_info["set"])
	info_label.text = "%d new cards  ·  Best pull: %s  ·  %s %d%% complete (+%d%%)" % [
		new_count, best.name if best else "-", CardDB.sets[pack_info["set"]]["code"], int(after * 100), int(round((after - completion_before) * 100))]
	# Lay the cards out in two rows.
	var w := 112.0
	for i in revealed.size():
		var cv: CardView = revealed[i]
		var row := i / 5
		var col := i % 5
		var pos := Vector2(480 - 2.5 * (w + 14) + col * (w + 14) + 7, 60 + row * (w * 1.4 + 12))
		cv.glow = 0.4 if CardDef.RARITIES.find(cv.card.rarity) >= 2 else 0.0
		cv.mouse_filter = Control.MOUSE_FILTER_STOP
		var tw := create_tween().set_parallel()
		tw.tween_interval(i * 0.03)
		tw.tween_property(cv, "position", pos, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(cv, "size", Vector2(w, w * 1.4), 0.35)
		tw.tween_property(cv, "custom_minimum_size", Vector2(w, w * 1.4), 0.35)
		cv.pivot_offset = Vector2(w, w * 1.4) / 2
		cv.hovered.connect(_on_summary_hover)
	if Game.pending_packs.is_empty():
		buttons.add_child(UIKit.button("Done", func(): _next_pack(), 140))
	else:
		buttons.add_child(UIKit.button("Next pack (%d left)" % Game.pending_packs.size(), func(): _restart(), 180))
		buttons.add_child(UIKit.button("Save the rest for later", func(): _save_rest(), 200))
	buttons.add_child(UIKit.button("View binder", func(): _to_binder(), 140))


func _on_summary_hover(cv: CardView, on: bool) -> void:
	if state != State.SUMMARY:
		return
	_world.move_child(cv, -1)
	create_tween().tween_property(cv, "scale", Vector2(1.6, 1.6) if on else Vector2.ONE, 0.12)


func _restart() -> void:
	reveal_idx = 0
	_next_pack()


func _save_rest() -> void:
	for p in Game.pending_packs:
		Game.add_sealed(p["set"], p.get("variant", ""))
	Game.pending_packs.clear()
	_next_pack()


func _to_binder() -> void:
	_save_rest()
	Game.save_game()
	Game.goto("binder")


# ---------------------------------------------------------------- juice

func _flash(c: Color, strength: float) -> void:
	flash.color = Color(c, strength)
	create_tween().tween_property(flash, "color:a", 0.0, 0.6)


func _burst(at: Vector2, c: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 1.1
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 30
	p.direction = Vector2(0, -1)
	p.spread = 180
	p.initial_velocity_min = 120
	p.initial_velocity_max = 320
	p.gravity = Vector2(0, 380)
	p.damping_min = 40
	p.damping_max = 80
	p.scale_amount_min = 3
	p.scale_amount_max = 6
	var ramp := Gradient.new()
	ramp.set_color(0, c.lightened(0.3))
	ramp.set_color(1, Color(c, 0))
	p.color_ramp = ramp
	_world.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


## The booster wrapper. Draws itself; the top strip can be torn off.
class PackVisual:
	extends Control
	const SHADER := preload("res://assets/shaders/foil.gdshader")
	var set_name_text := ""
	var mascot := ""
	var top_color := Color("e0703c")
	var bottom_color := Color("b84a2e")
	var card_count := 8
	var collector := false
	var tear := 0.0:
		set(v):
			tear = v
			queue_redraw()
	var wobble := 0.0
	var _top_attached := true
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("strength", 0.35)
		m.set_shader_parameter("prism", 1.0 if collector else 0.0)
		material = m

	func _process(delta: float) -> void:
		_t += delta
		wobble = maxf(0.0, wobble - delta * 3.0)
		rotation_degrees = sin(_t * 1.5) * 1.2 + sin(_t * 40.0) * wobble * 1.5
		queue_redraw()

	func detach_top() -> Control:
		_top_attached = false
		var strip := PackTop.new()
		strip.size = Vector2(size.x, 40)
		strip.material = material
		strip.color = Color("6e55a0") if collector else top_color
		return strip

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var top_c := top_color if not collector else Color("6e55a0")
		var bot_c := bottom_color if not collector else Color("3d2f6b")
		var y0 := 40.0 if not _top_attached else 0.0
		# Body gradient in bands (pixel-y)
		for i in 20:
			var t := float(i) / 20.0
			var y := lerpf(36.0, h - 12.0, t)
			draw_rect(Rect2(6, y, w - 12, (h - 48.0) / 20.0 + 1), top_c.lerp(bot_c, t))
		# Crimped edges
		_crimp(h - 14.0, bot_c.darkened(0.2))
		if _top_attached:
			draw_rect(Rect2(6, 12, w - 12, 26), top_c.lightened(0.1))
			_crimp(0.0, top_c.darkened(0.15))
			# Tear line progress
			if tear > 0.0:
				var x := 8.0
				var pts := PackedVector2Array()
				while x < 8.0 + (w - 16.0) * tear:
					pts.append(Vector2(x, 38 + (3 if int(x / 4) % 2 == 0 else -1)))
					x += 4.0
				if pts.size() >= 2:
					draw_polyline(pts, Color("fff3d6"), 2.0)
		else:
			# Torn edge
			var pts2 := PackedVector2Array()
			for i in range(0, int(w - 12), 4):
				pts2.append(Vector2(6 + i, 38 + (3 if (i / 4) % 2 == 0 else -1)))
			draw_polyline(pts2, Color("fff3d6"), 2.0)
		# Art window with the set's mascot
		var mc: CardDef = CardDB.get_card(mascot)
		var art := CardArt.get_texture(mc if mc else CardDB.get_card(CardDB.set_card_ids(CardDB.set_order[0])[0]))
		var ar := Rect2(26, 70, w - 52, (w - 52) / 1.5)
		draw_rect(ar.grow(3), Color("2a211c"))
		draw_rect(ar.grow(2), UIKit.GOLD)
		draw_texture_rect(art, ar, false)
		var font := get_theme_default_font()
		var words := set_name_text.to_upper().split(" ")
		for i in words.size():
			draw_string(font, Vector2(0, ar.end.y + 34 + i * 26), words[i], HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color("2a211c"))
			draw_string(font, Vector2(-1, ar.end.y + 32 + i * 26), words[i], HORIZONTAL_ALIGNMENT_CENTER, w, 22, Color("fff3d6"))
		var sub := "COLLECTOR BOOSTER" if collector else "BOOSTER PACK · %d CARDS" % card_count
		draw_string(font, Vector2(0, h - 26), sub, HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color("fff3d6"))

	func _crimp(y: float, c: Color) -> void:
		for x in range(6, int(size.x) - 6, 6):
			draw_rect(Rect2(x, y, 3, 14), c)
			draw_rect(Rect2(x + 3, y, 3, 14), c.lightened(0.1))

	class PackTop:
		extends Control
		var color := Color("e0703c")
		func _draw() -> void:
			var c := color
			draw_rect(Rect2(6, 12, size.x - 12, 26), c.lightened(0.1))
			for x in range(6, int(size.x) - 6, 6):
				draw_rect(Rect2(x, 0, 3, 14), c.darkened(0.15))
				draw_rect(Rect2(x + 3, 0, 3, 14), c.darkened(0.05))
