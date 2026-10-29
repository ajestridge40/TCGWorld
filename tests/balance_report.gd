extends Node
## Large-scale balance report. Plays thousands of AI-vs-AI games and prints a
## markdown report (also saved to user://balance_report.md).
##   godot --headless --path . res://tests/balance_report.tscn -- [scale]
## scale multiplies every sample size (default 1.0; 0.1 for a quick run).

var out: PackedStringArray = []
var scale := 1.0
var first_player_wins := 0
var total_games := 0
var turn_sum := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		scale = float(args[0])
	var t0 := Time.get_ticks_msec()
	_line("# Sparkfolk balance report\n")
	_starters()
	_npcs()
	_set_upgrades()
	_rarity()
	_random_decks()
	_line("\n## Overall\n")
	_line("- Games played: **%d**" % total_games)
	_line("- First player win rate: **%.1f%%**" % (100.0 * first_player_wins / maxi(1, total_games)))
	_line("- Average game length: **%.1f turns** (both players' turns counted)" % (float(turn_sum) / maxi(1, total_games)))
	_line("- Runtime: %.0fs" % ((Time.get_ticks_msec() - t0) / 1000.0))
	var f := FileAccess.open("user://balance_report.md", FileAccess.WRITE)
	f.store_string("\n".join(out))
	print("\nSaved to ", ProjectSettings.globalize_path("user://balance_report.md"))
	get_tree().quit()


func _line(s: String) -> void:
	out.append(s)
	print(s)


func _n(base: int) -> int:
	return maxi(10, int(base * scale))


## Plays one game; returns the engine (winner, turns) and tracks globals.
func _game(deck_a: Dictionary, deck_b: Dictionary, seed_v: int, cards_played: Array = []) -> BattleEngine:
	var e := BattleEngine.new()
	e.setup(Deck.from_dict({ "cards": deck_a }).to_list(), Deck.from_dict({ "cards": deck_b }).to_list(), "A", "B", seed_v)
	var first := e.active
	var ais := [BattleAI.new(0.5), BattleAI.new(0.5)]
	ais[0].rng.seed = seed_v
	ais[1].rng.seed = seed_v + 7
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
		total_games += 1
		turn_sum += e.turn
		if e.winner == first:
			first_player_wins += 1
	return e


## Head-to-head; returns win rate of deck A. Seats alternate via the seed.
func _match(a: Dictionary, b: Dictionary, games: int, seed_base: int) -> float:
	var wins := 0
	var done := 0
	for g in games:
		var e := _game(a, b, seed_base + g * 31)
		if e.is_over():
			done += 1
			if e.winner == 0:
				wins += 1
	return float(wins) / maxi(1, done)


## 95% margin of error for a win rate measured over n games.
func _moe(n: int) -> float:
	return 1.96 * sqrt(0.25 / maxf(1.0, n)) * 100.0


func _round_robin(title: String, decks: Array, games: int, seed_base: int) -> void:
	_line("\n## %s\n" % title)
	_line("%d games per pairing (±%.1f%% margin of error per matchup).\n" % [games, _moe(games)])
	var names: Array = decks.map(func(d): return d[0])
	var header := "| | " + " | ".join(names) + " | **Overall** |"
	_line(header)
	_line("|" + "---|".repeat(names.size() + 2))
	var rates := {}
	for i in decks.size():
		for j in decks.size():
			if i < j:
				var r := _match(decks[i][1], decks[j][1], games, seed_base + i * 1000 + j * 100000)
				rates[[i, j]] = r
				rates[[j, i]] = 1.0 - r
	for i in decks.size():
		var row := "| **%s** |" % names[i]
		var sum := 0.0
		for j in decks.size():
			if i == j:
				row += " - |"
			else:
				row += " %.0f%% |" % (rates[[i, j]] * 100)
				sum += rates[[i, j]]
		var overall := sum / (decks.size() - 1)
		row += " **%.1f%%** |" % (overall * 100)
		_line(row)


func _starters() -> void:
	var decks: Array = CardDB.starters.map(func(s): return [s["id"], s["cards"]])
	_round_robin("Starter decks", decks, _n(1000), 10000)


func _npcs() -> void:
	var decks: Array = CardDB.npc_order.map(func(id): return [id, CardDB.npc(id)["deck"]])
	_round_robin("Townsfolk decks (Set 1)", decks, _n(300), 20000)


func _set_upgrades() -> void:
	_line("\n## New set vs old: power creep check\n")
	var games := _n(600)
	_line("Each townsperson's Tidefall deck vs their Hearthvale deck, %d games (±%.1f%%). Target: roughly 40-65%%.\n" % [games, _moe(games)])
	_line("| Townsperson | Tidefall deck win rate |")
	_line("|---|---|")
	for id in CardDB.npc_order:
		var n := CardDB.npc(id)
		if n.has("set_decks") and n["set_decks"].has("tff"):
			var r := _match(n["set_decks"]["tff"], n["deck"], games, 30000 + hash(id) % 1000)
			_line("| %s | %.1f%% |" % [n["name"], r * 100])
	var mixed: Array = []
	for id in CardDB.npc_order:
		var n2 := CardDB.npc(id)
		mixed.append([id + (" (TFF)" if n2.has("set_decks") else ""), n2.get("set_decks", {}).get("tff", n2["deck"])])
	_round_robin("Townsfolk decks after Tidefall releases", mixed, _n(200), 40000)


## Same colors, same curve shape: one deck of only commons vs one stuffed
## with every rare / ultra / secret it can hold.
func _rarity() -> void:
	_line("\n## Rarity: does opening rares win games?\n")
	var games := _n(800)
	_line("%d games per color pair (±%.1f%%). Both decks use the same two colors.\n" % [games, _moe(games)])
	_line("| Colors | Rare-heavy deck | Rare-heavy win rate vs commons-only |")
	_line("|---|---|---|")
	var pairs := [["ember", "grove"], ["tide", "sun"], ["moon", "grove"], ["ember", "moon"], ["sun", "grove"]]
	var total := 0.0
	for pr in pairs:
		var common := _built_deck(pr, ["common"], 77)
		var rare := _built_deck(pr, ["secret", "ultra", "rare", "uncommon", "common"], 77)
		var count := 0
		for id in rare:
			if CardDB.get_card(id).rarity in ["rare", "ultra", "secret"]:
				count += rare[id]
		var r := _match(rare, common, games, 50000 + hash(str(pr)) % 1000)
		total += r
		_line("| %s / %s | %d rare+ cards | %.1f%% |" % [pr[0], pr[1], count, r * 100])
	_line("| **Average** | | **%.1f%%** |" % (total / pairs.size() * 100))


## Fills a 30-card deck from both sets in `colors`, taking rarities in the order
## given (max copies each), aiming for ~22 creatures and a sensible curve.
func _built_deck(colors: Array, rarity_order: Array, seed_v: int) -> Dictionary:
	var pool: Array = []
	for set_id in CardDB.set_order:
		for id in CardDB.set_card_ids(set_id):
			var c: CardDef = CardDB.get_card(id)
			if c.color in colors or c.color == "colorless":
				pool.append(id)
	var r := RandomNumberGenerator.new()
	r.seed = seed_v
	var d := {}
	var size := 0
	for rar in rarity_order:
		var opts := pool.filter(func(id): return CardDB.get_card(id).rarity == rar)
		opts.sort_custom(func(a, b): return CardDB.get_card(a).cost < CardDB.get_card(b).cost)
		for id in opts:
			if size >= Deck.SIZE:
				break
			var c: CardDef = CardDB.get_card(id)
			# Keep the curve sane: few 6+ drops, at most ~8 spells.
			var spells := 0
			var big := 0
			for k in d:
				if CardDB.get_card(k).is_spell():
					spells += d[k]
				if CardDB.get_card(k).cost >= 6:
					big += d[k]
			if c.is_spell() and spells >= 8:
				continue
			if c.cost >= 6 and big >= 4:
				continue
			var n := mini(Deck.copy_limit(id), Deck.SIZE - size)
			d[id] = n
			size += n
	# Commons-only decks can come up short; pad with the cheapest commons.
	var fill := pool.filter(func(id): return CardDB.get_card(id).rarity == "common")
	while size < Deck.SIZE and not fill.is_empty():
		var id2: String = fill[r.randi_range(0, fill.size() - 1)]
		if d.get(id2, 0) < Deck.copy_limit(id2):
			d[id2] = d.get(id2, 0) + 1
			size += 1
	return d


## Thousands of games between random legal decks; tracks each card's win rate
## when it is in a deck, to surface individual outliers.
func _random_decks() -> void:
	var games := _n(4000)
	_line("\n## Individual cards (random decks)\n")
	_line("%d games between random legal two-color decks from both sets. For each card: win rate of decks that contained it." % games)
	_line("A fair card sits near 50%. Flagged: outside 42-58% with at least 150 appearances.\n")
	var r := RandomNumberGenerator.new()
	r.seed = 4242
	var in_deck := {}   # id -> [games, wins]
	for g in games:
		var da := _random_deck(r)
		var db := _random_deck(r)
		var e := _game(da, db, 60000 + g)
		if not e.is_over():
			continue
		for side in 2:
			var dk: Dictionary = da if side == 0 else db
			for id in dk:
				if not in_deck.has(id):
					in_deck[id] = [0, 0]
				in_deck[id][0] += 1
				if e.winner == side:
					in_deck[id][1] += 1
	var rows: Array = []
	for id in in_deck:
		var gp: int = in_deck[id][0]
		rows.append([id, float(in_deck[id][1]) / gp, gp])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	_line("| Card | Set | Rarity | Cost | Decks | Win rate | |")
	_line("|---|---|---|---|---|---|---|")
	var flagged := 0
	for row in rows:
		var c: CardDef = CardDB.get_card(row[0])
		var flag := ""
		if row[2] >= 150 and (row[1] < 0.42 or row[1] > 0.58):
			flag = "⚠ strong" if row[1] > 0.5 else "⚠ weak"
			flagged += 1
		_line("| %s | %s | %s | %d | %d | %.1f%% | %s |" % [c.name, c.set_id.to_upper(), CardDef.RARITY_NAMES[c.rarity], c.cost, row[2], row[1] * 100, flag])
	_line("\n%d of %d cards flagged." % [flagged, rows.size()])
	# By rarity
	var by_r := {}
	for row in rows:
		var rar: String = CardDB.get_card(row[0]).rarity
		if not by_r.has(rar):
			by_r[rar] = [0.0, 0]
		by_r[rar][0] += row[1] * row[2]
		by_r[rar][1] += row[2]
	_line("\n| Rarity | Avg win rate when in deck |")
	_line("|---|---|")
	for rar in CardDef.RARITIES:
		if by_r.has(rar):
			_line("| %s | %.1f%% |" % [CardDef.RARITY_NAMES[rar], by_r[rar][0] / by_r[rar][1] * 100])


func _random_deck(r: RandomNumberGenerator) -> Dictionary:
	var cols: Array = CardDef.COLORS.duplicate()
	var a: String = cols[r.randi_range(0, 4)]
	cols.erase(a)
	var b: String = cols[r.randi_range(0, 3)]
	var pool: Array = []
	for set_id in CardDB.set_order:
		for id in CardDB.set_card_ids(set_id):
			var c: CardDef = CardDB.get_card(id)
			if c.color in [a, b, "colorless"]:
				pool.append(id)
	var creatures := pool.filter(func(id): return CardDB.get_card(id).is_creature())
	var d := {}
	var size := 0
	var guard := 0
	while size < Deck.SIZE and guard < 2000:
		guard += 1
		var src: Array = creatures if size < 20 else pool
		var id: String = src[r.randi_range(0, src.size() - 1)]
		var c: CardDef = CardDB.get_card(id)
		# Gentle curve: expensive cards are picked less often.
		if c.cost >= 5 and r.randf() < 0.5:
			continue
		if d.get(id, 0) < Deck.copy_limit(id):
			d[id] = d.get(id, 0) + 1
			size += 1
	return d
