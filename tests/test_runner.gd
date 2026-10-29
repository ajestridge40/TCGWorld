extends Node
## Headless test suite. Run with:
##   godot --headless --path . res://tests/test_runner.tscn
## Exits with code 0 on success, 1 on any failure.

var failures := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: " + msg)


func _ready() -> void:
	test_card_data()
	test_pack_generation()
	test_collection_and_decks()
	test_engine_rules()
	test_ai_vs_ai()
	test_save_roundtrip()
	test_maps()
	print("%d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func test_card_data() -> void:
	check(CardDB.sets.has("hvb"), "hvb set loaded")
	var ids := CardDB.set_card_ids("hvb")
	check(ids.size() == 52, "hvb has 52 cards (got %d)" % ids.size())
	for id in ids:
		var c: CardDef = CardDB.get_card(id)
		check(c.rarity in CardDef.RARITIES, "%s rarity valid" % id)
		check(c.text != "" or c.keywords.is_empty() and c.effects.is_empty(), "%s has text" % id)
		for e in c.effects:
			check(c.describe_effect(e) != "", "%s effect %s describable" % [id, e.get("op")])
	var fox: CardDef = CardDB.get_card("hvb_kindling_fox")
	check(fox.cost_generic == 1 and fox.cost_colors.get("ember") == 1, "cost parse 1E")
	check(fox.mana_value() == 2, "fox mv 2")
	check(CardDB.get_card("land_ember").is_basic(), "basic land exists")
	for n in CardDB.npcs.values():
		var dk := Deck.from_dict({ "cards": n["deck"] })
		check(dk.validate().is_empty(), "%s deck legal: %s" % [n["id"], dk.validate()])
	for s in CardDB.starters:
		var dk := Deck.from_dict({ "cards": s["cards"] })
		check(dk.validate().is_empty(), "%s starter legal: %s" % [s["id"], dk.validate()])


func test_pack_generation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var tally := {}
	var foils := 0
	var n := 2000
	for i in n:
		var pack := PackGenerator.open_pack("hvb", rng)
		check(pack.size() == 10, "pack has 10 cards")
		var seen := {}
		for p in pack:
			var r: String = CardDB.get_card(p["id"]).rarity
			tally[r] = tally.get(r, 0) + 1
			if p["foil"]:
				foils += 1
		var last: CardDef = CardDB.get_card(pack.back()["id"])
		check(last.rarity in ["rare", "ultra", "secret"] or pack.back()["foil"], "best card revealed last")
	var secret_rate := float(tally.get("secret", 0)) / n
	print("  rarity tally over %d packs: %s, foils %d, secret/pack %.3f" % [n, tally, foils, secret_rate])
	check(secret_rate > 0.02 and secret_rate < 0.07, "secret rate ~4%")
	check(foils > n * 0.18 and foils < n * 0.32, "foil rate ~25%")
	var col := PackGenerator.open_pack("hvb", rng, "collector")
	check(col.size() == 5, "collector pack size")
	check(col.all(func(p): return p["foil"]), "collector all foil")


func test_collection_and_decks() -> void:
	var c := Collection.new()
	c.add("hvb_kindling_fox", false, 2)
	c.add("hvb_kindling_fox", true)
	check(c.count("hvb_kindling_fox") == 3, "count merges foil")
	check(c.remove("hvb_kindling_fox", true), "remove foil")
	check(not c.remove("hvb_kindling_fox", true), "can't remove missing foil")
	var dk := Deck.new()
	dk.add("hvb_kindling_fox", 3)
	dk.add("land_ember", 37)
	check(dk.validate().is_empty(), "40-card deck legal without ownership")
	check(not dk.validate(c).is_empty(), "ownership enforced")
	dk.add("hvb_cinderpaw_dragon", 2)
	check(not dk.validate().is_empty(), "ultra copy limit")


func _new_engine(a: Array, b: Array, seed_v: int) -> BattleEngine:
	var e := BattleEngine.new()
	e.setup(a, b, "A", "B", seed_v)
	return e


func test_engine_rules() -> void:
	var e := _new_engine(Deck.from_dict({ "cards": CardDB.npc("mira")["deck"] }).to_list(),
			Deck.from_dict({ "cards": CardDB.npc("rose")["deck"] }).to_list(), 7)
	e.start()
	check(e.players[0].hand.size() + e.players[1].hand.size() >= 14, "opening hands dealt")
	# Hand-build a board to test combat keywords.
	e.phase = BattleEngine.Phase.MAIN
	e.active = 0
	var p0: BattleEngine.PlayerState = e.players[0]
	var p1: BattleEngine.PlayerState = e.players[1]
	p0.battlefield.clear()
	p1.battlefield.clear()
	var viper := e._make_instance("hvb_nightshade_viper", 0)
	viper.sick = false
	var stag := e._make_instance("hvb_thicket_stag", 1)
	p0.battlefield.append(viper)
	p1.battlefield.append(stag)
	e.declare_attackers([viper.uid])
	check(e.phase == BattleEngine.Phase.BLOCKS, "in blocks phase")
	e.declare_blocks({ viper.uid: stag.uid })
	e.pass_tricks()
	e.pass_tricks()
	check(e.find(stag.uid) == null, "deathtouch kills blocker")
	check(e.find(viper.uid) == null, "viper died too")
	# Flying can't be blocked by ground creatures.
	var gull := e._make_instance("hvb_harbor_gull", 0)
	gull.sick = false
	var badger := e._make_instance("hvb_burrow_badger", 1)
	p0.battlefield.append(gull)
	p1.battlefield.append(badger)
	e.combat_done = false
	e.phase = BattleEngine.Phase.MAIN
	e.declare_attackers([gull.uid])
	check(not e.can_block(badger.uid, gull.uid), "ground can't block flyer")
	var life_before: int = p1.life
	e.declare_blocks({ gull.uid: badger.uid })
	e.pass_tricks()
	e.pass_tricks()
	check(p1.life == life_before - 1, "unblocked flyer hits face")
	# Trample overflow.
	var wyrm := e._make_instance("hvb_bramblecrown_wyrm", 0)
	wyrm.sick = false
	var bat := e._make_instance("hvb_dusk_bat", 1)
	p0.battlefield.append(wyrm)
	p1.battlefield.append(bat)
	e.combat_done = false
	e.phase = BattleEngine.Phase.MAIN
	life_before = p1.life
	e.declare_attackers([wyrm.uid])
	e.declare_blocks({ wyrm.uid: bat.uid })
	e.pass_tricks()
	e.pass_tricks()
	check(p1.life == life_before - 6, "trample excess (7 power - 1 toughness) got %d" % (life_before - p1.life))
	# Spell targeting + damage.
	var toss := e._make_instance("hvb_spark_toss", 0)
	p0.hand.append(toss)
	var land := e._make_instance("land_ember", 0)
	p0.lands.append(land)
	check(e.can_cast(0, toss), "can cast spark toss")
	var hp: int = p1.life
	check(e.cast(0, toss, { "kind": "player", "index": 1 }), "cast at face")
	check(p1.life == hp - 2, "2 damage to face")
	check(land.tapped, "land tapped for payment")


func test_ai_vs_ai() -> void:
	var ids: Array = CardDB.npc_order
	var games := 0
	var wins := [0, 0]
	var turns_total := 0
	for i in 60:
		var a: String = ids[i % ids.size()]
		var b: String = ids[(i + 1 + i / ids.size()) % ids.size()]
		var e := _new_engine(Deck.from_dict({ "cards": CardDB.npc(a)["deck"] }).to_list(),
				Deck.from_dict({ "cards": CardDB.npc(b)["deck"] }).to_list(), 1000 + i)
		var ais := [BattleAI.new(CardDB.npc(a)["aggression"]), BattleAI.new(CardDB.npc(b)["aggression"])]
		e.start()
		var guard := 0
		while not e.is_over() and guard < 2000:
			guard += 1
			var pi := e.active
			var act: Dictionary = ais[pi].next_main_action(e, pi)
			if not act.is_empty():
				var ok := e.cast(pi, act["card"], act["target"])
				check(ok, "AI action legal (%s)" % act["card"].def.name)
				if not ok:
					break
				continue
			if not e.combat_done:
				e.declare_attackers(ais[pi].choose_attackers(e, pi))
				if e.phase == BattleEngine.Phase.BLOCKS:
					e.declare_blocks(ais[1 - pi].choose_blocks(e, 1 - pi))
					while e.phase == BattleEngine.Phase.TRICKS:
						var tp: int = e.trick_player
						var tr: Dictionary = ais[tp].next_trick(e, tp)
						if tr.is_empty():
							e.pass_tricks()
						else:
							check(e.cast(tp, tr["card"], tr["target"]), "AI trick legal")
				continue
			e.end_turn()
			if e.turn > 80:
				break
		check(e.is_over(), "game %d finished (turn %d)" % [i, e.turn])
		if e.is_over():
			games += 1
			wins[e.winner] += 1
			turns_total += e.turn
	print("  AI vs AI: %d games, avg %.1f turns, wins by seat %s" % [games, float(turns_total) / maxi(1, games), wins])


func test_save_roundtrip() -> void:
	Game.new_game("Tester", "hearthfire_pals")
	check(Game.decks.size() == 1, "starter deck created")
	check(Game.current_deck().validate(Game.collection).is_empty(), "starter deck legal with ownership")
	Game.add_coins(123)
	var coins := Game.coins
	Game.save_game()
	Game.coins = 0
	check(Game.load_game(), "load ok")
	check(Game.coins == coins, "coins persisted")
	check(Game.collection.count("hvb_kindling_fox") == 3, "collection persisted")
	var pulls := PackGenerator.open_pack("hvb", Game.rng)
	var fresh := Game.add_pulls(pulls)
	check(Game.unlocked.has("first_pack"), "first_pack achievement")
	check(fresh.size() > 0, "some new cards")
	var offer := Game.trade_offer("pip")
	print("  trade offer from pip: ", offer)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))


func test_maps() -> void:
	for id in CardDB.maps:
		var m: Dictionary = CardDB.maps[id]
		check(m.has("w") and m.has("h"), "map %s has size" % id)
		var wm := WorldMap.new()
		wm.load_map(m)
		for b in m.get("buildings", []):
			if b.has("spawn"):
				pass
		for d in wm.doors:
			var dest: Dictionary = CardDB.maps[d["to"]]
			var dm := WorldMap.new()
			dm.load_map(dest)
			check(not dm.is_blocked(Vector2i(d["spawn"][0], d["spawn"][1])), "spawn %s->%s walkable" % [id, d["to"]])
