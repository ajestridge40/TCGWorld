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
	test_balance()
	test_pack_generation()
	test_collection_and_decks()
	test_engine_rules()
	test_ai_vs_ai()
	test_matchups()
	test_npc_ladder()
	test_tutorial()
	test_save_roundtrip()
	test_maps()
	print("%d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func test_card_data() -> void:
	print("> card_data")
	check(CardDB.sets.has("hvb") and CardDB.sets.has("tff"), "both sets loaded")
	check(CardDB.set_card_ids("hvb").size() == 47, "hvb has 47 cards (got %d)" % CardDB.set_card_ids("hvb").size())
	check(CardDB.set_card_ids("tff").size() == 30, "tff has 30 cards (got %d)" % CardDB.set_card_ids("tff").size())
	check(CardDB.released_sets(0) == ["hvb"], "only hvb released on day 0")
	check(CardDB.released_sets(14) == ["hvb", "tff"], "tff released on day 14")
	for set_id in CardDB.set_order:
		for id in CardDB.set_card_ids(set_id):
			var c: CardDef = CardDB.get_card(id)
			check(c.rarity in CardDef.RARITIES, "%s rarity valid" % id)
			check(c.color in CardDef.COLORS or c.color == "colorless", "%s color valid" % id)
			check(c.is_creature() or c.is_spell(), "%s type valid" % id)
			check(not c.is_creature() or c.health > 0, "%s has health" % id)
			for k in c.keywords:
				check(CardDef.KEYWORD_NAMES.has(k), "%s keyword %s known" % [id, k])
			for e in c.effects:
				check(c.describe_effect(e) != "", "%s effect %s describable" % [id, e.get("op")])
	for n in CardDB.npcs.values():
		var dk := Deck.from_dict({ "cards": n["deck"] })
		check(dk.validate().is_empty(), "%s deck legal: %s" % [n["id"], dk.validate()])
		for sid in n.get("set_decks", {}):
			var dk2 := Deck.from_dict({ "cards": n["set_decks"][sid] })
			check(dk2.validate().is_empty(), "%s %s deck legal: %s" % [n["id"], sid, dk2.validate()])
	for s in CardDB.starters:
		var dk := Deck.from_dict({ "cards": s["cards"] })
		check(dk.validate().is_empty(), "%s starter legal: %s" % [s["id"], dk.validate()])


## Every card must sit within CardBalance.TOLERANCE of its cost/rarity budget,
## and each set may only use the mechanics its complexity tier allows.
func test_balance() -> void:
	print("> balance")
	var tier_keywords := {
		1: ["swift", "soar", "shield"],
		2: ["swift", "soar", "shield", "reach", "sweep", "move"],
	}
	var tier_triggers := { 1: ["enter", "cast"], 2: ["enter", "cast", "dies", "attack"] }
	var worst := 0.0
	for set_id in CardDB.set_order:
		var tier := int(CardDB.sets[set_id].get("tier", 1))
		var lines: Array = []
		for id in CardDB.set_card_ids(set_id):
			var c: CardDef = CardDB.get_card(id)
			var dev := CardBalance.deviation(c)
			worst = maxf(worst, absf(dev))
			check(absf(dev) <= CardBalance.TOLERANCE + 0.001, "%s off budget by %+.2f (value %.2f, budget %.2f)" % [id, dev, CardBalance.value(c), CardBalance.budget(c)])
			for k in c.keywords:
				check(tier_keywords[tier].has(k), "%s uses %s, too complex for tier %d" % [id, k, tier])
			for e in c.effects:
				check(tier_triggers[tier].has(e.get("on", "cast")), "%s uses trigger %s, too complex for tier %d" % [id, e.get("on"), tier])
				if e.has("token"):
					for k in e["token"].get("keywords", []):
						check(tier_keywords[tier].has(k), "%s token uses %s" % [id, k])
			if absf(dev) > 0.75:
				lines.append("%s %+.2f" % [c.name, dev])
		print("  %s: %d cards near the edge of budget: %s" % [set_id, lines.size(), ", ".join(lines)])
	print("  worst budget deviation: %.2f (tolerance %.2f)" % [worst, CardBalance.TOLERANCE])


func test_pack_generation() -> void:
	print("> pack_generation")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for set_id in CardDB.set_order:
		var tally := {}
		var foils := 0
		var n := 2000
		for i in n:
			var pack := PackGenerator.open_pack(set_id, rng)
			check(pack.size() == 8, "pack has 8 cards")
			for p in pack:
				var r: String = CardDB.get_card(p["id"]).rarity
				tally[r] = tally.get(r, 0) + 1
				if p["foil"]:
					foils += 1
			var last: Dictionary = pack.back()
			check(CardDB.get_card(last["id"]).rarity in ["rare", "ultra", "secret"] or last["foil"], "best card revealed last")
		var secret_rate := float(tally.get("secret", 0)) / n
		print("  %s over %d packs: %s, foils %d, secret/pack %.3f" % [set_id, n, tally, foils, secret_rate])
		check(secret_rate > 0.02 and secret_rate < 0.07, "secret rate ~4%")
		check(foils > n * 0.18 and foils < n * 0.32, "foil rate ~25%")
	var col := PackGenerator.open_pack("hvb", rng, "collector")
	check(col.size() == 4, "collector pack size")
	check(col.all(func(p): return p["foil"]), "collector all foil")


func test_collection_and_decks() -> void:
	print("> collection_and_decks")
	var c := Collection.new()
	c.add("hvb_kindling_fox", false, 2)
	c.add("hvb_kindling_fox", true)
	check(c.count("hvb_kindling_fox") == 3, "count merges foil")
	check(c.remove("hvb_kindling_fox", true), "remove foil")
	check(not c.remove("hvb_kindling_fox", true), "can't remove missing foil")
	var dk := Deck.new()
	for id in ["hvb_kindling_fox", "hvb_hearth_salamander", "hvb_spark_toss", "hvb_brick_oven_golem", "hvb_burrow_badger",
			"hvb_mossback_tortoise", "hvb_sudden_bloom", "hvb_puffcap_sprout", "hvb_clockwork_mouse", "hvb_patchwork_scarecrow"]:
		dk.add(id, 3)
	check(dk.size() == 30 and dk.validate().is_empty(), "30-card two-color deck legal: %s" % [dk.validate()])
	check(not dk.validate(c).is_empty(), "ownership enforced")
	check(not dk.color_allows("hvb_dusk_bat"), "third color blocked")
	check(dk.color_allows("hvb_cobblestone_golem"), "colorless always allowed")
	dk.add("hvb_dusk_bat")
	check(not dk.validate().is_empty(), "31 cards / 3 colors illegal")
	var dk2 := Deck.new()
	dk2.add("hvb_cinderpaw_dragon", 2)
	check(dk2.validate().any(func(e): return "max 1" in e), "ultra copy limit")


func _new_engine(a: Array, b: Array, seed_v: int) -> BattleEngine:
	var e := BattleEngine.new()
	check(e != null, "BattleEngine script loads")
	e.setup(a, b, "A", "B", seed_v)
	return e


func _fresh_board(seed_v: int = 7) -> BattleEngine:
	var e := _new_engine(Deck.from_dict({ "cards": CardDB.npc("mira")["deck"] }).to_list(),
			Deck.from_dict({ "cards": CardDB.npc("rose")["deck"] }).to_list(), seed_v)
	e.start()
	e.active = 0
	e.attacked = false
	for p in e.players:
		p.lanes = [null, null, null, null]
		p.sparks = 10
		p.max_sparks = 10
		p.life = 20
	return e


func _put(e: BattleEngine, id: String, owner: int, lane: int, fresh: bool = false) -> BattleEngine.CardInstance:
	var c := e._make_instance(id, owner)
	c.lane = lane
	c.fresh = fresh
	e.players[owner].lanes[lane] = c
	return c


func test_engine_rules() -> void:
	print("> engine_rules")
	var e := _new_engine(Deck.from_dict({ "cards": CardDB.npc("mira")["deck"] }).to_list(),
			Deck.from_dict({ "cards": CardDB.npc("rose")["deck"] }).to_list(), 7)
	e.start()
	var first: BattleEngine.PlayerState = e.players[e.active]
	var second: BattleEngine.PlayerState = e.players[1 - e.active]
	check(first.hand.size() == 4, "first player: 3 cards + first draw (got %d)" % first.hand.size())
	check(second.hand.size() == 5 and second.hand.any(func(c): return c.def.id == "lucky_penny"), "second player: 4 cards + Lucky Penny")
	check(first.max_sparks == 1 and first.sparks == 1, "turn 1: one Spark")
	e.end_turn()
	e.end_turn()
	check(first.max_sparks == 2, "Sparks grow by one per turn")

	# Lane combat: both creatures hit each other.
	e = _fresh_board()
	var golem := _put(e, "hvb_brick_oven_golem", 0, 1)   # 5/4
	var badger := _put(e, "hvb_burrow_badger", 1, 1)      # 2/3
	e.attack([golem.uid])
	check(e.find(badger.uid) == null, "attacker kills blocker")
	check(golem.damage == 2, "blocker hits back (golem took %d)" % golem.damage)
	check(e.players[1].life == 20, "blocked attack doesn't reach Heart")
	# Open lane hits Heart; fresh creatures can't attack, Swift can.
	e = _fresh_board()
	var sal := _put(e, "hvb_hearth_salamander", 0, 0)
	var fresh := _put(e, "hvb_burrow_badger", 0, 2, true)
	var fox := _put(e, "hvb_kindling_fox", 0, 3, true)
	check(not e.can_attack(fresh), "fresh creature can't attack")
	check(e.can_attack(fox), "Swift creature can attack right away")
	e.attack([sal.uid, fresh.uid, fox.uid])
	check(e.players[1].life == 20 - 3 - 1, "open lanes hit Heart (life %d)" % e.players[1].life)
	check(not e.attack([sal.uid]), "only one attack per turn")
	# Soar flies over ground creatures, not over Soar/Reach.
	e = _fresh_board()
	var gull := _put(e, "hvb_harbor_gull", 0, 0)
	_put(e, "hvb_shellback_crab", 1, 0)
	var gull2 := _put(e, "hvb_harbor_gull", 0, 1)
	var bat := _put(e, "hvb_dusk_bat", 1, 1)
	var gull3 := _put(e, "hvb_harbor_gull", 0, 2)
	_put(e, "tff_tidepool_crab", 1, 2)
	check(e.blocker_for(gull) == null, "soar flies over ground")
	check(e.blocker_for(gull2) == bat, "soar meets soar")
	check(e.blocker_for(gull3) != null, "reach catches soar")
	# Shield absorbs the first hit.
	e = _fresh_board()
	var squire := _put(e, "hvb_meadow_squire", 1, 0)
	var mouse := _put(e, "hvb_clockwork_mouse", 0, 0)
	e.attack([mouse.uid])
	check(squire.damage == 0 and not squire.shield, "shield popped, no damage")
	check(e.find(mouse.uid) == null, "mouse died to the hit back")
	# Sweep hits neighbors without retaliation.
	e = _fresh_board()
	var brawler := _put(e, "tff_bonfire_brawler", 0, 1)
	var left := _put(e, "hvb_dusk_bat", 1, 0)
	var right := _put(e, "hvb_burrow_badger", 1, 2)
	e.attack([brawler.uid])
	check(e.find(left.uid) == null and right.damage == 3, "sweep hits both neighbors")
	check(e.players[1].life == 17, "unblocked sweeper still hits Heart")
	# Move.
	e = _fresh_board()
	var acro := _put(e, "tff_ember_acrobat", 0, 0)
	check(e.move_options(0, acro.uid) == [1], "move to neighbor only")
	check(e.move(0, acro.uid, 1) and acro.lane == 1, "moved")
	check(e.move_options(0, acro.uid).is_empty(), "once per turn")
	# Spells, targeting, sparks.
	e = _fresh_board()
	e.players[0].sparks = 1
	var toss := e._make_instance("hvb_spark_toss", 0)
	e.players[0].hand.append(toss)
	check(e.can_play(0, toss), "can cast spark toss")
	check(not e.play(0, toss, -1, {}), "needs a target")
	check(e.play(0, toss, -1, { "kind": "player", "index": 1 }), "cast at face")
	check(e.players[1].life == 18 and e.players[0].sparks == 0, "2 damage, 1 Spark spent")
	# Tokens appear next to their maker; dies triggers fire.
	e = _fresh_board()
	var puff := e._make_instance("hvb_puffcap_sprout", 0)
	e.players[0].hand.append(puff)
	e.play(0, puff, 2)
	check(e.players[0].creatures().size() == 2, "puffcap made a spore")
	var hog := _put(e, "tff_hedge_hog", 1, 0)
	var golem2 := _put(e, "hvb_brick_oven_golem", 0, 0)
	e.attack([golem2.uid])
	check(e.find(hog.uid) == null and e.players[1].lanes[0] != null, "hedge hog left a hoglet")
	# Freeze stops the next attack only.
	e = _fresh_board()
	var net := e._make_instance("tff_frost_net", 0)
	e.players[0].hand.append(net)
	var target := _put(e, "hvb_brick_oven_golem", 1, 0)
	e.play(0, net, -1, { "kind": "creature", "uid": target.uid })
	e.end_turn()
	check(not e.can_attack(target), "frozen creature can't attack")
	e.end_turn()
	e.end_turn()
	check(e.can_attack(target), "thawed after one turn")
	# Fatigue.
	e = _fresh_board()
	e.players[1].library.clear()
	e.end_turn()
	check(e.players[1].life == 19, "fatigue 1")


func _play_ai_game(deck_a: Dictionary, deck_b: Dictionary, aggr_a: float, aggr_b: float, seed_v: int) -> BattleEngine:
	var e := _new_engine(Deck.from_dict({ "cards": deck_a }).to_list(), Deck.from_dict({ "cards": deck_b }).to_list(), seed_v)
	var ais := [BattleAI.new(aggr_a), BattleAI.new(aggr_b)]
	ais[0].rng.seed = seed_v
	ais[1].rng.seed = seed_v + 1
	e.start()
	var guard := 0
	while not e.is_over() and guard < 3000 and e.turn < 80:
		guard += 1
		var pi := e.active
		for phase in 2:
			while not e.is_over():
				var act: Dictionary = ais[pi].next_action(e, pi)
				if act.is_empty():
					break
				var ok: bool
				if act["kind"] == "move":
					ok = e.move(pi, act["uid"], act["lane"])
				else:
					ok = e.play(pi, act["card"], act["lane"], act["target"])
				check(ok, "AI action legal (%s)" % act)
				if not ok:
					return e
			if phase == 0 and not e.is_over():
				e.attack(ais[pi].choose_attackers(e, pi))
		e.end_turn()
	return e


func test_ai_vs_ai() -> void:
	print("> ai_vs_ai")
	var ids: Array = CardDB.npc_order
	var games := 0
	var seat := [0, 0]
	var first_wins := 0
	var turns_total := 0
	for i in 60:
		var a: String = ids[i % ids.size()]
		var b: String = ids[(i + 1 + i / ids.size()) % ids.size()]
		var e := _play_ai_game(CardDB.npc(a)["deck"], CardDB.npc(b)["deck"], CardDB.npc(a)["aggression"], CardDB.npc(b)["aggression"], 1000 + i)
		check(e.is_over(), "game %d finished (turn %d)" % [i, e.turn])
		if e.is_over():
			games += 1
			seat[e.winner] += 1
			turns_total += e.turn
	print("  AI vs AI: %d games, avg %.1f turns, wins by seat %s" % [games, float(turns_total) / maxi(1, games), seat])


## Round-robin between the starter decks with identical AIs: each should win a
## fair share. This is the "is the game balanced" smoke alarm.
func test_matchups() -> void:
	print("> matchups")
	var decks: Array = CardDB.starters.map(func(s): return [s["id"], s["cards"]])
	var games_per := 100
	var wins := {}
	for d in decks:
		wins[d[0]] = 0
	var first_player_wins := 0
	var total := 0
	for i in decks.size():
		for j in decks.size():
			if i >= j:
				continue
			var w_i := 0
			for g in games_per:
				var e := _play_ai_game(decks[i][1], decks[j][1], 0.5, 0.5, 5000 + g * 7 + i * 101 + j * 13)
				if not e.is_over():
					continue
				total += 1
				if e.winner == 0:
					w_i += 1
				wins[decks[i][0] if e.winner == 0 else decks[j][0]] += 1
			print("  %s vs %s: %d-%d" % [decks[i][0], decks[j][0], w_i, games_per - w_i])
	for d in decks:
		var rate: float = float(wins[d[0]]) / (games_per * (decks.size() - 1))
		print("  %s overall win rate %.0f%%" % [d[0], rate * 100])
		check(rate > 0.3 and rate < 0.7, "%s win rate %.0f%% within 30-70%%" % [d[0], rate * 100])


## Townsfolk form a difficulty ladder against the starter decks:
## Pip & Rose easy, Theo medium, Mira & Corwin hard, Gus hardest.
func test_npc_ladder() -> void:
	var NpcLadder = load("res://tests/npc_ladder.gd")
	for which in ["base", "tff"]:
		var r: Dictionary = NpcLadder.ladder(60, which)
		print("  ladder (%s): %s" % [which, ", ".join(CardDB.npc_order.map(func(id): return "%s %.0f%%" % [id, r[id]]))])
		check(r["pip"] < 48 and r["rose"] < 48, "%s: Pip and Rose are easy" % which)
		check(r["theo"] > 36 and r["theo"] < 62, "%s: Theo is medium" % which)
		check(r["mira"] > r["pip"] + 8 and r["corwin"] > r["rose"] + 8, "%s: Mira and Corwin are harder than the kids' table" % which)
		check(r["gus"] > 55, "%s: Gus is the toughest" % which)


## The lesson game should be very winnable for a beginner of any play style.
func test_tutorial() -> void:
	var t: Dictionary = CardDB.tutorial
	check(t["player_deck"].size() == 30 and t["gus_deck"].size() == 30, "tutorial decks have 30 cards")
	var wins := 0
	var styles := [0.1, 0.3, 0.5, 0.7, 0.9]
	for style in styles:
		for seed_v in 4:
			var e := BattleEngine.new()
			e.setup(t["player_deck"], t["gus_deck"], "P", "Gus", 7 + seed_v, { "first": 0, "stacked": true })
			check(e.active == 0, "player goes first in the lesson")
			check(e.me(0).hand[0].def.id == "hvb_kindling_fox", "lesson opens with Kindling Fox in hand")
			var ais := [BattleAI.new(style), BattleAI.new(float(t["aggression"]))]
			ais[0].rng.seed = seed_v
			ais[1].rng.seed = seed_v
			e.start()
			while not e.is_over() and e.turn < 80:
				var pi := e.active
				for phase in 2:
					while not e.is_over():
						var act: Dictionary = ais[pi].next_action(e, pi)
						if act.is_empty():
							break
						if act["kind"] == "move":
							e.move(pi, act["uid"], act["lane"])
						else:
							e.play(pi, act["card"], act["lane"], act["target"])
					if phase == 0 and not e.is_over():
						e.attack(ais[pi].choose_attackers(e, pi))
				e.end_turn()
			if e.winner == 0:
				wins += 1
	var rate := float(wins) / (styles.size() * 4)
	print("  tutorial: player wins %.0f%% across play styles" % (rate * 100))
	check(rate >= 0.75, "tutorial is winnable (%.0f%%)" % (rate * 100))


func test_save_roundtrip() -> void:
	print("> save_roundtrip")
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
	check(Game.current_deck().validate(Game.collection).is_empty(), "starter deck still legal after load")
	var pulls := PackGenerator.open_pack("hvb", Game.rng)
	var fresh := Game.add_pulls(pulls)
	check(Game.unlocked.has("first_pack"), "first_pack achievement")
	check(fresh.size() > 0, "some new cards")
	var offer := Game.trade_offer("pip")
	print("  trade offer from pip: ", offer)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))


func test_maps() -> void:
	print("> maps")
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
