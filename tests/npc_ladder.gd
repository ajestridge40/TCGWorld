extends Node
## Difficulty ladder: each townsperson (with their own AI aggression) vs the
## three starter decks played by a neutral AI. Lower = easier opponent.
##   godot --headless --path . res://tests/npc_ladder.tscn -- [games_per_starter] [set]
## set: "base" (Hearthvale decks) or "tff" (decks after Tidefall releases).

const TARGETS := { "pip": 35, "rose": 40, "theo": 50, "mira": 55, "corwin": 60, "gus": 65 }


static func ladder(games: int, which: String) -> Dictionary:
	var out := {}
	for id in CardDB.npc_order:
		var n := CardDB.npc(id)
		var deck: Dictionary = n["deck"]
		if which == "tff" and n.has("set_decks"):
			deck = n["set_decks"].get("tff", deck)
		var wins := 0
		var total := 0
		for s in CardDB.starters:
			for g in games:
				var e := BattleEngine.new()
				e.setup(Deck.from_dict({ "cards": s["cards"] }).to_list(), Deck.from_dict({ "cards": deck }).to_list(), "P", "N", 70000 + g * 13 + hash(id) % 997)
				var ais := [BattleAI.new(0.5), BattleAI.new(float(n.get("aggression", 0.5)))]
				ais[0].rng.seed = g
				ais[1].rng.seed = g + 1
				e.start()
				while not e.is_over() and e.turn < 100:
					var pi := e.active
					for phase in 2:
						var guard := 0
						while not e.is_over() and guard < 40:
							guard += 1
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
					total += 1
					if e.winner == 1:
						wins += 1
		out[id] = 100.0 * wins / maxi(1, total)
	return out


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 200
	var which: String = args[1] if args.size() > 1 else "base"
	var res := ladder(games, which)
	print("NPC win rate vs starters (%s decks, %d games per starter):" % [which, games])
	for id in CardDB.npc_order:
		print("  %-7s %5.1f%%   (target ~%d%%)" % [id, res[id], TARGETS[id]])
	get_tree().quit()
