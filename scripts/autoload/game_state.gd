extends Node
## Everything about the current save: coins, cards, decks, time, friendships,
## progression. Also owns scene routing so scenes can hand off to each other.

signal coins_changed(amount: int)
signal time_changed(day: int, minutes: int)
signal toast(text: String, kind: String)
signal day_started(day: int)

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const DAY_START := 6 * 60
const DAY_END := 26 * 60          # 2am: you fall asleep wherever you are
const DAYS_PER_SEASON := 28
const SEASONS := ["Spring", "Summer", "Fall", "Winter"]
const WEEKDAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
const POINTS_PER_HEART := 100
const MAX_HEARTS := 10

const SCENES := {
	"menu": "res://scenes/main_menu.tscn",
	"world": "res://scenes/world.tscn",
	"shop": "res://scenes/shop_menu.tscn",
	"packs": "res://scenes/pack_opening.tscn",
	"binder": "res://scenes/binder.tscn",
	"decks": "res://scenes/deck_builder.tscn",
	"battle": "res://scenes/battle.tscn",
	"tournament": "res://scenes/tournament.tscn",
}

var player_name: String = "Sam"
var coins: int = 0
var day: int = 0                  # days since the game began
var minutes: int = DAY_START
var map_id: String = "home"
var player_pos: Vector2i = Vector2i(6, 6)
var player_facing: Vector2i = Vector2i.DOWN
var collection := Collection.new()
var decks: Array = []             # Deck
var active_deck: int = 0
var sealed: Dictionary = {}       # "hvb" / "hvb:collector" -> count
var supplies: Array = []
var playmat: String = ""
var friendship: Dictionary = {}   # npc id -> points
var talked_today: Dictionary = {}
var battled_today: Dictionary = {}
var traded_today: Dictionary = {}
var beaten: Dictionary = {}
var traded_with: Dictionary = {}
var xp: int = 0
var rank: int = 1
var unlocked: Dictionary = {}     # achievement id -> day unlocked
var stats: Dictionary = { "packs": 0, "wins": 0, "losses": 0, "shifts": 0 }
var trophies: Array = []
var tournament: Dictionary = {}   # active tournament run, empty if none
var daily_singles: Array = []     # [{ id, foil, price }]
var flags: Dictionary = {}        # one-off story / event flags

# Scene hand-off ----------------------------------------------------------
var battle_request: Dictionary = {}
var battle_result: Dictionary = {}
var pending_packs: Array = []     # [{ "set": "hvb", "variant": "" }]
var return_scene: String = "world"
var shop_tab: String = ""

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	get_tree().root.theme = UIKit.make_theme()


# ---------------------------------------------------------------- routing

func goto(scene: String) -> void:
	var path: String = SCENES.get(scene, scene)
	get_tree().call_deferred("change_scene_to_file", path)


func open_packs(packs: Array, back_to: String) -> void:
	pending_packs = packs
	return_scene = back_to
	goto("packs")


# ---------------------------------------------------------------- new / save / load

func new_game(p_name: String, starter_id: String) -> void:
	player_name = p_name if p_name.strip_edges() != "" else "Sam"
	coins = 500
	day = 0
	minutes = DAY_START + 120
	map_id = "home"
	player_pos = Vector2i(6, 6)
	collection = Collection.new()
	decks = []
	sealed = { "hvb": 2 }
	supplies = []
	playmat = ""
	friendship = {}
	for id in CardDB.npc_order:
		friendship[id] = 0
	talked_today = {}
	battled_today = {}
	traded_today = {}
	beaten = {}
	traded_with = {}
	xp = 0
	rank = 1
	unlocked = {}
	stats = { "packs": 0, "wins": 0, "losses": 0, "shifts": 0 }
	trophies = []
	tournament = {}
	flags = {}
	for s in CardDB.starters:
		if s["id"] == starter_id:
			var dk := Deck.from_dict({ "name": s["name"], "cards": s["cards"] })
			for id in dk.cards:
				if not CardDB.get_card(id).is_basic():
					collection.add(id, false, dk.cards[id])
			decks.append(dk)
	active_deck = 0
	_roll_daily_singles()
	save_game()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	var d := {
		"version": SAVE_VERSION,
		"player_name": player_name, "coins": coins, "day": day, "minutes": minutes,
		"map_id": map_id, "player_pos": [player_pos.x, player_pos.y],
		"collection": collection.to_dict(),
		"decks": decks.map(func(dk): return dk.to_dict()), "active_deck": active_deck,
		"sealed": sealed, "supplies": supplies, "playmat": playmat,
		"friendship": friendship, "talked_today": talked_today, "battled_today": battled_today,
		"traded_today": traded_today, "beaten": beaten, "traded_with": traded_with,
		"xp": xp, "rank": rank, "unlocked": unlocked, "stats": stats, "trophies": trophies,
		"daily_singles": daily_singles, "flags": flags,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d, "\t"))


func load_game() -> bool:
	if not has_save():
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = parsed
	player_name = d.get("player_name", "Sam")
	coins = int(d.get("coins", 0))
	day = int(d.get("day", 0))
	minutes = int(d.get("minutes", DAY_START))
	map_id = d.get("map_id", "home")
	var pp: Array = d.get("player_pos", [6, 6])
	player_pos = Vector2i(int(pp[0]), int(pp[1]))
	collection = Collection.new()
	collection.load_dict(d.get("collection", {}))
	decks = []
	for dd in d.get("decks", []):
		decks.append(Deck.from_dict(dd))
	active_deck = clampi(int(d.get("active_deck", 0)), 0, max(0, decks.size() - 1))
	sealed = d.get("sealed", {})
	for k in sealed:
		sealed[k] = int(sealed[k])
	supplies = d.get("supplies", [])
	playmat = d.get("playmat", "")
	friendship = d.get("friendship", {})
	for id in CardDB.npc_order:
		friendship[id] = int(friendship.get(id, 0))
	talked_today = d.get("talked_today", {})
	battled_today = d.get("battled_today", {})
	traded_today = d.get("traded_today", {})
	beaten = d.get("beaten", {})
	traded_with = d.get("traded_with", {})
	xp = int(d.get("xp", 0))
	rank = int(d.get("rank", 1))
	unlocked = d.get("unlocked", {})
	stats = d.get("stats", stats)
	trophies = d.get("trophies", [])
	daily_singles = d.get("daily_singles", [])
	flags = d.get("flags", {})
	tournament = {}
	return true


# ---------------------------------------------------------------- coins & xp

func add_coins(n: int) -> void:
	coins += n
	coins_changed.emit(coins)
	if coins >= 2000:
		unlock("rich")


func spend(n: int) -> bool:
	if coins < n:
		return false
	coins -= n
	coins_changed.emit(coins)
	return true


func add_xp(reason: String, mult: int = 1) -> void:
	var gain: int = int(CardDB.achievements.get("xp", {}).get(reason, 0)) * mult
	if gain <= 0:
		return
	xp += gain
	var ranks: Array = CardDB.achievements.get("ranks", [])
	for r in ranks:
		if xp >= int(r["xp"]) and int(r["rank"]) > rank:
			rank = int(r["rank"])
			toast.emit("Collector Rank %d: %s!" % [rank, r["title"]], "rank")
			Sfx.play("fanfare")


func rank_title(r: int = -1) -> String:
	if r < 0:
		r = rank
	for x in CardDB.achievements.get("ranks", []):
		if int(x["rank"]) == r:
			return x["title"]
	return ""


func next_rank_xp() -> int:
	for x in CardDB.achievements.get("ranks", []):
		if int(x["rank"]) == rank + 1:
			return int(x["xp"])
	return -1


func unlock(id: String) -> void:
	if unlocked.has(id):
		return
	unlocked[id] = day
	for a in CardDB.achievements.get("achievements", []):
		if a["id"] == id:
			toast.emit("Achievement: " + a["name"], "achievement")
			Sfx.play("chime")


# ---------------------------------------------------------------- cards

## Add cards (from a pack, or bought as singles); returns which ones are brand new.
func add_pulls(pulls: Array, from_pack: bool = true) -> Array:
	var fresh: Array = []
	for p in pulls:
		var id: String = p["id"]
		if collection.count(id) == 0 and not fresh.has(id):
			fresh.append(id)
		collection.add(id, p.get("foil", false))
		var c: CardDef = CardDB.get_card(id)
		match c.rarity:
			"rare": unlock("first_rare")
			"ultra":
				unlock("first_rare")
				unlock("first_ultra")
			"secret":
				unlock("first_rare")
				unlock("first_secret")
		if p.get("foil", false):
			unlock("first_foil")
	if from_pack:
		stats["packs"] = int(stats.get("packs", 0)) + 1
		unlock("first_pack")
		add_xp("pack_opened")
	add_xp("new_card", fresh.size())
	check_set_completion()
	return fresh


func check_set_completion() -> void:
	for set_id in CardDB.set_order:
		var pct := collection.completion(set_id)
		if pct >= 0.25:
			unlock("set_25")
		if pct >= 0.5:
			unlock("set_50")
		if pct >= 1.0 and not unlocked.has("set_100"):
			unlock("set_100")
			add_xp("set_complete")


func current_deck() -> Deck:
	if decks.is_empty():
		return null
	return decks[clampi(active_deck, 0, decks.size() - 1)]


func max_decks() -> int:
	return 3 + (4 if supplies.has("deckbox_wood") else 0)


func sealed_total() -> int:
	var n := 0
	for k in sealed:
		n += sealed[k]
	return n


func add_sealed(set_id: String, variant: String = "", n: int = 1) -> void:
	var k := set_id + (":" + variant if variant != "" else "")
	sealed[k] = sealed.get(k, 0) + n


func take_sealed_all() -> Array:
	var out: Array = []
	for k in sealed:
		var parts: PackedStringArray = k.split(":")
		for i in sealed[k]:
			out.append({ "set": parts[0], "variant": parts[1] if parts.size() > 1 else "" })
	sealed.clear()
	return out


# ---------------------------------------------------------------- time

func weekday(d: int = -1) -> int:
	return (day if d < 0 else d) % 7


func season_name() -> String:
	return SEASONS[(day / DAYS_PER_SEASON) % 4]


func date_string() -> String:
	return "%s %d, %s" % [WEEKDAYS[weekday()], (day % DAYS_PER_SEASON) + 1, season_name()]


func time_string() -> String:
	var h := (minutes / 60) % 24
	var m := minutes % 60
	var suffix := "am" if h < 12 else "pm"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d%s" % [h12, m, suffix]


func hour() -> float:
	return minutes / 60.0


func advance_time(mins: int) -> void:
	minutes += mins
	time_changed.emit(day, minutes)


func is_too_late() -> bool:
	return minutes >= DAY_END


func sleep() -> void:
	day += 1
	minutes = DAY_START
	talked_today = {}
	battled_today = {}
	traded_today = {}
	map_id = "home"
	player_pos = Vector2i(9, 5)
	_roll_daily_singles()
	save_game()
	day_started.emit(day)
	time_changed.emit(day, minutes)


func _roll_daily_singles() -> void:
	daily_singles = []
	var r := RandomNumberGenerator.new()
	r.seed = hash("singles%d" % day)
	var pool: Array = []
	for set_id in CardDB.set_order:
		pool += CardDB.set_card_ids(set_id)
	var weights := { "common": 0, "uncommon": 30, "rare": 45, "ultra": 20, "secret": 5 }
	for i in 6:
		var rar := PackGenerator.weighted_pick(weights, r)
		var opts := pool.filter(func(id): return CardDB.get_card(id).rarity == rar)
		if opts.is_empty():
			continue
		var id: String = opts[r.randi_range(0, opts.size() - 1)]
		var foil := r.randf() < 0.15
		daily_singles.append({ "id": id, "foil": foil, "price": CardDB.single_price(id, foil) })


# ---------------------------------------------------------------- friendship

func hearts(npc_id: String) -> int:
	return mini(MAX_HEARTS, int(friendship.get(npc_id, 0)) / POINTS_PER_HEART)


func add_friendship(npc_id: String, pts: int) -> void:
	var before := hearts(npc_id)
	friendship[npc_id] = mini(MAX_HEARTS * POINTS_PER_HEART, int(friendship.get(npc_id, 0)) + pts)
	var after := hearts(npc_id)
	if after > before:
		toast.emit("%s: %d hearts!" % [CardDB.npc(npc_id).get("name", npc_id), after], "heart")
		Sfx.play("heart")
	if after >= 4:
		unlock("best_friend")


## Where an NPC is right now, or {} if they're not out and about.
func npc_location(npc_id: String) -> Dictionary:
	var n := CardDB.npc(npc_id)
	var h := hour()
	var wd := weekday()
	for s in n.get("schedule", []):
		var days = s.get("days", "all")
		if typeof(days) == TYPE_ARRAY and not days.has(wd) and not days.has(float(wd)):
			continue
		if h >= float(s["from"]) and h < float(s["to"]):
			return s
	return {}


# ---------------------------------------------------------------- trading

## One daily offer per NPC: a card from their trade binder for one of your
## spare cards of the same rarity. Deterministic per day so it doesn't reroll.
func trade_offer(npc_id: String) -> Dictionary:
	if traded_today.has(npc_id):
		return {}
	var n := CardDB.npc(npc_id)
	var binder: Array = n.get("trade_binder", [])
	if binder.is_empty():
		return {}
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s%d" % [npc_id, day])
	var offered: String = binder[r.randi_range(0, binder.size() - 1)]
	var rar: String = CardDB.get_card(offered).rarity
	var spares: Array = []
	var fallback: Array = []
	for k in collection.counts:
		var parts := Collection.split_key(k)
		var id: String = parts[0]
		var c: CardDef = CardDB.get_card(id)
		if c == null or c.is_basic() or id == offered or c.rarity != rar:
			continue
		if collection.count(id) >= 2:
			spares.append(k)
		elif collection.count(id) == 1:
			fallback.append(k)
	var pool := spares if not spares.is_empty() else fallback
	if pool.is_empty():
		return {}
	pool.sort()
	var want_key: String = pool[r.randi_range(0, pool.size() - 1)]
	var wp := Collection.split_key(want_key)
	return { "give": offered, "want": wp[0], "want_foil": wp[1] }


func accept_trade(npc_id: String, offer: Dictionary) -> bool:
	if not collection.remove(offer["want"], offer["want_foil"]):
		return false
	var fresh := collection.count(offer["give"]) == 0
	collection.add(offer["give"], false)
	traded_today[npc_id] = true
	traded_with[npc_id] = true
	add_friendship(npc_id, 20)
	add_xp("trade")
	if fresh:
		add_xp("new_card")
	unlock("first_trade")
	var all_traded := true
	for id in CardDB.npc_order:
		if not traded_with.has(id):
			all_traded = false
	if all_traded:
		unlock("trade_everyone")
	check_set_completion()
	return true


# ---------------------------------------------------------------- battles

## Called by the battle scene when a match is over.
func record_battle(npc_id: String, won: bool, context: String) -> int:
	var reward := 0
	if won:
		stats["wins"] = int(stats.get("wins", 0)) + 1
		unlock("first_win")
		add_xp("battle_win")
		beaten[npc_id] = true
		var everyone := true
		for id in CardDB.npc_order:
			if not beaten.has(id):
				everyone = false
		if everyone:
			unlock("beat_everyone")
	else:
		stats["losses"] = int(stats.get("losses", 0)) + 1
		add_xp("battle_loss")
	if context == "casual":
		if won and not battled_today.has(npc_id):
			reward = int(CardDB.npc(npc_id).get("reward", 50))
		elif not battled_today.has(npc_id):
			reward = int(CardDB.npc(npc_id).get("reward", 50)) / 4
		if not battled_today.has(npc_id):
			add_friendship(npc_id, 30)
		battled_today[npc_id] = true
		add_coins(reward)
		advance_time(60)
	return reward
