extends Control
## Battle table. Drives BattleEngine for the human (seat 0) and BattleAI (seat 1).
## Request comes from Game.battle_request: { opponent, best_of, context }.

signal player_done

const CX := 180.0          # center column x
const CW := 570.0          # center column width
const CREATURE_W := 64.0
const HAND_W := 78.0
const ROW_OPP_LANDS := 10.0
const ROW_OPP := 46.0
const ROW_ME := 252.0
const ROW_MY_LANDS := 362.0
const ROW_HAND := 404.0

var engine: BattleEngine
var ai: BattleAI
var npc: Dictionary
var npc_id := ""
var best_of := 1
var context := "casual"
var score := [0, 0]
var game_no := 0

var mode := "idle"          # idle | main | attack | blocks | tricks | target | over
var busy := false
var sel_attackers: Array = []
var block_assign: Dictionary = {}   # attacker uid -> blocker uid
var sel_blocker := -1
var pending: BattleEngine.CardInstance
var pending_targets: Array = []
var _prev_mode := ""

var board := Control.new()
var arrows: ArrowLayer
var views: Dictionary = {}          # uid -> CardView (battlefield + hand)
var last_rects: Dictionary = {}     # uid -> Rect2 (for effects after a card leaves)
var opp_panel: PanelContainer
var me_panel: PanelContainer
var opp_life := UIKit.label("20", 34, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
var me_life := UIKit.label("20", 34, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
var opp_info := UIKit.label("", 12, UIKit.INK_SOFT)
var me_info := UIKit.label("", 12, UIKit.INK_SOFT)
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
	var mid := ColorRect.new()
	mid.color = Color(1, 1, 1, 0.08)
	mid.position = Vector2(CX, 203)
	mid.size = Vector2(CW, 2)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mid)
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	arrows = ArrowLayer.new()
	arrows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(arrows)

	opp_panel = _player_panel(npc.get("name", "?"), npc.get("deck_name", ""), npc.get("look", {}), opp_life, opp_info)
	opp_panel.position = Vector2(6, 6)
	add_child(opp_panel)
	me_panel = _player_panel(Game.player_name, Game.current_deck().name, CharacterSprite.PLAYER_LOOK, me_life, me_info)
	me_panel.position = Vector2(6, 384)
	add_child(me_panel)
	opp_panel.gui_input.connect(func(ev): _on_player_clicked(ev, 1))
	me_panel.gui_input.connect(func(ev): _on_player_clicked(ev, 0))

	var phase_p := UIKit.panel()
	phase_p.position = Vector2(6, 166)
	phase_p.custom_minimum_size = Vector2(164, 208)
	add_child(phase_p)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	phase_p.add_child(pv)
	pv.add_child(turn_label)
	phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	phase_label.custom_minimum_size = Vector2(144, 70)
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

	banner.position = Vector2(CX, 186)
	banner.size = Vector2(CW, 36)
	banner.add_theme_color_override("font_outline_color", Color("2a211c"))
	banner.add_theme_constant_override("outline_size", 8)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	result_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result_layer.visible = false
	add_child(result_layer)
	add_child(ToastLayer.new())


func _player_panel(pname: String, sub: String, look: Dictionary, life_l: Label, info_l: Label) -> PanelContainer:
	var p := UIKit.panel()
	p.custom_minimum_size = Vector2(164, 150)
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
	face.custom_minimum_size = Vector2(48, 48)
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
	v.add_child(life_l)
	v.add_child(info_l)
	return p


# ================================================================ game flow

func _deck_list(cards: Dictionary) -> Array:
	return Deck.from_dict({ "cards": cards }).to_list()


func _new_game() -> void:
	game_no += 1
	engine = BattleEngine.new()
	engine.event.connect(_on_event)
	engine.setup(Game.current_deck().to_list(), _deck_list(npc["deck"]), Game.player_name, npc["name"])
	log_box.clear()
	views.clear()
	for c in board.get_children():
		c.queue_free()
	engine.start()
	var who := "You go" if engine.active == 0 else "%s goes" % npc["name"]
	await _show_banner(("Game %d · " % game_no if best_of > 1 else "") + who + " first", 1.0)
	_turn_flow()


func _turn_flow() -> void:
	if engine.is_over():
		_game_over()
		return
	_refresh()
	if engine.active == 0:
		await _show_banner("Your turn", 0.6)
		_set_mode("main")
	else:
		await _ai_turn()


func _set_mode(m: String) -> void:
	mode = m
	if m != "target":
		pending = null
		pending_targets = []
	_refresh()


func _ai_turn() -> void:
	busy = true
	_set_mode("idle")
	await _show_banner("%s's turn" % npc["name"], 0.6)
	await _ai_main_phase()
	if engine.is_over():
		busy = false
		_game_over()
		return
	var atk: Array = ai.choose_attackers(engine, 1)
	engine.declare_attackers(atk)
	_refresh()
	if engine.phase == BattleEngine.Phase.BLOCKS:
		Sfx.play("thump", 0.8)
		await _wait(0.5)
		busy = false
		block_assign = {}
		sel_blocker = -1
		_set_mode("blocks")
		await player_done
		busy = true
		engine.declare_blocks(block_assign)
		block_assign = {}
		_refresh()
		await _combat_tricks()
	if engine.is_over():
		busy = false
		_game_over()
		return
	await _ai_main_phase()
	if engine.is_over():
		busy = false
		_game_over()
		return
	await _wait(0.3)
	engine.end_turn()
	busy = false
	_turn_flow()


func _ai_main_phase() -> void:
	while not engine.is_over():
		var act: Dictionary = ai.next_main_action(engine, 1)
		if act.is_empty():
			break
		await _wait(0.55)
		engine.cast(1, act["card"], act["target"])
		_refresh()
	await _wait(0.3)


## Trick window: attacker acts first, then defender. Handles both seats.
func _combat_tricks() -> void:
	while engine.phase == BattleEngine.Phase.TRICKS and not engine.is_over():
		if engine.trick_player == 1:
			var tr: Dictionary = ai.next_trick(engine, 1)
			if tr.is_empty():
				engine.pass_tricks()
			else:
				await _wait(0.5)
				engine.cast(1, tr["card"], tr["target"])
				_refresh()
				await _wait(0.4)
		else:
			if _has_playable_instant():
				busy = false
				_set_mode("tricks")
				await player_done
				busy = true
			engine.pass_tricks()
		_refresh()
	await _wait(0.35)


func _has_playable_instant() -> bool:
	for c in engine.me(0).hand:
		if c.def.is_instant() and engine.can_pay(0, c.def):
			return true
	return false


# ================================================================ player actions

func _on_main_button() -> void:
	if busy:
		return
	match mode:
		"main":
			if engine.combat_done:
				_end_my_turn()
			else:
				var able: Array = engine.me(0).battlefield.filter(func(c): return c.can_attack())
				if able.is_empty():
					_end_my_turn()
				else:
					sel_attackers = []
					_set_mode("attack")
		"attack":
			_confirm_attack()
		"blocks":
			player_done.emit()
		"tricks":
			player_done.emit()
		"target":
			_set_mode(_prev_mode)


func _on_alt_button() -> void:
	if busy:
		return
	match mode:
		"main":
			_end_my_turn()
		"attack":
			sel_attackers = []
			_set_mode("main")
		"blocks":
			block_assign = {}
			sel_blocker = -1
			_refresh()


func _end_my_turn() -> void:
	if engine.active != 0 or engine.phase != BattleEngine.Phase.MAIN:
		return
	busy = true
	_set_mode("idle")
	engine.end_turn()
	busy = false
	_turn_flow()


func _confirm_attack() -> void:
	busy = true
	engine.declare_attackers(sel_attackers)
	sel_attackers = []
	_set_mode("idle")
	if engine.phase == BattleEngine.Phase.BLOCKS:
		Sfx.play("thump", 0.8)
		await _wait(0.6)
		engine.declare_blocks(ai.choose_blocks(engine, 1))
		_refresh()
		await _wait(0.5)
		await _combat_tricks()
	busy = false
	if engine.is_over():
		_game_over()
	else:
		_set_mode("main")


func _on_card_clicked(view: CardView, button: int) -> void:
	if busy or mode in ["idle", "over"]:
		return
	if button == MOUSE_BUTTON_RIGHT:
		if mode == "target":
			_set_mode(_prev_mode)
		return
	var uid := view.instance_uid
	var hand_card = _hand_card(uid)
	if mode == "target":
		_try_target({ "kind": "creature", "uid": uid })
		return
	if hand_card:
		_try_cast(hand_card)
		return
	var c := engine.find(uid)
	if c == null:
		return
	match mode:
		"attack":
			if c.owner == 0 and c.can_attack():
				if sel_attackers.has(uid):
					sel_attackers.erase(uid)
				else:
					sel_attackers.append(uid)
				Sfx.play("click")
				_refresh()
		"blocks":
			if c.owner == 0 and not c.tapped:
				for a in block_assign.keys():
					if block_assign[a] == uid:
						block_assign.erase(a)
				sel_blocker = uid if sel_blocker != uid else -1
				Sfx.play("click")
				_refresh()
			elif c.owner == 1 and engine.attackers.has(uid) and sel_blocker != -1:
				if engine.can_block(sel_blocker, uid):
					for a in block_assign.keys():
						if block_assign[a] == sel_blocker:
							block_assign.erase(a)
					block_assign[uid] = sel_blocker
					sel_blocker = -1
					Sfx.play("play")
				else:
					_nope("That creature can't block this attacker (flying?).")
				_refresh()


func _hand_card(uid: int):
	for c in engine.me(0).hand:
		if c.uid == uid:
			return c
	return null


func _try_cast(c) -> void:
	if c.def.is_land():
		if engine.play_land(0, c):
			Sfx.play("play", 0.8)
			_refresh()
		else:
			_nope("You've already played a land this turn." if engine.active == 0 else "Lands can only be played on your turn.")
		return
	if not engine.can_cast(0, c):
		if not engine.can_pay(0, c.def):
			_nope("Not enough mana.")
		elif mode == "tricks" and not c.def.is_instant():
			_nope("Only instants during combat.")
		elif engine.active != 0:
			_nope("Wait for your turn (or a combat trick window).")
		else:
			_nope("No legal targets.")
		return
	var te: Dictionary = c.def.targeted_effect()
	if te.is_empty():
		_do_cast(c, {})
		return
	var legal := engine.legal_targets(0, te)
	if legal.is_empty():
		_do_cast(c, {})
		return
	_prev_mode = mode
	pending = c
	pending_targets = legal
	mode = "target"
	_refresh()


func _try_target(t: Dictionary) -> void:
	for l in pending_targets:
		if l.get("kind") == t.get("kind") and l.get("uid", -1) == t.get("uid", -1) and l.get("index", -1) == t.get("index", -1):
			var c = pending
			mode = _prev_mode
			_do_cast(c, l)
			return
	_nope("Not a legal target. (Right-click to cancel.)")


func _do_cast(c, target: Dictionary) -> void:
	if engine.cast(0, c, target):
		Sfx.play("play")
		pending = null
		pending_targets = []
		_refresh()
		if engine.is_over():
			_game_over()
	else:
		_nope("Can't cast that right now.")


func _on_player_clicked(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and mode == "target":
		_try_target({ "kind": "player", "index": idx })


func _nope(msg: String) -> void:
	Sfx.play("nope")
	phase_label.text = msg


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_ESCAPE and mode == "target":
			_set_mode(_prev_mode)
		elif ev.keycode == KEY_SPACE and not busy and btn_main.visible and not btn_main.disabled:
			_on_main_button()


# ================================================================ rendering

func _refresh() -> void:
	if engine == null:
		return
	var me: BattleEngine.PlayerState = engine.me(0)
	var op: BattleEngine.PlayerState = engine.me(1)
	opp_life.text = str(op.life)
	me_life.text = str(me.life)
	opp_info.text = "Hand %d · Library %d" % [op.hand.size(), op.library.size()]
	me_info.text = "Library %d · Discard %d" % [me.library.size(), me.graveyard.size()]
	var target_player := func(i): return mode == "target" and pending_targets.any(func(t): return t.get("kind") == "player" and t.get("index") == i)
	opp_panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.PAPER, UIKit.GOLD if target_player.call(1) else UIKit.WOOD, 4 if target_player.call(1) else 3))
	me_panel.add_theme_stylebox_override("panel", UIKit.panel_style(UIKit.PAPER, UIKit.GOLD if target_player.call(0) else UIKit.WOOD, 4 if target_player.call(0) else 3))
	_update_controls()
	# Rebuild board views.
	var old := views
	views = {}
	for c in board.get_children():
		board.remove_child(c)
		c.queue_free()
	_layout_lands(op, ROW_OPP_LANDS)
	_layout_lands(me, ROW_MY_LANDS)
	_layout_creatures(op.battlefield, ROW_OPP, old)
	_layout_creatures(me.battlefield, ROW_ME, old)
	_layout_hand(me.hand, old)
	_update_arrows()


func _update_controls() -> void:
	var my_turn := engine.active == 0
	turn_label.text = "Turn %d · %s" % [engine.turn, "You" if my_turn else npc["name"]]
	if best_of > 1:
		turn_label.text += "\nMatch %d-%d" % score
	btn_alt.visible = false
	btn_main.visible = true
	btn_main.disabled = false
	match mode:
		"main":
			if engine.combat_done:
				phase_label.text = "Main phase (after combat). Cast spells, then end your turn."
				btn_main.text = "End turn"
			else:
				phase_label.text = "Main phase. Play a land, cast spells, then attack."
				var able: Array = engine.me(0).battlefield.filter(func(c): return c.can_attack())
				btn_main.text = "Attack..." if not able.is_empty() else "End turn"
				btn_alt.visible = not able.is_empty()
				btn_alt.text = "End turn"
		"attack":
			phase_label.text = "Click your creatures to choose attackers."
			btn_main.text = "Attack (%d)" % sel_attackers.size() if not sel_attackers.is_empty() else "Skip combat"
			btn_alt.visible = true
			btn_alt.text = "Cancel"
		"blocks":
			phase_label.text = "%s attacks! Click one of your creatures, then the attacker it should block." % npc["name"]
			btn_main.text = "Confirm blocks" if not block_assign.is_empty() else "No blocks"
			btn_alt.visible = not block_assign.is_empty()
			btn_alt.text = "Clear"
		"tricks":
			phase_label.text = "Combat trick window. Cast an instant, or continue."
			btn_main.text = "Continue"
		"target":
			phase_label.text = "Choose a target for %s. (Right-click to cancel)" % pending.def.name
			btn_main.text = "Cancel"
		"over":
			btn_main.visible = false
		_:
			phase_label.text = "%s is thinking..." % npc["name"] if not my_turn else "..."
			btn_main.visible = false


func _layout_lands(p: BattleEngine.PlayerState, y: float) -> void:
	var by_color := {}
	for l in p.lands:
		var col: String = l.def.produces
		if not by_color.has(col):
			by_color[col] = [0, 0]
		by_color[col][1] += 1
		if not l.tapped:
			by_color[col][0] += 1
	var x := CX + 6
	for col in CardDef.COLORS:
		if not by_color.has(col):
			continue
		var chip := Panel.new()
		var st := UIKit.panel_style(UIKit.CARD_COLORS[col], UIKit.CARD_COLORS[col].darkened(0.4), 2, 10)
		chip.add_theme_stylebox_override("panel", st)
		chip.position = Vector2(x, y)
		chip.size = Vector2(70, 28)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.tooltip_text = "%s: %d untapped of %d" % [CardDef.COLOR_NAMES[col], by_color[col][0], by_color[col][1]]
		var l := UIKit.label("%d / %d" % by_color[col], 14, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		l.add_theme_color_override("font_outline_color", Color("2a211c"))
		l.add_theme_constant_override("outline_size", 4)
		l.size = chip.size
		chip.add_child(l)
		board.add_child(chip)
		x += 76


func _layout_creatures(list: Array, y: float, old: Dictionary) -> void:
	var n := list.size()
	if n == 0:
		return
	var w := clampf(CW / n - 30.0, 40.0, CREATURE_W)
	var slot := w + 30.0
	var start := CX + CW / 2 - slot * n / 2.0 + 15.0
	for i in n:
		var c: BattleEngine.CardInstance = list[i]
		var cv := CardView.make(c.def, w)
		cv.instance_uid = c.uid
		cv.power_override = c.power()
		cv.toughness_override = c.toughness()
		cv.damage = c.damage
		cv.pivot_offset = cv.size / 2
		cv.position = Vector2(start + i * slot, y + (110 - cv.size.y) / 2.0)
		if c.tapped:
			cv.rotation_degrees = 90
		if c.sick and not c.has_kw("haste") and c.owner == engine.active and engine.active == 0:
			cv.badge = "zzz"
			cv.badge_color = UIKit.INK_SOFT
		cv.highlight = _creature_highlight(c)
		cv.clicked.connect(_on_card_clicked)
		cv.hovered.connect(_on_hover)
		board.add_child(cv)
		views[c.uid] = cv
		last_rects[c.uid] = Rect2(cv.position, cv.size)
		if not old.has(c.uid):
			cv.scale = Vector2(0.3, 0.3)
			create_tween().tween_property(cv, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _creature_highlight(c: BattleEngine.CardInstance) -> Color:
	if mode == "target":
		for t in pending_targets:
			if t.get("kind") == "creature" and t.get("uid") == c.uid:
				return Color(UIKit.GOLD, 0.9)
		return Color(0, 0, 0, 0)
	if engine.attackers.has(c.uid) or sel_attackers.has(c.uid):
		return Color(UIKit.ROSE, 0.95)
	if mode == "attack" and c.owner == 0 and c.can_attack():
		return Color(1, 1, 1, 0.35)
	if mode == "blocks":
		if c.uid == sel_blocker:
			return Color(UIKit.TEAL, 0.95)
		if block_assign.values().has(c.uid):
			return Color(UIKit.TEAL, 0.6)
		if c.owner == 0 and not c.tapped:
			return Color(1, 1, 1, 0.35)
	if engine.blocks.values().has(c.uid):
		return Color(UIKit.TEAL, 0.8)
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
		var playable := false
		if c.def.is_land():
			playable = engine.can_play_land(0, c) and mode == "main"
		else:
			playable = engine.can_cast(0, c) and mode in ["main", "tricks"]
		cv.dim = not playable and mode != "target"
		cv.highlight = Color(UIKit.LEAF, 0.8) if playable else Color(0, 0, 0, 0)
		if pending and pending.uid == c.uid:
			cv.highlight = Color(UIKit.GOLD, 1)
		cv.position = Vector2(start + i * step, ROW_HAND + 10 + absf(i - (n - 1) / 2.0) * 2.0)
		cv.rotation_degrees = (i - (n - 1) / 2.0) * 1.5
		cv.clicked.connect(_on_card_clicked)
		cv.hovered.connect(func(v, on):
			_on_hover(v, on)
			if is_instance_valid(v):
				v.position.y += -24 if on else 24
				v.z_index = 5 if on else 0)
		board.add_child(cv)
		views[c.uid] = cv
		if not old.has(c.uid):
			cv.position.y += 120
			create_tween().tween_property(cv, "position:y", cv.position.y - 120, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _update_arrows() -> void:
	var lines: Array = []
	var center := func(uid):
		var r: Rect2 = last_rects.get(uid, Rect2())
		return r.position + r.size / 2
	for a in engine.attackers:
		if engine.blocks.has(a):
			lines.append([center.call(engine.blocks[a]), center.call(a), UIKit.TEAL])
		else:
			var to := opp_panel.position + Vector2(160, 70) if engine.active == 0 else me_panel.position + Vector2(160, 70)
			lines.append([center.call(a), to, UIKit.ROSE])
	for a in block_assign:
		lines.append([center.call(block_assign[a]), center.call(a), UIKit.TEAL])
	arrows.lines = lines
	arrows.queue_redraw()


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
		_preview.toughness_override = c.toughness()
		_preview.damage = c.damage
	preview_holder.add_child(_preview)


# ================================================================ events & juice

func _on_event(kind: String, d: Dictionary) -> void:
	match kind:
		"log":
			var t: String = d["text"]
			if t.begins_with("--"):
				log_box.append_text("[color=#6b4a32][b]%s[/b][/color]\n" % t)
			else:
				log_box.append_text(t + "\n")
		"player_damage":
			var panel := opp_panel if d["player"] == 1 else me_panel
			_float_text("-%d" % d["amount"], panel.position + Vector2(122, 62), Color("ff6b6b"))
			_pulse(opp_life if d["player"] == 1 else me_life)
			Sfx.play("hit", 1.0 + randf() * 0.2)
		"life_gain":
			var panel2 := opp_panel if d["player"] == 1 else me_panel
			_float_text("+%d" % d["amount"], panel2.position + Vector2(18, 62), Color("7bd389"))
			Sfx.play("chime", 1.3, -8.0)
		"creature_damage":
			var r: Rect2 = last_rects.get(d["uid"], Rect2())
			if r.size != Vector2.ZERO:
				_float_text("-%d" % d["amount"], r.position + Vector2(r.size.x / 2 - 8, 10), Color("ffb347"))
		"leave":
			var r2: Rect2 = last_rects.get(d["uid"], Rect2())
			if r2.size != Vector2.ZERO:
				_poof(r2)
		"draw":
			if d["player"] == 0:
				Sfx.play("flip", 1.1, -8.0)
		"pump":
			Sfx.play("chime", 1.6, -10.0)
		"game_over":
			pass


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
			_new_game()))
		return
	var lines: Array = npc.get("win_lines" if match_won else "lose_lines", [""])
	var quote := UIKit.label("\"%s\"" % lines[randi() % lines.size()], 14, UIKit.INK_SOFT, HORIZONTAL_ALIGNMENT_CENTER)
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.custom_minimum_size.x = 330
	v.add_child(quote)
	if context == "casual":
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


## Draws attack / block lines over the board.
class ArrowLayer:
	extends Control
	var lines: Array = []

	func _draw() -> void:
		for l in lines:
			var a: Vector2 = l[0]
			var b: Vector2 = l[1]
			var c: Color = l[2]
			if a == Vector2.ZERO or b == Vector2.ZERO:
				continue
			draw_line(a, b, Color(0, 0, 0, 0.4), 6.0)
			draw_line(a, b, c, 3.0)
			var dir := (b - a).normalized()
			var side := dir.orthogonal() * 7.0
			draw_colored_polygon(PackedVector2Array([b, b - dir * 12.0 + side, b - dir * 12.0 - side]), c)


class StarField:
	extends Control
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var r := RandomNumberGenerator.new()
		r.seed = 99
		for i in 120:
			draw_rect(Rect2(r.randf() * size.x, r.randf() * size.y, 2, 2), Color(1, 1, 0.9, r.randf_range(0.2, 0.7)))
