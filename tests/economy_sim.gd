extends Node
## Economy simulation: how fast does a typical player earn coins, open packs
## and complete sets? Uses the real pack generator, prices and NPC rewards.
##   godot --headless --path . res://tests/economy_sim.tscn -- [players] [days]
##
## Model of a day (a reasonably engaged player, not a min-maxer):
##  - talk to everyone they meet (friendship), play up to 3 battles against the
##    townsfolk available, choosing the best expected payout;
##  - work Gus's shift once he likes them (2 hearts);
##  - play the Saturday Showdown every week;
##  - sell copies beyond what a deck can use, then spend coins on packs of the
##    least-complete released set. "Completionists" also buy missing singles.

# Player win chance vs each townsperson (from tests/npc_ladder: 1 - their win rate).
const WIN := { "pip": 0.62, "rose": 0.64, "theo": 0.52, "mira": 0.43, "corwin": 0.35, "gus": 0.30 }
const BATTLES_PER_DAY := 3
const TALKS_PER_DAY := 4


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var players := int(args[0]) if args.size() > 0 else 200
	var days := int(args[1]) if args.size() > 1 else 84
	for completionist in [false, true]:
		_report(players, days, completionist)
	get_tree().quit()


func _report(players: int, days: int, completionist: bool) -> void:
	var milestones := {}  # name -> Array of days
	var checkpoints := [7, 14, 28, 56, 84]
	var completion_at := {}  # day -> [hvb%, tff%]
	var packs_at := {}
	var coins_per_day := 0.0
	for pl in players:
		var res := _simulate(pl, days, completionist)
		for k in res["milestones"]:
			if not milestones.has(k):
				milestones[k] = []
			milestones[k].append(res["milestones"][k])
		for d in checkpoints:
			if d <= days:
				if not completion_at.has(d):
					completion_at[d] = [0.0, 0.0]
					packs_at[d] = 0.0
				completion_at[d][0] += res["completion"][d][0] / players
				completion_at[d][1] += res["completion"][d][1] / players
				packs_at[d] += float(res["packs"][d]) / players
		coins_per_day += res["earned"] / float(days) / players
	print("\n## %s, %d simulated players, %d days\n" % ["Completionist (buys missing singles)" if completionist else "Pack opener (packs only)", players, days])
	print("Average earnings: %.0f coins/day (a booster is 100-120)\n" % coins_per_day)
	print("| Day | Packs opened | Hearthvale complete | Tidefall complete |")
	print("|---|---|---|---|")
	for d in checkpoints:
		if completion_at.has(d):
			print("| %d | %.0f | %.0f%% | %.0f%% |" % [d, packs_at[d], completion_at[d][0] * 100, completion_at[d][1] * 100])
	print("\n| Milestone | Median day | 90%% of players by | Never reached |")
	print("|---|---|---|---|")
	for k in ["first_ultra", "first_secret", "all_rares_hvb", "complete_hvb", "complete_tff"]:
		var arr: Array = milestones.get(k, [])
		var reached := arr.filter(func(x): return x >= 0)
		reached.sort()
		var never := players - reached.size()
		# Unreached players count as "later than everyone", so percentiles index past them.
		var med := "-" if reached.size() * 2 < players else str(reached[players / 2])
		var p90 := "-" if reached.size() < players * 0.9 else str(reached[int(players * 0.9) - 1])
		print("| %s | %s | %s | %d%% |" % [k, med, p90, 100 * never / players])


func _simulate(seed_v: int, days: int, completionist: bool) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = 1000 + seed_v
	var col := Collection.new()
	for s in CardDB.starters:
		if s["id"] == "hearthfire_pals":
			for id in s["cards"]:
				col.add(id, false, s["cards"][id])
	var coins := 500
	var earned := 0
	var sealed := 2
	var packs := 0
	var friend := {}
	var milestones := { "first_ultra": -1, "first_secret": -1, "all_rares_hvb": -1, "complete_hvb": -1, "complete_tff": -1 }
	var completion := {}
	var packs_at := {}
	var t: Dictionary = CardDB.products["tournament"]
	var sh: Dictionary = CardDB.products["shift"]
	for day in range(days + 1):
		var released := CardDB.released_sets(day)
		var wd := day % 7
		# Friendship from chatting.
		var met: Array = CardDB.npc_order.duplicate()
		met.shuffle()
		for id in met.slice(0, TALKS_PER_DAY):
			friend[id] = friend.get(id, 0) + 25
		# Battles: best expected payout first, one per townsperson per day.
		var options: Array = []
		for id in CardDB.npc_order:
			var n := CardDB.npc(id)
			if friend.get(id, 0) / 100 < int(n.get("battle_min_hearts", 0)):
				continue
			var rew := int(n.get("reward", 50))
			options.append([id, WIN[id] * rew + (1.0 - WIN[id]) * rew / 4.0])
		options.sort_custom(func(a, b): return a[1] > b[1])
		for o in options.slice(0, BATTLES_PER_DAY):
			var id: String = o[0]
			var rew := int(CardDB.npc(id).get("reward", 50))
			var gain := rew if r.randf() < WIN[id] else rew / 4
			coins += gain
			earned += gain
			friend[id] = friend.get(id, 0) + 30
		# Shift at the shop.
		if friend.get("gus", 0) / 100 >= int(sh["min_hearts"]):
			coins += int(sh["pay"])
			earned += int(sh["pay"])
			friend["gus"] += int(sh["friend_points"])
		# Saturday Showdown.
		if wd == int(t["day"]) and coins >= int(t["entry"]):
			coins -= int(t["entry"])
			var wins := 0
			for i in int(t["rounds"]):
				if r.randf() < 0.5:
					wins += 1
			var prize: Dictionary = t["prizes"][str(wins)]
			coins += int(prize.get("coins", 0))
			earned += int(prize.get("coins", 0))
			sealed += int(prize.get("packs", 0))
		# Sell extras.
		for k in col.counts.keys():
			var parts := Collection.split_key(k)
			var n2 := mini(col.extras(parts[0]), col.count_variant(parts[0], parts[1]))
			if n2 > 0:
				col.remove(parts[0], parts[1], n2)
				var v := n2 * CardDB.sell_price(parts[0], parts[1])
				coins += v
				earned += v
		# Completionists buy the missing rare-or-better singles in today's case.
		if completionist:
			for sg in _singles(day, released):
				if col.count(sg["id"]) == 0 and coins >= sg["price"]:
					coins -= sg["price"]
					col.add(sg["id"], sg["foil"])
		# Buy packs of the least-complete released set.
		while true:
			var target_set: String = released[0]
			for sid in released:
				if col.completion(sid) < col.completion(target_set):
					target_set = sid
			var price := 100 if target_set == "hvb" else 120
			if coins < price:
				break
			coins -= price
			sealed += 1
		# Open everything.
		while sealed > 0:
			sealed -= 1
			var sid2: String = released[0]
			for sid in released:
				if col.completion(sid) < col.completion(sid2):
					sid2 = sid
			for p in PackGenerator.open_pack(sid2, r):
				col.add(p["id"], p["foil"])
				var rar: String = CardDB.get_card(p["id"]).rarity
				if rar == "ultra" and milestones["first_ultra"] < 0:
					milestones["first_ultra"] = day
				if rar == "secret" and milestones["first_secret"] < 0:
					milestones["first_secret"] = day
			packs += 1
		if milestones["all_rares_hvb"] < 0 and CardDB.cards_of_rarity("hvb", "rare").all(func(id): return col.count(id) > 0):
			milestones["all_rares_hvb"] = day
		if milestones["complete_hvb"] < 0 and col.completion("hvb") >= 1.0:
			milestones["complete_hvb"] = day
		if milestones["complete_tff"] < 0 and col.completion("tff") >= 1.0:
			milestones["complete_tff"] = day
		completion[day] = [col.completion("hvb"), col.completion("tff")]
		packs_at[day] = packs
	return { "milestones": milestones, "completion": completion, "packs": packs_at, "earned": earned }


## Same roll as Game._roll_daily_singles, restricted to released sets.
func _singles(day: int, released: Array) -> Array:
	var out: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = hash("singles%d" % day)
	var pool: Array = []
	for sid in released:
		pool += CardDB.set_card_ids(sid)
	var weights := { "common": 0, "uncommon": 30, "rare": 45, "ultra": 20, "secret": 5 }
	for i in 6:
		var rar := PackGenerator.weighted_pick(weights, r)
		var opts := pool.filter(func(id): return CardDB.get_card(id).rarity == rar)
		if opts.is_empty():
			continue
		var id: String = opts[r.randi_range(0, opts.size() - 1)]
		var foil := r.randf() < 0.15
		out.append({ "id": id, "foil": foil, "price": CardDB.single_price(id, foil) })
	return out
