extends Node2D
## The walkable town / shop / home. Loads whichever map Game.map_id names.

const SPEED := 78.0
const ZOOM := 3.0
const REAL_SECONDS_PER_10_MIN := 7.0

var map := WorldMap.new()
var player: Character
var npcs: Dictionary = {}       # npc id -> Character
var ysort := Node2D.new()
var tint := CanvasModulate.new()
var ui := CanvasLayer.new()
var dialogue := DialogueBox.new()
var hud_date := UIKit.label("", 15)
var hud_time := UIKit.label("", 15)
var hud_coins := UIKit.label("", 15)
var hud_rank := UIKit.label("", 13, UIKit.INK_SOFT)
var hint := UIKit.label("", 13, Color.WHITE)
var _clock_acc := 0.0
var _last_hour := -1
var _busy := false
var _transitioning := false
var _fade := ColorRect.new()


func _ready() -> void:
	map.load_map(CardDB.maps[Game.map_id])
	var layers := map.render()
	var ground := Sprite2D.new()
	ground.centered = false
	ground.texture = ImageTexture.create_from_image(layers[0])
	add_child(ground)
	ysort.y_sort_enabled = true
	add_child(ysort)
	var overlay := Sprite2D.new()
	overlay.centered = false
	overlay.texture = ImageTexture.create_from_image(layers[1])
	overlay.z_index = 5
	add_child(overlay)
	add_child(tint)

	player = Character.new()
	player.position = Vector2(Game.player_pos.x * WorldMap.T + 8, Game.player_pos.y * WorldMap.T + 14)
	player.facing = Game.player_facing
	ysort.add_child(player)
	var cam := Camera2D.new()
	cam.zoom = Vector2(ZOOM, ZOOM)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = map.w * WorldMap.T
	cam.limit_bottom = map.h * WorldMap.T
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	player.add_child(cam)
	# Small interiors: center them instead of clamping into a corner.
	var view := Vector2(960, 540) / ZOOM
	if map.w * WorldMap.T < view.x:
		var pad := (view.x - map.w * WorldMap.T) / 2.0
		cam.limit_left = int(-pad)
		cam.limit_right = int(map.w * WorldMap.T + pad)
	if map.h * WorldMap.T < view.y:
		var pad_y := (view.y - map.h * WorldMap.T) / 2.0
		cam.limit_top = int(-pad_y)
		cam.limit_bottom = int(map.h * WorldMap.T + pad_y)
	RenderingServer.set_default_clear_color(Color("1f1a24") if not map.outdoor else Color("3f7d3a"))

	_build_ui()
	_refresh_npcs()
	_update_hud()
	_update_tint()
	Game.coins_changed.connect(func(_c): _update_hud())
	Game.time_changed.connect(func(_d, _m): _update_hud())
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.35)
	if Game.day == 0 and Game.map_id == "home" and not Game.flags.has("intro"):
		Game.flags["intro"] = true
		_intro()


func _build_ui() -> void:
	add_child(ui)
	add_child(ToastLayer.new())
	var top := UIKit.panel()
	top.position = Vector2(8, 8)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	top.add_child(v)
	v.add_child(hud_date)
	v.add_child(hud_time)
	v.add_child(hud_coins)
	v.add_child(hud_rank)
	ui.add_child(top)
	hint.add_theme_color_override("font_outline_color", Color("2a211c"))
	hint.add_theme_constant_override("outline_size", 4)
	hint.position = Vector2(8, 514)
	ui.add_child(hint)
	var loc := UIKit.label(map.data.get("name", ""), 15, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	loc.add_theme_color_override("font_outline_color", Color("2a211c"))
	loc.add_theme_constant_override("outline_size", 4)
	loc.position = Vector2(700, 10)
	loc.size = Vector2(250, 20)
	ui.add_child(loc)
	ui.add_child(dialogue)


func _intro() -> void:
	_busy = true
	await get_tree().create_timer(0.5).timeout
	dialogue.open("", [
		"Welcome to Maplebrook, %s. The moving boxes can wait." % Game.player_name,
		"You brought your starter deck and two fresh Hearthvale boosters. Press [P] to open them whenever you like.",
		"The Gilded Deck card shop is just up the road. Everyone in town plays Sparkfolk there sooner or later.",
		"Gus, the shop owner, teaches every newcomer. Go say hi. He's gruff, but he's a softie.",
		"Walk with WASD / arrows. Talk and interact with E or Space. [B] Binder, [K] Decks, [Esc] Menu.",
	])
	await dialogue.closed
	_busy = false


func _update_hud() -> void:
	hud_date.text = Game.date_string()
	hud_time.text = Game.time_string()
	hud_coins.text = UIKit.coins_text(Game.coins)
	hud_rank.text = "Rank %d · %s" % [Game.rank, Game.rank_title()]
	var packs := Game.sealed_total()
	hint.text = "[E] Interact   [B] Binder   [K] Decks   [P] Open packs (%d)   [Esc] Menu" % packs


func _update_tint() -> void:
	if not map.outdoor:
		tint.color = Color(1.0, 0.97, 0.92)
		return
	var h := Game.hour()
	var day_c := Color(1, 1, 1)
	var dusk := Color(1.0, 0.82, 0.7)
	var night := Color(0.45, 0.48, 0.72)
	if h < 17.0:
		tint.color = day_c
	elif h < 19.5:
		tint.color = day_c.lerp(dusk, (h - 17.0) / 2.5)
	elif h < 21.5:
		tint.color = dusk.lerp(night, (h - 19.5) / 2.0)
	else:
		tint.color = night


func _refresh_npcs() -> void:
	for id in CardDB.npc_order:
		var loc := Game.npc_location(id)
		var here: bool = not loc.is_empty() and loc["map"] == Game.map_id
		if here and not npcs.has(id):
			var n := CardDB.npc(id)
			var c := Character.new()
			c.look = n["look"]
			c.npc_id = id
			c.display_name = n["name"]
			c.facing = Vector2i.DOWN
			ysort.add_child(c)
			npcs[id] = c
		if here:
			npcs[id].position = Vector2(loc["pos"][0] * WorldMap.T + 8, loc["pos"][1] * WorldMap.T + 14)
		elif npcs.has(id):
			npcs[id].queue_free()
			npcs.erase(id)


func _process(delta: float) -> void:
	if _transitioning:
		return
	if not _busy and not dialogue.is_open():
		_clock_acc += delta
		if _clock_acc >= REAL_SECONDS_PER_10_MIN:
			_clock_acc = 0.0
			Game.advance_time(10)
			_update_tint()
			if int(Game.hour()) != _last_hour:
				_last_hour = int(Game.hour())
				_refresh_npcs()
			if Game.is_too_late():
				_pass_out()
				return
		_move_player(delta)
	else:
		player.moving = false
	# Show names of nearby NPCs.
	for id in npcs:
		npcs[id].show_name(npcs[id].position.distance_to(player.position) < 28.0)


func _move_player(delta: float) -> void:
	var dir := Vector2(
		Input.get_axis("ui_left", "ui_right") + (1.0 if Input.is_key_pressed(KEY_D) else 0.0) - (1.0 if Input.is_key_pressed(KEY_A) else 0.0),
		Input.get_axis("ui_up", "ui_down") + (1.0 if Input.is_key_pressed(KEY_S) else 0.0) - (1.0 if Input.is_key_pressed(KEY_W) else 0.0))
	dir = dir.limit_length(1.0)
	player.moving = dir != Vector2.ZERO
	if not player.moving:
		return
	if absf(dir.x) > absf(dir.y):
		player.facing = Vector2i.RIGHT if dir.x > 0 else Vector2i.LEFT
	else:
		player.facing = Vector2i.DOWN if dir.y > 0 else Vector2i.UP
	var step := dir * SPEED * delta
	# Axis-separated movement so you slide along walls.
	var nx := player.position + Vector2(step.x, 0)
	if _free(nx):
		player.position = nx
	var ny := player.position + Vector2(0, step.y)
	if _free(ny):
		player.position = ny
	var door := map.door_at(player.tile())
	if not door.is_empty():
		_enter_door(door)


## Feet hitbox: 10x5 pixels.
func _free(p: Vector2) -> bool:
	for off in [Vector2(-5, -4), Vector2(4, -4), Vector2(-5, 0), Vector2(4, 0)]:
		var q: Vector2 = p + off
		var t := Vector2i(floori(q.x / WorldMap.T), floori(q.y / WorldMap.T))
		if map.is_blocked(t):
			return false
	for id in npcs:
		var n: Character = npcs[id]
		if absf(n.position.x - p.x) < 10 and absf(n.position.y - p.y) < 6:
			return false
	return true


func _enter_door(door: Dictionary) -> void:
	_transitioning = true
	player.moving = false
	Sfx.play("thump")
	Game.map_id = door["to"]
	Game.player_pos = Vector2i(door["spawn"][0], door["spawn"][1])
	Game.player_facing = Vector2i.DOWN if door["to"] != "town" else Vector2i.DOWN
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.25)
	tw.tween_callback(func(): Game.goto("world"))


func _save_position() -> void:
	Game.player_pos = player.tile()
	Game.player_facing = player.facing


func _go(scene: String) -> void:
	_save_position()
	Game.return_scene = "world"
	Game.goto(scene)


# ---------------------------------------------------------------- input

func _unhandled_input(ev: InputEvent) -> void:
	if _transitioning:
		return
	if dialogue.is_open():
		if ev.is_action_pressed("interact"):
			dialogue.advance()
			get_viewport().set_input_as_handled()
		return
	if _busy:
		return
	if ev.is_action_pressed("interact"):
		_interact()
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_B: _go("binder")
			KEY_K: _go("decks")
			KEY_P: _open_packs()
			KEY_ESCAPE: _pause_menu()


func _open_packs() -> void:
	if Game.sealed_total() == 0:
		dialogue.open("", ["You don't have any unopened packs. The Gilded Deck sells them!"])
		return
	_save_position()
	Game.open_packs(Game.take_sealed_all(), "world")


func _pause_menu() -> void:
	dialogue.open("Menu", ["Collected %d / %d Hearthvale cards. %d packs opened. %d wins, %d losses." % [
			Game.collection.owned_unique("hvb"), CardDB.set_card_ids("hvb").size(),
			int(Game.stats.get("packs", 0)), int(Game.stats.get("wins", 0)), int(Game.stats.get("losses", 0))]], [
		{ "text": "Resume", "cb": Callable() },
		{ "text": "Achievements", "cb": _show_achievements },
		{ "text": "Music: %s" % ("On" if Sfx.music_enabled else "Off"), "cb": func(): Sfx.set_music(not Sfx.music_enabled) },
		{ "text": "Save & Quit", "cb": func():
			_save_position()
			Game.save_game()
			Game.goto("menu") },
	])


func _show_achievements() -> void:
	var lines: Array = []
	var page := ""
	var i := 0
	for a in CardDB.achievements.get("achievements", []):
		var got: bool = Game.unlocked.has(a["id"])
		page += ("[color=#2e7d32]★ %s[/color]" if got else "[color=#9a8a78]☆ %s[/color]") % a["name"] + " - " + a["desc"] + "\n"
		i += 1
		if i % 3 == 0:
			lines.append(page.strip_edges())
			page = ""
	if page != "":
		lines.append(page.strip_edges())
	dialogue.open("Achievements", lines)


func _front_tile() -> Vector2i:
	return player.tile() + player.facing


func _interact() -> void:
	var front := _front_tile()
	var probe := player.position + Vector2(player.facing) * 12.0
	for id in npcs:
		var n: Character = npcs[id]
		if n.tile() == front or n.position.distance_to(probe) < 10.0:
			_talk_to(id)
			return
	var it: Dictionary = map.interact.get(front, map.interact.get(player.tile(), {}))
	if it.is_empty():
		return
	if it["kind"] == "text":
		dialogue.open("", [it["text"]])
	elif it["kind"] == "action":
		_do_action(it["action"])


func _do_action(action: String) -> void:
	match action:
		"shop":
			if npcs.has("gus"):
				_go("shop")
			else:
				dialogue.open("", ["Nobody's behind the counter. A sign says: 'Open 8am to midnight. Gus.'"])
		"singles":
			Game.shop_tab = "Singles"
			if npcs.has("gus"):
				_go("shop")
			else:
				dialogue.open("", ["The display case is locked. A secret rare glints inside."])
		"tournament":
			_tournament_board()
		"sleep":
			dialogue.open("", ["Go to bed and end the day?"], [
				{ "text": "Sleep", "cb": _sleep },
				{ "text": "Not yet", "cb": Callable() },
			])
		"desk":
			dialogue.open("", ["Your desk. Binders, sleeves, and a mug that says WORLD'S OKAYEST DUELIST."], [
				{ "text": "Binder", "cb": func(): _go("binder") },
				{ "text": "Deck Builder", "cb": func(): _go("decks") },
				{ "text": "Open packs (%d)" % Game.sealed_total(), "cb": _open_packs },
				{ "text": "Close", "cb": Callable() },
			])
		"trophies":
			var n := Game.trophies.size()
			dialogue.open("", ["Your trophy shelf. " + ("It's empty... for now." if n == 0 else "%d trophies. Each one a story." % n)])


func _tournament_board() -> void:
	var t: Dictionary = CardDB.products["tournament"]
	var info := "%s: every Saturday %dpm-%dpm. Entry %dc. %d rounds, best of one. Prizes for everyone!" % [
		t["name"], int(t["from"]) - 12, int(t["to"]) - 12, int(t["entry"]), int(t["rounds"])]
	var is_on: bool = Game.weekday() == int(t["day"]) and Game.hour() >= float(t["from"]) and Game.hour() < float(t["to"])
	if not is_on:
		dialogue.open("Bulletin Board", [info, "Also pinned: 'LF draft partners - Theo', and a crayon drawing of a dragon signed 'PIP'."])
		return
	if Game.flags.has("showdown_%d" % Game.day):
		dialogue.open("Bulletin Board", ["You've already played tonight's Showdown. Same time next week!"])
		return
	var deck := Game.current_deck()
	var errs: Array = deck.validate(Game.collection) if deck else ["You need a deck."]
	dialogue.open("Bulletin Board", [info, "The Showdown is on right now! Sign up?"], [
		{ "text": "Enter (%dc)" % int(t["entry"]), "disabled": not errs.is_empty() or Game.coins < int(t["entry"]),
			"tooltip": "\n".join(errs), "cb": func():
				Game.spend(int(t["entry"]))
				Game.flags["showdown_%d" % Game.day] = true
				_start_tournament() },
		{ "text": "Not tonight", "cb": Callable() },
	])


func _start_tournament() -> void:
	var pool: Array = CardDB.npc_order.filter(func(id): return id != "gus" and CardDB.npc(id).get("battles", false))
	pool.shuffle()
	var rounds := int(CardDB.products["tournament"]["rounds"])
	Game.tournament = { "round": 0, "wins": 0, "opponents": pool.slice(0, rounds), "results": [] }
	_go("tournament")


func _sleep() -> void:
	_transitioning = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.8)
	tw.tween_callback(func():
		Game.sleep()
		Game.goto("world"))


func _pass_out() -> void:
	_transitioning = true
	dialogue.open("", ["You're exhausted... You stumble home and collapse into bed. (It's 2am!)"])
	await dialogue.closed
	_sleep()


# ---------------------------------------------------------------- NPCs

func _portrait(id: String) -> Texture2D:
	return CharacterSprite.texture(CardDB.npc(id)["look"], 0, 0)


func _talk_to(id: String) -> void:
	var n := CardDB.npc(id)
	var c: Character = npcs[id]
	c.face_toward(player.position)
	var hearts := Game.hearts(id)
	var tiers: Dictionary = n.get("talk", {})
	var best := "0"
	for k in tiers:
		if int(k) <= hearts and int(k) >= int(best):
			best = k
	var lines: Array = tiers[best]
	var line: String = lines[(Game.day + hash(id)) % lines.size()]
	if id == "gus" and not Game.flags.get("tutorial_done", false):
		line = "New face, huh? You play Sparkfolk? ...No? Sit down, sit down. Ten minutes and you'll know everything that matters."
	if not Game.talked_today.has(id):
		Game.talked_today[id] = true
		Game.add_friendship(id, 25)
	var heart_str := "♥".repeat(Game.hearts(id)) + "♡".repeat(maxi(0, 4 - Game.hearts(id)))
	_npc_menu(id, "%s  %s" % [n["name"], heart_str], [line])


func _npc_menu(id: String, title: String, lines: Array) -> void:
	var n := CardDB.npc(id)
	var choices: Array = []
	if id == "gus":
		var done: bool = Game.flags.get("tutorial_done", false)
		choices.append({ "text": "Replay lesson" if done else "Learn Sparkfolk!", "cb": _start_tutorial })
		choices.append({ "text": "Shop", "cb": func(): _go("shop") })
	if n.get("battles", false):
		var need := int(n.get("battle_min_hearts", 0))
		var locked := Game.hearts(id) < need
		choices.append({ "text": "Battle", "disabled": locked, "tooltip": "Needs %d hearts" % need if locked else "",
			"cb": func(): _battle_menu(id) })
	choices.append({ "text": "Trade", "disabled": Game.hearts(id) < 1, "tooltip": "Become friends first (1 heart)" if Game.hearts(id) < 1 else "",
		"cb": func(): _trade(id) })
	choices.append({ "text": "Bye", "cb": Callable() })
	dialogue.open(title, lines, choices, _portrait(id))


func _start_tutorial() -> void:
	_save_position()
	Game.battle_request = { "opponent": "gus", "best_of": 1, "context": "tutorial" }
	Game.return_scene = "world"
	Game.goto("battle")


func _battle_menu(id: String) -> void:
	var n := CardDB.npc(id)
	var deck := Game.current_deck()
	var errs: Array = deck.validate(Game.collection) if deck else ["You don't have a deck yet."]
	if not errs.is_empty():
		dialogue.open(n["name"], ["Your deck isn't ready: " + " ".join(errs), "(Fix it in the Deck Builder - press K.)"], [], _portrait(id))
		return
	var start := func(best_of: int):
		_save_position()
		Game.battle_request = { "opponent": id, "best_of": best_of, "context": "casual" }
		Game.return_scene = "world"
		Game.goto("battle")
	var reward := "" if Game.battled_today.has(id) else " (first win today: %dc)" % int(n.get("reward", 50))
	dialogue.open(n["name"], [n.get("battle_intro", "Let's play!") + reward], [
		{ "text": "Quick game (Bo1)", "cb": func(): start.call(1) },
		{ "text": "Best of 3", "cb": func(): start.call(3) },
		{ "text": "Maybe later", "cb": Callable() },
	], _portrait(id))


func _trade(id: String) -> void:
	var n := CardDB.npc(id)
	var offer := Game.trade_offer(id)
	if offer.is_empty():
		var why := "Already traded today - come back tomorrow!" if Game.traded_today.has(id) else "Hmm, you don't have anything I'm looking for right now."
		dialogue.open(n["name"], [why], [], _portrait(id))
		return
	_busy = true
	var popup := TradePopup.new()
	popup.setup(n["name"], offer)
	ui.add_child(popup)
	var accepted: bool = await popup.decided
	_busy = false
	if accepted:
		Game.accept_trade(id, offer)
		Sfx.play("coin")
		dialogue.open(n["name"], ["Pleasure doing business!"], [], _portrait(id))
