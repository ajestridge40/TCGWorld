extends Node
## Dev tool: detailed AI-vs-AI stats for two decks.
##   godot --headless --path . res://tests/balance_sim.tscn -- <deckA> <deckB> [games]
## Deck names are starter ids or npc ids.

## "deck~old_card>new_card~..." swaps every copy of old_card for new_card (experiments).
func _deck(spec: String) -> Dictionary:
	var parts := spec.split("~")
	var d := _base_deck(parts[0]).duplicate()
	for i in range(1, parts.size()):
		var sw := parts[i].split(">")
		var n: int = d.get(sw[0], 0)
		d.erase(sw[0])
		d[sw[1]] = d.get(sw[1], 0) + n
	return d


func _base_deck(name: String) -> Dictionary:
	if "@" in name:
		var np := name.split("@")
		return CardDB.npc(np[0])["set_decks"][np[1]]
	if name.begins_with("all:"):
		return { name.substr(4): 30 }
	for s in CardDB.starters:
		if s["id"] == name:
			return s["cards"]
	return Game.npc_deck(name) if CardDB.npcs.has(name) else {}


func _on_event(kind: String, d: Dictionary, stats: Dictionary) -> void:
	match kind:
		"player_damage":
			stats["face"][1 - d["player"]] += d["amount"]
		"life_gain":
			stats["heal"][d["player"]] += d["amount"]
		"play":
			stats["played"][d["player"]][d["card"]] = stats["played"][d["player"]].get(d["card"], 0) + 1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var a: String = args[0] if args.size() > 0 else "hearthfire_pals"
	var b: String = args[1] if args.size() > 1 else "lighthouse_watch"
	var n := int(args[2]) if args.size() > 2 else 40
	var stats := { "wins": [0, 0], "face": [0, 0], "heal": [0, 0], "turns": 0, "first_wins": 0, "played": [{}, {}], "deaths": [0, 0] }
	for g in n:
		var e := BattleEngine.new()
		e.setup(Deck.from_dict({ "cards": _deck(a) }).to_list(), Deck.from_dict({ "cards": _deck(b) }).to_list(), a, b, 900 + g)
		var first := e.active
		e.event.connect(_on_event.bind(stats))
		var ais := [BattleAI.new(0.5), BattleAI.new(0.5)]
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
		if e.is_over():
			stats["wins"][e.winner] += 1
			if e.winner == first:
				stats["first_wins"] += 1
		stats["turns"] += e.turn
	print("%s vs %s over %d games" % [a, b, n])
	print("  wins %s, first player won %d, avg turns %.1f" % [stats["wins"], stats["first_wins"], float(stats["turns"]) / n])
	print("  face damage dealt %s, healing %s" % [stats["face"], stats["heal"]])
	for i in 2:
		var arr: Array = stats["played"][i].keys()
		arr.sort_custom(func(x, y): return stats["played"][i][x] > stats["played"][i][y])
		print("  %s plays: %s" % [[a, b][i], ", ".join(arr.slice(0, 12).map(func(k): return "%s %d" % [k.replace("hvb_", ""), stats["played"][i][k]]))])
	get_tree().quit()
