extends Control
## Sparkfolk table. Drives BattleEngine for the human (seat 0) and BattleAI (seat 1).
## Request comes from Game.battle_request: { opponent, best_of, context }.

const CX := 180.0          # center column x
const CW := 570.0          # center column width
const LANE_W := CW / BattleEngine.LANES
const CARD_W := 88.0
const HAND_W := 84.0
const ROW_OPP := 16.0
const ROW_ME := 206.0
const ROW_HAND := 392.0

var engine: BattleEngine
var ai: BattleAI
var npc: Dictionary
var npc_id := ""
var best_of := 1
var context := "casual"
var score := [0, 0]
var game_no := 0

var mode := "idle"          # idle | play | place | target | move | attack | over
var busy := false
var sel_attackers: Array = []
var pending: BattleEngine.CardInstance
var pending_lane := -1
var pending_targets: Array = []
var move_uid := -1
var _last_ok := false

var board := Control.new()
var lane_slots: Array = []          # [player][lane] -> Panel
var views: Dictionary = {}          # uid -> CardView
var last_rects: Dictionary = {}     # uid -> Rect2
var _queue: Array = []              # engine events waiting to be animated
var opp_panel: PanelContainer
var me_panel: PanelContainer
var opp_life := UIKit.label("20", 30, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
var me_life := UIKit.label("20", 30, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
var opp_info := UIKit.label("", 12, UIKit.INK_SOFT)
var me_info := UIKit.label("", 12, UIKit.INK_SOFT)
var opp_sparks: SparkMeter
var me_sparks: SparkMeter
var turn_label := UIKit.label("", 16, UIKit.WOOD, HORIZONTAL_ALIGNMENT_CENTER)
var phase_label := UIKit.label("", 13, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
var btn_main: Button
var btn_alt: Button
var log_box := RichTextLabel.new()
var preview_holder := Control.new()
var _preview: CardView
var banner := UIKit.label("", 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
var result_layer := Control.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var req := Game.battle_request
	npc_id = req.get("opponent", "pip")
	npc = CardDB.npc(npc_id)
	best_of = int(req.get("best_of", 1))
	context = req.get("context", "casual")
	ai = BattleAI.new(float(npc.get("aggression", 0.5)))
	if context == "tutorial":
		ai.aggression = float(CardDB.tutorial.get("aggression", 0.3))
	_build_ui()
	_new_game()


# ================================================================ UI build

func _playmat_color() -> Color:
	match Game.playmat:
		"playmat_meadow": return Color("3f6b45")
		"playmat_starry": return Color("1f2a4a")
	return Color("4a3a30")


func _build_ui() -> void:
	UIKit.backdrop(self, Color("2a211c"))
	var mat := Panel.new()
	mat.add_theme_stylebox_override("panel", UIKit.panel_style(_playmat_color(), Color("1a1410"), 3, 12))
	mat.position = Vector2(CX - 6, 4)
	mat.size = Vector2(CW + 12, 532)
	mat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mat)
	if Game.playmat == "playmat_starry":
		var stars := StarField.new()
		stars.position = mat.position
		stars.size = mat.size
		add_child(stars)
	# Lane strips + clickable slots.
	for pl in 2:
		var row: Array = []
		for l in BattleEngine.LANES:
			var slot := Panel.new()
			slot.position = Vector2(CX + l * LANE_W + 6, (ROW_OPP if pl == 1 else ROW_ME) - 6)
			slot.size = Vector2(LANE_W - 12, CARD_W * 1.4 + 12)
			slot.mouse_filter = Control.MOUSE_FILTER_STOP
			var lane := l
			var who := pl
			slot.gui_input.connect(func(ev): _on_slot_input(ev, who, lane))
			add_child(slot)
			row.append(slot)
		lane_slots.append(row)
	for l in BattleEngine.LANES:
		var n := UIKit.label("%d" % (l + 1), 12, Color(1, 1, 1, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
		n.position = Vector2(CX + l * LANE_W, 158 + 22)
		n.size = Vector2(LANE_W, 16)
		add_child(n)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)

	opp_sparks = SparkMeter.new()
	me_sparks = SparkMeter.new()
	opp_panel = _player_panel(npc.get("name", "?"), "Teaching Deck" if context == "tutorial" else npc.get("deck_name", ""), npc.get("look", {}), opp_life, opp_info, opp_sparks)
	opp_panel.position = Vector2(6, 6)
	add_child(opp_panel)
	var my_deck_name: String = CardDB.tutorial.get("player_deck_name", "") if context == "tutorial" else Game.current_deck().name
	me_panel = _player_panel(Game.player_name, my_deck_name, CharacterSprite.PLAYER_LOOK, me_life, me_info, me_sparks)
	me_panel.position = Vector2(6, 372)
	add_child(me_panel)
	opp_panel.gui_input.connect(func(ev): _on_player_clicked(ev, 1))
	me_panel.gui_input.connect(func(ev): _on_player_clicked(ev, 0))

	var phase_p := UIKit.panel()
	phase_p.position = Vector2(6, 170)
	phase_p.custom_minimum_size = Vector2(164, 194)
	add_child(phase_p)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	phase_p.add_child(pv)
	pv.add_child(turn_label)
	phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phase_label.custom_minimum_size = Vector2(144, 62)
	pv.add_child(phase_label)
	btn_main = UIKit.button("", _on_main_button)
	pv.add_child(btn_main)
	btn_alt = UIKit.button("", _on_alt_button)
	pv.add_child(btn_alt)

	preview_holder.position = Vector2(762, 6)
	preview_holder.size = Vector2(192, 269)
	preview_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(preview_holder)
	var lp := UIKit.panel(Color("fbf4e2"))
	lp.position = Vector2(762, 282)
	lp.custom_minimum_size = Vector2(192, 252)
	lp.size = lp.custom_minimum_size
	add_child(lp)
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.custom_minimum_size = Vector2(172, 232)
	log_box.add_theme_font_size_override("normal_font_size", 11)
	log_box.add_theme_color_override("default_color", UIKit.INK)
	lp.add_child(log_box)
	if context == "tutorial":
		lp.visible = false
		_build_coach()

	banner.position = Vector2(CX, 172)
	banner.size = Vector2(CW, 36)
	banner.add_theme_color_override("font_outline_color", Color("2a211c"))
	banner.add_theme_constant_override("outline_size", 8)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.visible = false
	add_child(result_layer)
	add_child(ToastLayer.new())


func _player_panel(pname: String, sub: String, look: Dictionary, life_l: Label, info_l: Label, meter: SparkMeter) -> PanelContainer:
	var p := UIKit.panel()
	p.custom_minimum_size = Vector2(164, 158)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var h := HBoxContainer.new()
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(h)
	var face := TextureRect.new()
	face.texture = CharacterSprite.texture(look, 0, 0)
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.custom_minimum_size = Vector2(44, 44)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(face)
	var nv := VBoxContainer.new()
	nv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(nv)
	nv.add_child(UIKit.label(pname, 16, UIKit.WOOD))
	var s := UIKit.label(sub, 11, UIKit.INK_SOFT)
	s.clip_text = true
	s.custom_minimum_size.x = 96
	nv.add_child(s)
	var lh := HBoxContainer.new()
	lh.alignment = BoxContainer.ALIGNMENT_CENTER
	lh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lh.add_child(UIKit.label("♥", 22, UIKit.ROSE))
	lh.add_child(life_l)
	v.add_child(lh)
	meter.custom_minimum_size = Vector2(144, 18)
	v.add_child(meter)
	v.add_child(info_l)
	return p


# ================================================================ game flow

func _deck_list(cards: Dictionary) -> Array:
	return Deck.from_dict({ "cards": cards }).to_list()


func _new_game() -> void:
	game_no += 1
	engine = BattleEngine.new()
	engine.event.connect(_on_event)
	if context == "tutorial":
		engine.setup(CardDB.tutorial["player_deck"], CardDB.tutorial["gus_deck"], Game.player_name, npc["name"], 7, { "first": 0, "stacked": true })
	else:
		engine.setup(Game.current_deck().to_list(), _deck_list(Game.npc_deck(npc_id)), Game.player_name, npc["name"])
	log_box.clear()
	views.clear()
	for c in board.get_children():
		c.queue_free()
	busy = true
	await _act(engine.start)
	var who := "You go" if engine.active == 0 else "%s goes" % npc["name"]
	await _show_banner(("Game %d · " % game_no if best_of > 1 else "") + who + " first", 1.0)
	busy = false
	_turn_flow()


func _turn_flow() -> void:
	if engine.is_over():
		_game_over()
		return
	_refresh()
	if engine.active == 0:
		await _show_banner("Your turn", 0.5)
		_set_mode("play")
	else:
		await _ai_turn()


func _set_mode(m: String) -> void:
	mode = m
	if m != "target" and m != "place":
		pending = null
		pending_lane = -1
		pending_targets = []
	if m != "move":
		move_uid = -1
	_refresh()


## Run an engine action, then animate whatever it emitted.
func _act(f: Callable) -> void:
	_queue.clear()
	f.call()
	await _play_queue()
	_refresh()


func _ai_turn() -> void:
	busy = true
	_set_mode("idle")
	await _show_banner("%s's turn" % npc["name"], 0.5)
	await _ai_actions()
	if not engine.is_over():
		var atk: Array = ai.choose_attackers(engine, 1)
		if not atk.is_empty():
			await _wait(0.3)
			await _act(func(): engine.attack(atk))
	if not engine.is_over():
		await _ai_actions()
	if engine.is_over():
		busy = false
		_game_over()
		return
	await _wait(0.3)
	await _act(engine.end_turn)
	busy = false
	_turn_flow()


func _ai_actions() -> void:
	var guard := 0
	while not engine.is_over() and guard < 30:
		guard += 1
		var act: Dictionary = ai.next_action(engine, 1)
		if act.is_empty():
			break
		await _wait(0.5)
		if act["kind"] == "move":
			await _act(func(): engine.move(1, act["uid"], act["lane"]))
		else:
			await _act(func(): engine.play(1, act["card"], act["lane"], act["target"]))


# ================================================================ player actions

func _on_main_button() -> void:
	if busy:
		return
	match mode:
		"play":
			if _attack_candidates().is_empty():
				_end_my_turn()
			else:
				sel_attackers = _attack_candidates().filter(func(c): return _forecast(c) != "dies").map(func(c): return c.uid)
				_set_mode("attack")
		"attack":
			_confirm_attack()
		"place", "target", "move":
			_set_mode("play")


func _on_alt_button() -> void:
	if busy:
		return
	match mode:
		"play":
			_end_my_turn()
		"attack":
			sel_attackers = []
			_set_mode("play")


func _attack_candidates() -> Array:
	return engine.me(0).creatures().filter(func(c): return engine.can_attack(c))


func _end_my_turn() -> void:
	if not engine.is_my_turn(0):
		return
	busy = true
	_set_mode("idle")
	await _act(engine.end_turn)
	busy = false
	_turn_flow()


func _confirm_attack() -> void:
	busy = true
	var list := sel_attackers.duplicate()
	sel_attackers = []
	_set_mode("idle")
	await _act(func(): engine.attack(list))
	busy = false
	if engine.is_over():
		_game_over()
	else:
		_set_mode("play")


func _on_card_clicked(view: CardView, button: int) -> void:
	if busy or mode in ["idle", "over"]:
		return
	if button == MOUSE_BUTTON_RIGHT:
		if mode in ["place", "target", "move"]:
			_set_mode("play")
		return
	var uid := view.instance_uid
	if mode == "target":
		_try_target({ "kind": "creature", "uid": uid })
		return
	var hand_card = _hand_card(uid)
	if hand_card:
		if mode in ["play", "place", "move"]:
			_try_play(hand_card)
		return
	var c := engine.find(uid)
	if c == null:
		return
	if mode == "place" and c.owner == 0:
		choose_lane(c.lane)
		return
	match mode:
		"attack":
			if c.owner == 0 and engine.can_attack(c):
				if sel_attackers.has(uid):
					sel_attackers.erase(uid)
				else:
					sel_attackers.append(uid)
				Sfx.play("click")
				_refresh()
		"play", "move":
			if c.owner == 0 and not engine.move_options(0, uid).is_empty():
				move_uid = uid
				_set_mode("move")
			elif c.owner == 0 and c.has_kw("move"):
				_nope("It has already moved, or there's no empty lane next to it.")


func _on_slot_input(ev: InputEvent, who: int, lane: int) -> void:
	if not (ev is InputEventMouseButton and ev.pressed):
		return
	if ev.button_index == MOUSE_BUTTON_RIGHT:
		if mode in ["place", "target", "move"]:
			_set_mode("play")
		return
	if busy or who != 0:
		return
	choose_lane(lane)


## Player picked one of their lanes (to place a creature or move one).
func choose_lane(lane: int) -> void:
	if mode == "place":
		pending_lane = lane
		var te: Dictionary = pending.def.targeted_effect()
		var legal := engine.legal_targets(0, te) if not te.is_empty() else []
		if legal.is_empty():
			_do_play(pending, lane, {})
		else:
			pending_targets = legal
			mode = "target"
			_refresh()
	elif mode == "move" and engine.move_options(0, move_uid).has(lane):
		var uid := move_uid
		busy = true
		await _act(func(): engine.move(0, uid, lane))
		Sfx.play("play", 1.3)
		busy = false
		_set_mode("play")


func _hand_card(uid: int):
	for c in engine.me(0).hand:
		if c.uid == uid:
			return c
	return null


func _try_play(c) -> void:
	if not engine.can_play(0, c):
		if c.def.cost > engine.me(0).sparks:
			_nope("Not enough Sparks.")
		else:
			_nope("Nothing to target right now.")
		return
	pending = c
	if c.def.is_creature():
		mode = "place"
		_refresh()
		return
	var te: Dictionary = c.def.targeted_effect()
	var legal := engine.legal_targets(0, te) if not te.is_empty() else []
	if legal.is_empty():
		_do_play(c, -1, {})
	else:
		pending_targets = legal
		mode = "target"
		_refresh()


func _try_target(t: Dictionary) -> void:
	for l in pending_targets:
		if l.get("kind") == t.get("kind") and l.get("uid", -1) == t.get("uid", -1) and l.get("index", -1) == t.get("index", -1):
			_do_play(pending, pending_lane, l)
			return
	_nope("Not a legal target. (Right-click to cancel.)")


func _do_play(c, lane: int, target: Dictionary) -> void:
	busy = true
	_set_mode("idle")
	await _act(func(): _last_ok = engine.play(0, c, lane, target))
	busy = false
	if _last_ok:
		Sfx.play("play")
	else:
		Sfx.play("nope")
	if engine.is_over():
		_game_over()
	else:
		_set_mode("play")


func _on_player_clicked(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and mode == "target":
		_try_target({ "kind": "player", "index": idx })


func _nope(msg: String) -> void:
	Sfx.play("nope")
	phase_label.text = msg


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_ESCAPE and mode in ["place", "target", "move"]:
			_set_mode("play")
		elif ev.keycode == KEY_SPACE and not busy and btn_main.visible and not btn_main.disabled:
			_on_main_button()


## What will happen if this creature attacks now: "face", "kill", "trade", "hit", "dies".
func _forecast(c) -> String:
	var b := engine.blocker_for(c)
	if b == null:
		return "face"
	var k := BattleAI.kills(c, b)
	var d := BattleAI.kills(b, c)
	if k and d:
		return "trade"
	if k:
		return "kill"
	if d:
		return "dies"
	return "hit"


# ================================================================ rendering

func _refresh() -> void:
	if engine == null:
		return
	var me: BattleEngine.PlayerState = engine.me(0)
	var op: BattleEngine.PlayerState = engine.me(1)
	opp_life.text = str(op.life)
	me_life.text = str(me.life)
	opp_sparks.set_values(op.sparks, op.max_sparks)
	me_sparks.set_values(me.sparks, me.max_sparks)
	opp_info.text = "Hand %d · Deck %d" % [op.hand.size(), op.library.size()]
	me_info.text = "Deck %d · Discard %d" % [me.library.size(), me.graveyard.size()]
	for i in 2:
		var targetable := mode == "target" and pending_targets.any(func(t): return t.get("kind") == "player" and t.get("index") == i)
		var panel := opp_panel if i == 1 else me_panel
		panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.PAPER, UIKit.GOLD if targetable else UIKit.WOOD, 4 if targetable else 3))
	_style_slots()
	_update_controls()
	var old := views
	views = {}
	for c in board.get_children():
		board.remove_child(c)
		c.queue_free()
	for pl in 2:
		for c in engine.me(pl).lanes:
			if c:
				_layout_creature(c, old)
	_layout_hand(me.hand, old)
	if context == "tutorial":
		_update_coach()


func _style_slots() -> void:
	for pl in 2:
		for l in BattleEngine.LANES:
			var col := Color(1, 1, 1, 0.06)
			var border := Color(1, 1, 1, 0.12)
			if pl == 0 and mode == "place":
				var free: bool = engine.empty_lanes(0).has(l)
				col = Color(UIKit.LEAF, 0.35) if free else Color(UIKit.GOLD, 0.25)
				border = UIKit.LEAF if free else UIKit.GOLD
			elif pl == 0 and mode == "move" and engine.move_options(0, move_uid).has(l):
				col = Color(UIKit.TEAL, 0.35)
				border = UIKit.TEAL
			var st := UIKit.panel_style(col, border, 2, 8)
			st.shadow_size = 0
			lane_slots[pl][l].add_theme_stylebox_override("panel", st)


func _update_controls() -> void:
	var my_turn := engine.active == 0
	turn_label.text = "Turn %d · %s" % [engine.turn, "You" if my_turn else npc["name"]]
	if best_of > 1:
		turn_label.text += "\nMatch %d-%d" % score
	btn_alt.visible = false
	btn_main.visible = true
	btn_main.disabled = false
	match mode:
		"play":
			var can_atk := not _attack_candidates().is_empty()
			phase_label.text = "Play cards with your Sparks, then attack." if can_atk else "Play cards with your Sparks, then end your turn."
			btn_main.text = "Attack..." if can_atk else "End turn"
			btn_alt.visible = can_atk
			btn_alt.text = "End turn"
		"attack":
			phase_label.text = "Click creatures to choose who attacks. Badges show what will happen."
			btn_main.text = "Attack! (%d)" % sel_attackers.size() if not sel_attackers.is_empty() else "Don't attack"
			btn_alt.visible = true
			btn_alt.text = "Cancel"
		"place":
			phase_label.text = "Choose a lane for %s. (Playing over your own creature sends it home.)" % pending.def.name
			btn_main.text = "Cancel"
		"target":
			phase_label.text = "Choose a target for %s." % pending.def.name
			btn_main.text = "Cancel"
		"move":
			phase_label.text = "Click a highlighted lane to move there."
			btn_main.text = "Cancel"
		"over":
			btn_main.visible = false
		_:
			phase_label.text = "%s is thinking..." % npc["name"] if not my_turn else "..."
			btn_main.visible = false


func _lane_pos(pl: int, lane: int) -> Vector2:
	return Vector2(CX + lane * LANE_W + (LANE_W - CARD_W) / 2.0, ROW_OPP if pl == 1 else ROW_ME)


func _layout_creature(c: BattleEngine.CardInstance, old: Dictionary) -> void:
	var cv := CardView.make(c.def, CARD_W)
	cv.instance_uid = c.uid
	cv.power_override = c.power()
	cv.health_override = c.max_health()
	cv.damage = c.damage
	cv.shielded = c.shield
	cv.frozen = c.frozen > 0
	cv.position = _lane_pos(c.owner, c.lane)
	cv.pivot_offset = cv.size / 2
	if c.owner == engine.active and c.fresh and not c.has_kw("swift"):
		cv.badge = "zzz"
		cv.badge_color = UIKit.INK_SOFT
	cv.highlight = _creature_highlight(c)
	if mode == "attack" and c.owner == 0 and engine.can_attack(c):
		var f := _forecast(c)
		var labels := { "face": "→ %d" % c.power(), "kill": "KO!", "trade": "trade", "hit": "hit", "dies": "dies" }
		var cols := { "face": UIKit.GOLD.darkened(0.2), "kill": Color("2e7d32"), "trade": UIKit.TEAL, "hit": UIKit.INK_SOFT, "dies": Color("c0392b") }
		cv.badge = labels[f]
		cv.badge_color = cols[f]
		if not sel_attackers.has(c.uid):
			cv.dim = true
	cv.clicked.connect(_on_card_clicked)
	cv.hovered.connect(_on_hover)
	board.add_child(cv)
	views[c.uid] = cv
	last_rects[c.uid] = Rect2(cv.position, cv.size)
	if not old.has(c.uid):
		cv.scale = Vector2(0.3, 0.3)
		cv.create_tween().tween_property(cv, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _creature_highlight(c: BattleEngine.CardInstance) -> Color:
	if mode == "target":
		for t in pending_targets:
			if t.get("kind") == "creature" and t.get("uid") == c.uid:
				return Color(UIKit.GOLD, 0.9)
		return Color(0, 0, 0, 0)
	if sel_attackers.has(c.uid):
		return Color(UIKit.ROSE, 0.95)
	if mode == "move" and c.uid == move_uid:
		return Color(UIKit.TEAL, 0.95)
	if mode == "play" and c.owner == 0 and not engine.move_options(0, c.uid).is_empty():
		return Color(UIKit.TEAL, 0.35)
	return Color(0, 0, 0, 0)


func _layout_hand(hand: Array, old: Dictionary) -> void:
	var n := hand.size()
	if n == 0:
		return
	var step := minf(HAND_W + 6.0, (CW - HAND_W) / maxf(1.0, n - 1))
	var total := step * (n - 1) + HAND_W
	var start := CX + (CW - total) / 2.0
	for i in n:
		var c: BattleEngine.CardInstance = hand[i]
		var cv := CardView.make(c.def, HAND_W)
		cv.instance_uid = c.uid
		var playable := engine.can_play(0, c) and mode in ["play", "place", "move"]
		cv.dim = not playable and mode != "target"
		cv.highlight = Color(UIKit.LEAF, 0.8) if playable else Color(0, 0, 0, 0)
		if pending and pending.uid == c.uid:
			cv.highlight = Color(UIKit.GOLD, 1)
		cv.position = Vector2(start + i * step, ROW_HAND + 14 + absf(i - (n - 1) / 2.0) * 2.0)
		cv.rotation_degrees = (i - (n - 1) / 2.0) * 1.5
		cv.clicked.connect(_on_card_clicked)
		cv.hovered.connect(func(v, on):
			_on_hover(v, on)
			if is_instance_valid(v):
				v.position.y += -26 if on else 26
				v.z_index = 5 if on else 0)
		board.add_child(cv)
		views[c.uid] = cv
		if not old.has(c.uid):
			cv.position.y += 120
			cv.create_tween().tween_property(cv, "position:y", cv.position.y - 120, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _on_hover(v: CardView, on: bool) -> void:
	if not on or not is_instance_valid(v):
		return
	if _preview:
		_preview.queue_free()
	_preview = CardView.make(v.card, 192)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := engine.find(v.instance_uid)
	if c:
		_preview.power_override = c.power()
		_preview.health_override = c.max_health()
		_preview.damage = c.damage
		_preview.shielded = c.shield
		_preview.frozen = c.frozen > 0
	preview_holder.add_child(_preview)


# ================================================================ events & juice

func _on_event(kind: String, d: Dictionary) -> void:
	if kind == "log":
		var t: String = d["text"]
		if t.begins_with("--"):
			log_box.append_text("[color=#6b4a32][b]%s[/b][/color]\n" % t)
		else:
			log_box.append_text(t + "\n")
		return
	_queue.append([kind, d])


func _play_queue() -> void:
	var q := _queue.duplicate()
	_queue.clear()
	for item in q:
		var kind: String = item[0]
		var d: Dictionary = item[1]
		match kind:
			"clash":
				await _lunge(d)
			"player_damage":
				var panel := opp_panel if d["player"] == 1 else me_panel
				_float_text("-%d" % d["amount"], panel.position + Vector2(118, 54), Color("ff6b6b"))
				_pulse(opp_life if d["player"] == 1 else me_life)
				_shake_panel(panel)
				Sfx.play("hit", 1.0 + randf() * 0.2)
			"life_gain":
				var panel2 := opp_panel if d["player"] == 1 else me_panel
				_float_text("+%d" % d["amount"], panel2.position + Vector2(20, 54), Color("7bd389"))
				Sfx.play("chime", 1.3, -8.0)
			"creature_damage":
				var r: Rect2 = last_rects.get(d["uid"], Rect2())
				if r.size != Vector2.ZERO:
					_float_text("-%d" % d["amount"], r.position + Vector2(r.size.x / 2 - 8, 20), Color("ffb347"))
			"shield_pop":
				var r3: Rect2 = last_rects.get(d["uid"], Rect2())
				if r3.size != Vector2.ZERO:
					_float_text("pop!", r3.position + Vector2(r3.size.x / 2 - 14, 30), Color("9fe4ff"))
				Sfx.play("flip", 1.8)
			"leave":
				var r2: Rect2 = last_rects.get(d["uid"], Rect2())
				if r2.size != Vector2.ZERO:
					_poof(r2)
				if views.has(d["uid"]) and is_instance_valid(views[d["uid"]]):
					views[d["uid"]].visible = false
				await _wait(0.12)
			"enter":
				Sfx.play("thump", 1.2, -6.0)
				_refresh()
				await _wait(0.15)
			"move":
				var v: CardView = views.get(d["uid"])
				if v and is_instance_valid(v):
					var owner_pl := 0 if engine.find(d["uid"]) and engine.find(d["uid"]).owner == 0 else 1
					var tw := create_tween()
					tw.tween_property(v, "position", _lane_pos(owner_pl, d["to"]), 0.25).set_trans(Tween.TRANS_CUBIC)
					await tw.finished
			"buff":
				Sfx.play("chime", 1.6, -10.0)
			"freeze":
				Sfx.play("chime", 0.7, -6.0)
			"draw":
				if d["player"] == 0:
					Sfx.play("flip", 1.1, -8.0)


func _lunge(d: Dictionary) -> void:
	var v: CardView = views.get(d["attacker"])
	if v == null or not is_instance_valid(v):
		return
	var start := v.position
	var dir := 1.0 if d["player"] == 1 else -1.0
	var target := start + Vector2(0, dir * 70.0)
	if d["blocker"] == -1:
		target = start + Vector2(0, dir * 120.0)
	v.z_index = 10
	var tw := create_tween()
	tw.tween_property(v, "position", target, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): Sfx.play("hit", 0.8 + randf() * 0.3, -4.0))
	tw.tween_property(v, "position", start, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw.finished
	if is_instance_valid(v):
		v.z_index = 0


func _float_text(t: String, at: Vector2, c: Color) -> void:
	var l := UIKit.label(t, 22, c)
	l.add_theme_color_override("font_outline_color", Color("2a211c"))
	l.add_theme_constant_override("outline_size", 6)
	l.position = at
	l.z_index = 20
	add_child(l)
	var tw := create_tween().set_parallel()
	tw.tween_property(l, "position:y", at.y - 40, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


func _pulse(l: Label) -> void:
	l.pivot_offset = l.size / 2
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2(1.3, 1.3), 0.08)
	tw.tween_property(l, "scale", Vector2.ONE, 0.2)


func _shake_panel(p: Control) -> void:
	var base := p.position
	var tw := create_tween()
	for i in 4:
		tw.tween_property(p, "position", base + Vector2(randf_range(-4, 4), randf_range(-2, 2)), 0.03)
	tw.tween_property(p, "position", base, 0.03)


func _poof(r: Rect2) -> void:
	var p := CPUParticles2D.new()
	p.position = r.position + r.size / 2
	p.amount = 24
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = 0.7
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = r.size / 2
	p.direction = Vector2(0, -1)
	p.spread = 60
	p.initial_velocity_min = 30
	p.initial_velocity_max = 90
	p.gravity = Vector2(0, -40)
	p.scale_amount_min = 2
	p.scale_amount_max = 4
	p.color = Color(0.9, 0.85, 0.75, 0.8)
	p.z_index = 15
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func _show_banner(text: String, hold: float) -> void:
	banner.text = text
	banner.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.15)
	tw.tween_interval(hold)
	tw.tween_property(banner, "modulate:a", 0.0, 0.25)
	await tw.finished


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


# ================================================================ results

func _game_over() -> void:
	if mode == "over":
		return
	_set_mode("over")
	var won := engine.winner == 0
	score[0 if won else 1] += 1
	Sfx.play("win" if won else "lose")
	var need := best_of / 2 + 1
	var match_over: bool = score[0] >= need or score[1] >= need
	await _wait(0.6)
	_show_result(won, match_over)


func _show_result(won_game: bool, match_over: bool) -> void:
	for c in result_layer.get_children():
		c.queue_free()
	result_layer.visible = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.add_child(dim)
	var p := UIKit.panel()
	p.position = Vector2(300, 140)
	p.custom_minimum_size = Vector2(360, 0)
	result_layer.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var match_won: bool = score[0] > score[1]
	var title := ("You win!" if won_game else "%s wins." % npc["name"])
	if match_over and best_of > 1:
		title = "Match won %d-%d!" % score if match_won else "Match lost %d-%d." % score
	v.add_child(UIKit.label(title, 26, UIKit.WOOD, HORIZONTAL_ALIGNMENT_CENTER))
	if not match_over:
		v.add_child(UIKit.label("Match score %d-%d. Shuffle up for the next game." % score, 14, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(UIKit.button("Next game", func():
			result_layer.visible = false
			mode = "idle"
			_new_game()))
		return
	var lines: Array = npc.get("win_lines" if match_won else "lose_lines", [""])
	var quote := UIKit.label("\"%s\"" % lines[randi() % lines.size()], 14, UIKit.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.custom_minimum_size.x = 330
	v.add_child(quote)
	if context == "tutorial":
		_finish_tutorial(v, match_won)
	elif context == "casual":
		var reward := Game.record_battle(npc_id, match_won, context)
		if reward > 0:
			v.add_child(UIKit.label("+%s" % UIKit.coins_text(reward), 18, Color("2e7d32"), HORIZONTAL_ALIGNMENT_CENTER))
			Sfx.play("coin")
	elif context == "tournament":
		Game.battle_result = { "won": match_won, "opponent": npc_id }
	v.add_child(UIKit.button("Continue", _leave))


func _leave() -> void:
	Game.save_game()
	Game.goto("tournament" if context == "tournament" else Game.return_scene)


# ================================================================ tutorial

var coach_text := RichTextLabel.new()
var _coach_seen := {}
var _coach_current := ""
var _coach_turn := 0


func _build_coach() -> void:
	var cp := UIKit.panel(Color("fffaf0"), UIKit.GOLD)
	cp.position = Vector2(762, 282)
	cp.custom_minimum_size = Vector2(192, 252)
	cp.size = cp.custom_minimum_size
	add_child(cp)
	var v := VBoxContainer.new()
	cp.add_child(v)
	var h := HBoxContainer.new()
	var face := TextureRect.new()
	face.texture = CharacterSprite.texture(npc.get("look", {}), 0, 0)
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.custom_minimum_size = Vector2(32, 32)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	h.add_child(face)
	h.add_child(UIKit.label("Gus says...", 14, UIKit.WOOD))
	v.add_child(h)
	coach_text.bbcode_enabled = true
	coach_text.fit_content = true
	coach_text.custom_minimum_size = Vector2(172, 190)
	coach_text.add_theme_font_size_override("normal_font_size", 12)
	coach_text.add_theme_font_size_override("bold_font_size", 12)
	coach_text.add_theme_color_override("default_color", UIKit.INK)
	v.add_child(coach_text)


## Is this tip's moment now? Tips show once, in priority order.
func _tip_ready(id: String) -> bool:
	var me: BattleEngine.PlayerState = engine.me(0)
	var op: BattleEngine.PlayerState = engine.me(1)
	var my_turn := engine.active == 0
	match id:
		"welcome":
			return my_turn and engine.turn == 1 and me.creatures().is_empty()
		"attack_mode":
			return mode == "attack"
		"swift":
			return my_turn and mode == "play" and not engine.attacked and me.creatures().any(func(c): return engine.can_attack(c))
		"end_turn":
			return my_turn and engine.attacked and mode == "play"
		"opp_turn":
			return not my_turn
		"fight":
			return my_turn and me.creatures().any(func(c): return engine.blocker_for(c) != null)
		"guard":
			return my_turn and engine.turn >= 3 and _coach_seen.has("fight")
		"more_sparks":
			return my_turn and me.max_sparks >= 2
		"shield":
			return op.creatures().any(func(c): return c.shield)
		"soar":
			return op.creatures().any(func(c): return c.has_kw("soar"))
		"spell":
			return my_turn and engine.turn >= 3 and mode == "play" and me.hand.any(func(c): return c.def.is_spell() and engine.can_play(0, c))
		"full":
			return my_turn and engine.empty_lanes(0).is_empty() and me.hand.any(func(c): return c.def.is_creature())
		"low":
			return op.life <= 8
		"free":
			return _coach_seen.size() >= 8
	return false


func _update_coach() -> void:
	# Keep the current tip up while it still applies (within the same turn),
	# so tips don't flash past when several become true at once.
	if _coach_current != "" and _coach_turn == engine.turn and _tip_ready(_coach_current):
		return
	for tip in CardDB.tutorial.get("tips", []):
		var id: String = tip["id"]
		if _coach_seen.has(id) or not _tip_ready(id):
			continue
		_coach_seen[id] = true
		_coach_current = id
		_coach_turn = engine.turn
		coach_text.text = tip["text"]
		coach_text.visible_ratio = 0.0
		create_tween().tween_property(coach_text, "visible_ratio", 1.0, 0.8)
		Sfx.play("chime", 1.4, -10.0)
		return


func _finish_tutorial(v: VBoxContainer, won: bool) -> void:
	var first_time: bool = not Game.flags.get("tutorial_done", false)
	var msg := "Not bad at all for a first game." if won else "Ha! Don't feel bad. I've had thirty years of practice."
	if first_time:
		var packs := int(CardDB.tutorial.get("reward_packs", 2))
		Game.flags["tutorial_done"] = true
		Game.add_sealed("hvb", "", packs)
		Game.add_friendship("gus", int(CardDB.tutorial.get("reward_friendship", 50)))
		msg += " Here, take %d boosters on the house. Build something you love." % packs
		Sfx.play("fanfare")
	var l := UIKit.label(msg, 14, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 330
	v.add_child(l)


## Row of Spark orbs: lit = available this turn, dim = spent, hollow = not yet earned.
class SparkMeter:
	extends Control
	var cur := 0
	var top := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_values(c: int, m: int) -> void:
		cur = c
		top = m
		tooltip_text = "Sparks: %d / %d" % [c, m]
		queue_redraw()

	func _draw() -> void:
		var rad := 5.5
		var font := get_theme_default_font()
		draw_string(font, Vector2(0, 13), "%d/%d" % [cur, top], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.INK)
		for i in BattleEngine.MAX_SPARKS:
			var c := Vector2(38 + i * 11.0, 9)
			if i < cur:
				draw_circle(c, rad, CardView.SPARK)
				draw_circle(c + Vector2(-1.5, -1.5), 1.6, Color(1, 1, 1, 0.7))
			elif i < top:
				draw_circle(c, rad, Color("8a7a60"))
			else:
				draw_arc(c, rad - 0.5, 0, TAU, 12, Color(0, 0, 0, 0.25), 1.0)
		if cur > BattleEngine.MAX_SPARKS:
			draw_string(font, Vector2(38 + 10 * 11.0 - 4, 13), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UIKit.INK)


class StarField:
	extends Control
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := RandomNumberGenerator.new()
		r.seed = 99
		for i in 120:
			draw_rect(Rect2(r.randf() * size.x, r.randf() * size.y, 2, 2), Color(1, 1, 0.9, r.randf_range(0.2, 0.7)))
