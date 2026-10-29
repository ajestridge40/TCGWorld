extends Node
## Loads every scene headlessly, pokes its main interactions, and plays a full
## battle on autopilot. Catches script errors that only show up at runtime.
##   godot --headless --path . res://tests/smoke_test.tscn

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)


func _ready() -> void:
	Engine.time_scale = 20.0
	Game.new_game("Smoke", "lighthouse_watch")
	await _scene_test()
	print("smoke test done, %d failures" % failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	get_tree().quit(1 if failures > 0 else 0)


func _load(name: String) -> Node:
	var s: Node = load(Game.SCENES[name]).instantiate()
	add_child(s)
	await _frames(3)
	return s


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _scene_test() -> void:
	# Menu
	var s := await _load("menu")
	s.queue_free()
	# World: each map.
	for m in ["home", "town", "shop"]:
		Game.map_id = m
		Game.player_pos = Vector2i(CardDB.maps[m]["w"] / 2, CardDB.maps[m]["h"] / 2)
		Game.minutes = 14 * 60
		s = await _load("world")
		check(s.map.id == m, "world loaded " + m)
		s._interact()
		s._pause_menu()
		await _frames(2)
		if m == "shop":
			check(s.npcs.has("gus"), "gus is in the shop at 2pm")
			if s.npcs.has("gus"):
				s._talk_to("gus")
			s._tournament_board()
		s.queue_free()
		await _frames(1)
	# Shop
	s = await _load("shop")
	var coins := Game.coins
	s._buy(CardDB.product("pack_hvb"))
	check(Game.coins == coins - 100, "bought a pack")
	check(Game.sealed_total() == 3, "sealed packs = 3")
	s._buy_single(0)
	s._sell_extras()
	s._work_shift()
	await _frames(2)
	s.queue_free()
	# Pack opening: rip and reveal everything.
	Game.pending_packs = Game.take_sealed_all()
	Game.return_scene = "binder"
	s = await _load("packs")
	for p in 3:
		await get_tree().create_timer(1.5).timeout
		s._rip()
		await get_tree().create_timer(2.0).timeout
		for i in 4:
			s._reveal_next()
			await get_tree().create_timer(2.0).timeout
		s._reveal_all()
		await get_tree().create_timer(1.0).timeout
		check(s.state == s.State.SUMMARY, "pack %d reached summary (state %s)" % [p, s.state])
		if p < 2:
			s._restart()
	check(Game.stats["packs"] == 3, "3 packs opened (got %s)" % Game.stats["packs"])
	s.queue_free()
	await _frames(2)
	# Binder + deck builder
	s = await _load("binder")
	for f in ["owned", "missing", "tide", "all"]:
		s._set_filter(f)
	s._flip(1)
	s._inspect(CardDB.get_card("hvb_kindling_fox"))
	s.queue_free()
	s = await _load("decks")
	s._add("land_sun")
	s._remove("land_sun")
	s._new_deck()
	s._delete_deck()
	s.queue_free()
	# Battle on autopilot.
	for opp in ["pip", "mira"]:
		Game.battle_request = { "opponent": opp, "best_of": 1, "context": "casual" }
		s = await _load("battle")
		var guard := 0
		while not s.result_layer.visible and guard < 20000:
			guard += 1
			await get_tree().process_frame
			if s.busy:
				continue
			match s.mode:
				"main":
					# Cast whatever we can, then attack with everything.
					var cast_one := false
					for c in s.engine.me(0).hand:
						if s.engine.can_cast(0, c) and not c.def.is_instant():
							s._try_cast(c)
							if s.mode == "target":
								s._try_target(s.pending_targets[0])
							cast_one = true
							break
					if not cast_one:
						s._on_main_button()
				"attack":
					s.sel_attackers = s.engine.me(0).battlefield.filter(func(c): return c.can_attack()).map(func(c): return c.uid)
					s._on_main_button()
				"blocks", "tricks":
					s._on_main_button()
				"target":
					s._try_target(s.pending_targets[0])
		check(s.result_layer.visible, "battle vs %s finished (turn %d)" % [opp, s.engine.turn])
		print("  battle vs %s: winner seat %d on turn %d" % [opp, s.engine.winner, s.engine.turn])
		s.queue_free()
		await _frames(2)
	# Tournament
	Game.tournament = { "round": 0, "wins": 0, "opponents": ["pip", "rose", "theo"], "results": [] }
	Game.battle_result = { "won": true, "opponent": "pip" }
	s = await _load("tournament")
	check(Game.tournament["round"] == 1, "tournament round advanced")
	s.queue_free()
