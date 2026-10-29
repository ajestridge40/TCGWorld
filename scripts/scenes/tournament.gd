extends Control
## Saturday Showdown: a short series of best-of-one rounds against townsfolk,
## with prizes scaled by record. State lives in Game.tournament.

var t: Dictionary
var info: Dictionary
var body := VBoxContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UIKit.backdrop(self, Color("3b2c3f"))
	add_child(ToastLayer.new())
	info = CardDB.products["tournament"]
	t = Game.tournament
	if t.is_empty():
		Game.goto("world")
		return
	# Apply the result of the round we just came back from.
	if not Game.battle_result.is_empty():
		var won: bool = Game.battle_result["won"]
		t["results"].append(won)
		if won:
			t["wins"] += 1
			Game.add_xp("tournament_round_win")
			Game.stats["wins"] = int(Game.stats.get("wins", 0)) + 1
			Game.beaten[Game.battle_result["opponent"]] = true
			Game.unlock("first_win")
		else:
			Game.stats["losses"] = int(Game.stats.get("losses", 0)) + 1
		Game.add_friendship(Game.battle_result["opponent"], 20)
		t["round"] += 1
		Game.battle_result = {}
	var p := UIKit.panel()
	p.position = Vector2(180, 30)
	p.custom_minimum_size = Vector2(600, 480)
	add_child(p)
	body.add_theme_constant_override("separation", 12)
	p.add_child(body)
	_render()


func _render() -> void:
	for c in body.get_children():
		c.queue_free()
	var rounds := int(info["rounds"])
	body.add_child(UIKit.label("★ %s ★" % info["name"], 28, UIKit.WOOD, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(UIKit.label("Judge Theo reads the pairings off a clipboard. Gus is making popcorn.", 13, UIKit.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER))
	for i in rounds:
		var opp: String = t["opponents"][i]
		var n := CardDB.npc(opp)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var face := TextureRect.new()
		face.texture = CharacterSprite.texture(n["look"], 0, 0)
		face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		face.custom_minimum_size = Vector2(48, 48)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		h.add_child(face)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(UIKit.label("Round %d vs %s" % [i + 1, n["name"]], 18))
		v.add_child(UIKit.label(n.get("deck_name", ""), 13, UIKit.INK_SOFT))
		h.add_child(v)
		var status := "—"
		var col := UIKit.INK_SOFT
		if i < t["results"].size():
			status = "WIN" if t["results"][i] else "LOSS"
			col = Color("2e7d32") if t["results"][i] else Color("c0392b")
		elif i == t["round"]:
			status = "Up next"
			col = UIKit.TEAL
		h.add_child(UIKit.label(status, 18, col))
		body.add_child(h)
	body.add_child(HSeparator.new())
	var record := "Record: %d-%d" % [t["wins"], t["results"].size() - t["wins"]]
	body.add_child(UIKit.label(record, 18, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
	if t["round"] < rounds:
		var opp_id: String = t["opponents"][t["round"]]
		body.add_child(UIKit.button("Play round %d" % (t["round"] + 1), func(): _play(opp_id)))
		body.add_child(UIKit.button("Drop from the event", _finish))
	else:
		_prizes()


func _play(opp_id: String) -> void:
	Game.battle_request = { "opponent": opp_id, "best_of": 1, "context": "tournament" }
	Game.goto("battle")


func _prizes() -> void:
	var wins := int(t["wins"])
	var prize: Dictionary = info["prizes"].get(str(wins), {})
	var lines: Array = []
	if int(prize.get("coins", 0)) > 0:
		lines.append(UIKit.coins_text(int(prize["coins"])))
	if int(prize.get("packs", 0)) > 0:
		lines.append("%d Hearthvale booster%s" % [int(prize["packs"]), "s" if int(prize["packs"]) > 1 else ""])
	if prize.has("trophy"):
		lines.append("a Showdown trophy!")
	var msg := "Prizes: " + ", ".join(lines) if not lines.is_empty() else "Thanks for playing!"
	body.add_child(UIKit.label(("Undefeated! " if wins == int(info["rounds"]) else "") + msg, 16, UIKit.WOOD, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(UIKit.button("Collect prizes", func(): _collect(prize)))


func _collect(prize: Dictionary) -> void:
	Game.add_coins(int(prize.get("coins", 0)))
	var packs := int(prize.get("packs", 0))
	Game.add_sealed("hvb", "", packs)
	if prize.has("trophy"):
		Game.trophies.append({ "id": prize["trophy"], "day": Game.day })
		Game.unlock("tournament_win")
	Sfx.play("fanfare")
	_finish()


func _finish() -> void:
	Game.tournament = {}
	Game.minutes = maxi(Game.minutes, int(info["to"]) * 60)
	Game.map_id = "shop"
	Game.player_pos = Vector2i(16, 4)
	Game.save_game()
	Game.goto("world")
