extends Node
## Dev tool: render a scene in a given state and save a PNG.
##   xvfb-run godot --path . res://tests/screenshot.tscn -- <scene> <out.png> [setup]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: String = args[0] if args.size() > 0 else "menu"
	var out: String = args[1] if args.size() > 1 else "user://shot.png"
	var setup: String = args[2] if args.size() > 2 else ""
	Game.new_game("Sam", "hearthfire_pals")
	Game.minutes = 14 * 60
	Game.map_id = "town"
	Game.player_pos = Vector2i(22, 12)
	match setup:
		"shop": Game.map_id = "shop"; Game.player_pos = Vector2i(10, 8)
		"home": Game.map_id = "home"; Game.player_pos = Vector2i(6, 6); Game.flags["intro"] = true
		"evening": Game.minutes = 20 * 60
		"tff":
			Game.day = 20
			var r2 := RandomNumberGenerator.new()
			r2.seed = 6
			for i in 10:
				Game.add_pulls(PackGenerator.open_pack("tff", r2))
		"rich":
			var r := RandomNumberGenerator.new()
			r.seed = 5
			for i in 12:
				Game.add_pulls(PackGenerator.open_pack("hvb", r))
	Game.flags["intro"] = true
	if scene == "packs":
		Game.pending_packs = [{ "set": "hvb", "variant": "" }]
	if scene == "battle":
		Game.battle_request = { "opponent": "mira", "best_of": 1, "context": "casual" }
		if setup == "midgame2":
			Game.day = 20
			Game.decks[0] = Deck.from_dict({ "name": "Tidefall Test", "cards": CardDB.npc("theo")["set_decks"]["tff"] })
	var s: Node = load(Game.SCENES[scene]).instantiate()
	get_tree().root.add_child.call_deferred(s)
	var wait := 1.5
	if args.size() > 3:
		wait = float(args[3])
	await get_tree().create_timer(wait).timeout
	if scene == "packs" and setup.begins_with("reveal"):
		s._rip()
		await get_tree().create_timer(1.5).timeout
		var n := int(setup.substr(6)) if setup.length() > 6 else 10
		for i in n:
			s._reveal_next()
			await get_tree().create_timer(2.2).timeout
	if scene == "battle" and setup.begins_with("midgame"):
		# Fast-forward AI-vs-AI turns so the board is busy, then hand control back.
		if setup == "midgame2":
			Game.day = 20
		var ai0 := BattleAI.new(0.6)
		while s.busy or s.mode == "idle":
			await get_tree().process_frame
		var e: BattleEngine = s.engine
		for t in 9:
			var pi := e.active
			var my_ai: BattleAI = ai0 if pi == 0 else s.ai
			for phase in 2:
				while true:
					var a := my_ai.next_action(e, pi)
					if a.is_empty():
						break
					if a["kind"] == "move":
						e.move(pi, a["uid"], a["lane"])
					else:
						e.play(pi, a["card"], a["lane"], a["target"])
				if phase == 0 and e.turn > 2:
					e.attack(my_ai.choose_attackers(e, pi))
			if e.is_over():
				break
			if t < 8 or e.active != 0:
				e.end_turn()
		e.attacked = false
		s.mode = "play"
		s._refresh()
		await get_tree().create_timer(0.5).timeout
		if args.size() > 4 and args[4] == "attack":
			s._on_main_button()
			await get_tree().create_timer(0.3).timeout
		if args.size() > 4 and args[4] == "place":
			for c in e.me(0).hand:
				if c.def.is_creature():
					e.me(0).sparks = 10
					s._try_play(c)
					break
			await get_tree().create_timer(0.3).timeout
	if scene == "world" and setup == "talk":
		s._talk_to(s.npcs.keys()[0])
		await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
