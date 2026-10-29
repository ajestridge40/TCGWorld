class_name BattleEngine
extends RefCounted
## Rules engine for a two-player Magic-style duel. Pure logic, no nodes:
## the battle scene and the AI drive it by calling the action methods below,
## and listen to `event` to animate what happened.
##
## Turn: untap -> start-of-turn triggers -> draw -> MAIN (play a land, cast
## spells) -> optional COMBAT (declare attackers -> defender blocks -> trick
## window for instants, attacker first then defender -> damage) -> MAIN -> end.
##
## Simplifications vs. Magic: no stack (spells resolve immediately), instants
## are only castable in your own main phase or the combat trick window, one
## blocker per attacker, and a free "cozy mulligan" for land-flood/screw hands.

signal event(kind: String, data: Dictionary)

enum Phase { MAIN, BLOCKS, TRICKS, GAME_OVER }

const START_LIFE := 20
const START_HAND := 7
const MAX_HAND := 8

var players: Array = []          # [PlayerState, PlayerState]
var active: int = 0
var turn: int = 0
var phase: Phase = Phase.MAIN
var combat_done: bool = false
var attackers: Array = []        # uids
var blocks: Dictionary = {}      # attacker uid -> blocker uid
var trick_player: int = -1       # who may currently cast tricks
var winner: int = -1
var rng := RandomNumberGenerator.new()
var _next_uid: int = 1
var log_lines: Array = []


class PlayerState:
	var index: int
	var name: String
	var life: int = 20
	var library: Array = []      # card ids, top = back
	var hand: Array = []         # CardInstance
	var battlefield: Array = []  # CardInstance (creatures)
	var lands: Array = []        # CardInstance (lands)
	var graveyard: Array = []    # card ids
	var land_played: bool = false

	func untapped_lands() -> Array:
		return lands.filter(func(l): return not l.tapped)


class CardInstance:
	var uid: int
	var def: CardDef
	var owner: int
	var tapped: bool = false
	var sick: bool = true        # summoning sickness
	var damage: int = 0
	var counters: int = 0        # +1/+1 counters
	var temp_power: int = 0
	var temp_toughness: int = 0
	var temp_keywords: Array = []

	func power() -> int:
		return def.power + counters + temp_power

	func toughness() -> int:
		return def.toughness + counters + temp_toughness

	func has_kw(k: String) -> bool:
		return def.has_keyword(k) or temp_keywords.has(k)

	func can_attack() -> bool:
		return def.is_creature() and not tapped and (not sick or has_kw("haste")) and not has_kw("defender") and power() > 0

	func can_block_creature(att: CardInstance) -> bool:
		if tapped:
			return false
		if att.has_kw("flying") and not (has_kw("flying") or has_kw("reach")):
			return false
		return true

	func clear_temp() -> void:
		temp_power = 0
		temp_toughness = 0
		temp_keywords.clear()
		damage = 0


# ---------------------------------------------------------------- setup

func setup(deck_a: Array, deck_b: Array, name_a: String, name_b: String, seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	players = []
	for i in 2:
		var p := PlayerState.new()
		p.index = i
		p.name = name_a if i == 0 else name_b
		p.life = START_LIFE
		p.library = (deck_a if i == 0 else deck_b).duplicate()
		_shuffle(p.library)
		players.append(p)
	winner = -1
	turn = 0
	active = rng.randi_range(0, 1)
	for p in players:
		_draw_opening_hand(p)


func _draw_opening_hand(p: PlayerState) -> void:
	for attempt in 2:
		for i in START_HAND:
			_draw(p, false)
		var lands := p.hand.filter(func(c): return c.def.is_land()).size()
		if attempt == 0 and (lands <= 1 or lands >= 6):
			# Cozy mulligan: shuffle back and redraw once, no penalty.
			for c in p.hand:
				p.library.append(c.def.id)
			p.hand.clear()
			_shuffle(p.library)
			_log("%s takes a free mulligan." % p.name)
			continue
		break


func start() -> void:
	_begin_turn(true)


func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


func _make_instance(id_or_def, owner: int) -> CardInstance:
	var ci := CardInstance.new()
	ci.uid = _next_uid
	_next_uid += 1
	ci.def = id_or_def if id_or_def is CardDef else CardDB.get_card(id_or_def)
	ci.owner = owner
	return ci


func _log(s: String) -> void:
	log_lines.append(s)
	event.emit("log", { "text": s })


# ---------------------------------------------------------------- queries

func me(i: int) -> PlayerState:
	return players[i]


func opp(i: int) -> PlayerState:
	return players[1 - i]


func find(uid: int) -> CardInstance:
	for p in players:
		for c in p.battlefield:
			if c.uid == uid:
				return c
	return null


func is_over() -> bool:
	return phase == Phase.GAME_OVER


func available_mana(pi: int) -> Dictionary:
	var pool := {}
	for l in me(pi).untapped_lands():
		pool[l.def.produces] = pool.get(l.def.produces, 0) + 1
	return pool


func can_pay(pi: int, def: CardDef) -> bool:
	return _plan_payment(pi, def) != null


## Picks which lands to tap. Colored costs first; for generic, tap lands of the
## color least needed by the rest of the hand. Returns null if unaffordable.
func _plan_payment(pi: int, def: CardDef):
	var free: Array = me(pi).untapped_lands()
	var chosen: Array = []
	for col in def.cost_colors:
		for i in int(def.cost_colors[col]):
			var idx := -1
			for j in free.size():
				if free[j].def.produces == col:
					idx = j
					break
			if idx < 0:
				return null
			chosen.append(free[idx])
			free.remove_at(idx)
	if free.size() < def.cost_generic:
		return null
	var demand := {}
	for c in me(pi).hand:
		for col in c.def.cost_colors:
			demand[col] = demand.get(col, 0) + int(c.def.cost_colors[col])
	free.sort_custom(func(a, b): return demand.get(a.def.produces, 0) < demand.get(b.def.produces, 0))
	for i in def.cost_generic:
		chosen.append(free[i])
	return chosen


func is_main_phase_for(pi: int) -> bool:
	return phase == Phase.MAIN and active == pi


func can_play_land(pi: int, ci: CardInstance) -> bool:
	return ci.def.is_land() and is_main_phase_for(pi) and not me(pi).land_played


func can_cast(pi: int, ci: CardInstance) -> bool:
	if ci.def.is_land():
		return can_play_land(pi, ci)
	if phase == Phase.GAME_OVER:
		return false
	var timing_ok := false
	if is_main_phase_for(pi):
		timing_ok = true
	elif phase == Phase.TRICKS and trick_player == pi and ci.def.is_instant():
		timing_ok = true
	if not timing_ok:
		return false
	if not can_pay(pi, ci.def):
		return false
	# A spell whose only purpose is a target needs at least one legal target.
	var te := ci.def.targeted_effect()
	if ci.def.is_spell() and not te.is_empty() and legal_targets(pi, te).is_empty():
		return false
	return true


## Targets are { "kind": "player", "index": i } or { "kind": "creature", "uid": n }.
func legal_targets(pi: int, effect: Dictionary) -> Array:
	var out: Array = []
	var t: String = effect.get("target", "")
	var min_power := int(effect.get("min_power", -999))
	if t == "any":
		out.append({ "kind": "player", "index": 1 - pi })
		out.append({ "kind": "player", "index": pi })
	for p in players:
		for c in p.battlefield:
			var ok := false
			match t:
				"any", "creature": ok = true
				"enemy_creature": ok = c.owner != pi
				"own_creature": ok = c.owner == pi
			if ok and c.power() >= min_power:
				out.append({ "kind": "creature", "uid": c.uid })
	return out


# ---------------------------------------------------------------- turn flow

func _begin_turn(first: bool = false) -> void:
	turn += 1
	var p := me(active)
	p.land_played = false
	combat_done = false
	attackers.clear()
	blocks.clear()
	phase = Phase.MAIN
	for c in p.battlefield:
		c.tapped = false
		c.sick = false
	for l in p.lands:
		l.tapped = false
	event.emit("turn_start", { "player": active, "turn": turn })
	_log("-- Turn %d: %s --" % [turn, p.name])
	# The player going first skips their first draw, like Magic.
	if not (first and turn == 1):
		_draw(p, true)


func _draw(p: PlayerState, announce: bool) -> void:
	if p.library.is_empty():
		if announce:
			_log("%s has no cards left to draw!" % p.name)
			_lose(p.index)
		return
	var ci := _make_instance(p.library.pop_back(), p.index)
	p.hand.append(ci)
	if announce:
		event.emit("draw", { "player": p.index, "uid": ci.uid })


func play_land(pi: int, ci: CardInstance) -> bool:
	if not can_play_land(pi, ci):
		return false
	var p := me(pi)
	p.hand.erase(ci)
	p.lands.append(ci)
	p.land_played = true
	_log("%s plays %s." % [p.name, ci.def.name])
	event.emit("land", { "player": pi, "uid": ci.uid })
	return true


## Cast a card from hand. `target` must be supplied if the card needs one.
func cast(pi: int, ci: CardInstance, target: Dictionary = {}) -> bool:
	if ci.def.is_land():
		return play_land(pi, ci)
	if not can_cast(pi, ci):
		return false
	var te := ci.def.targeted_effect()
	if not te.is_empty():
		var legal := legal_targets(pi, te)
		if legal.is_empty():
			target = {}
		elif not _target_in(target, legal):
			return false
	var payment = _plan_payment(pi, ci.def)
	for l in payment:
		l.tapped = true
	var p := me(pi)
	p.hand.erase(ci)
	_log("%s casts %s." % [p.name, ci.def.name])
	event.emit("cast", { "player": pi, "uid": ci.uid, "card": ci.def.id, "target": target })
	if ci.def.is_creature():
		p.battlefield.append(ci)
		ci.sick = true
		event.emit("enter", { "player": pi, "uid": ci.uid })
		_run_effects(pi, ci, "etb", target)
	else:
		_run_effects(pi, ci, "cast", target)
		p.graveyard.append(ci.def.id)
	_check_state()
	return true


func _target_in(t: Dictionary, legal: Array) -> bool:
	for l in legal:
		if l.get("kind") == t.get("kind") and l.get("uid", -1) == t.get("uid", -1) and l.get("index", -1) == t.get("index", -1):
			return true
	return false


## Enter combat with the given attackers (uids). Empty array = skip combat.
func declare_attackers(uids: Array) -> bool:
	if phase != Phase.MAIN or combat_done:
		return false
	combat_done = true
	attackers.clear()
	for uid in uids:
		var c := find(uid)
		if c and c.owner == active and c.can_attack():
			attackers.append(uid)
	if attackers.is_empty():
		return true
	for uid in attackers:
		var c := find(uid)
		if not c.has_kw("vigilance"):
			c.tapped = true
		_log("%s attacks with %s." % [me(active).name, c.def.name])
		_run_effects(active, c, "attack", {})
	event.emit("attack", { "player": active, "attackers": attackers.duplicate() })
	_check_state()
	if phase == Phase.GAME_OVER:
		return true
	# Attack triggers can remove attackers (e.g. nothing yet, but be safe).
	attackers = attackers.filter(func(u): return find(u) != null)
	if attackers.is_empty():
		_end_combat()
		return true
	phase = Phase.BLOCKS
	blocks.clear()
	return true


func can_block(blocker_uid: int, attacker_uid: int) -> bool:
	var b := find(blocker_uid)
	var a := find(attacker_uid)
	if b == null or a == null or b.owner == active or not attackers.has(attacker_uid):
		return false
	return b.can_block_creature(a)


## Defender submits blocks: { attacker_uid: blocker_uid }.
func declare_blocks(assign: Dictionary) -> bool:
	if phase != Phase.BLOCKS:
		return false
	blocks.clear()
	var used := {}
	for a_uid in assign:
		var b_uid: int = assign[a_uid]
		if used.has(b_uid):
			continue
		if can_block(b_uid, a_uid):
			blocks[a_uid] = b_uid
			used[b_uid] = true
			_log("%s blocks %s." % [find(b_uid).def.name, find(a_uid).def.name])
	event.emit("blocks", { "blocks": blocks.duplicate() })
	phase = Phase.TRICKS
	trick_player = active
	return true


## The current trick-window player passes. After both pass, damage happens.
func pass_tricks() -> void:
	if phase != Phase.TRICKS:
		return
	if trick_player == active:
		trick_player = 1 - active
		event.emit("trick_window", { "player": trick_player })
	else:
		_resolve_combat_damage()


func _resolve_combat_damage() -> void:
	trick_player = -1
	# Attackers or blockers may have died to tricks.
	attackers = attackers.filter(func(u): return find(u) != null)
	var first_strikers_exist := false
	for a_uid in attackers:
		var a := find(a_uid)
		var b := find(blocks.get(a_uid, -1))
		if a.has_kw("first_strike") or (b and b.has_kw("first_strike")):
			first_strikers_exist = true
	if first_strikers_exist:
		_damage_step(true)
		_check_state()
	if phase != Phase.GAME_OVER:
		_damage_step(false)
		_check_state()
	if phase != Phase.GAME_OVER:
		_end_combat()


func _damage_step(first_strike_step: bool) -> void:
	var dealt: Array = []
	for a_uid in attackers:
		var a := find(a_uid)
		if a == null:
			continue
		var b_uid: int = blocks.get(a_uid, -1)
		var b := find(b_uid)
		var a_strikes: bool = a.has_kw("first_strike") == first_strike_step
		if b_uid != -1 and b == null:
			# Blocker vanished: attacker stays blocked (no damage) unless trample.
			if a_strikes and a.has_kw("trample"):
				_deal_damage_to_player(a, 1 - a.owner, a.power())
			continue
		if b == null:
			if a_strikes:
				_deal_damage_to_player(a, 1 - a.owner, a.power())
			continue
		if a_strikes and a.power() > 0:
			var to_blocker := a.power()
			if a.has_kw("trample"):
				var lethal: int = 1 if a.has_kw("deathtouch") else maxi(0, b.toughness() - b.damage)
				to_blocker = mini(a.power(), lethal)
				var excess := a.power() - to_blocker
				if excess > 0:
					_deal_damage_to_player(a, 1 - a.owner, excess)
			dealt.append([a, b, to_blocker])
		if b.has_kw("first_strike") == first_strike_step and b.power() > 0:
			dealt.append([b, a, b.power()])
	for d in dealt:
		_deal_damage_to_creature(d[0], d[1], d[2])
	if not dealt.is_empty():
		event.emit("combat_damage", {})


func _deal_damage_to_player(src: CardInstance, pi: int, amount: int) -> void:
	if amount <= 0:
		return
	players[pi].life -= amount
	_log("%s deals %d to %s." % [src.def.name, amount, players[pi].name])
	event.emit("player_damage", { "player": pi, "amount": amount, "source": src.uid })
	if src.has_kw("lifelink"):
		_gain_life(src.owner, amount)


func _deal_damage_to_creature(src: CardInstance, dst: CardInstance, amount: int) -> void:
	if amount <= 0 or find(dst.uid) == null:
		return
	dst.damage += amount
	if src.has_kw("deathtouch"):
		dst.damage = maxi(dst.damage, dst.toughness())
	event.emit("creature_damage", { "uid": dst.uid, "amount": amount })
	if src.has_kw("lifelink"):
		_gain_life(src.owner, amount)


func _gain_life(pi: int, amount: int) -> void:
	players[pi].life += amount
	event.emit("life_gain", { "player": pi, "amount": amount })


func _end_combat() -> void:
	attackers.clear()
	blocks.clear()
	trick_player = -1
	if phase != Phase.GAME_OVER:
		phase = Phase.MAIN
	event.emit("combat_end", {})


func end_turn() -> void:
	if phase == Phase.GAME_OVER:
		return
	if phase != Phase.MAIN:
		return
	var p := me(active)
	while p.hand.size() > MAX_HAND:
		var worst = p.hand[0]
		for c in p.hand:
			if c.def.mana_value() > worst.def.mana_value():
				worst = c
		p.hand.erase(worst)
		p.graveyard.append(worst.def.id)
		_log("%s discards %s (hand size)." % [p.name, worst.def.name])
	for pl in players:
		for c in pl.battlefield:
			c.clear_temp()
	event.emit("turn_end", { "player": active })
	active = 1 - active
	_begin_turn()


# ---------------------------------------------------------------- effects

func _run_effects(pi: int, src: CardInstance, trigger: String, target: Dictionary) -> void:
	for e in src.def.effects:
		if e.get("on", "cast") != trigger:
			continue
		_apply_effect(pi, src, e, target)
		if phase == Phase.GAME_OVER:
			return


func _apply_effect(pi: int, src: CardInstance, e: Dictionary, target: Dictionary) -> void:
	var amt := int(e.get("amount", 0))
	var tgt: String = e.get("target", "")
	var targets := _resolve_targets(pi, src, tgt, target)
	match e.get("op", ""):
		"damage":
			for t in targets:
				if t is CardInstance:
					_deal_damage_to_creature(src, t, amt)
				else:
					players[t].life -= amt
					event.emit("player_damage", { "player": t, "amount": amt, "source": src.uid })
					if src.has_kw("lifelink"):
						_gain_life(pi, amt)
		"heal":
			_gain_life(pi, amt)
		"lose_life":
			players[pi].life -= amt
			event.emit("player_damage", { "player": pi, "amount": amt, "source": src.uid })
		"drain":
			players[1 - pi].life -= amt
			event.emit("player_damage", { "player": 1 - pi, "amount": amt, "source": src.uid })
			_gain_life(pi, amt)
		"draw":
			for i in amt:
				_draw(players[pi], true)
		"discard":
			var oh: Array = players[1 - pi].hand
			for i in maxi(1, amt):
				if oh.is_empty():
					break
				var c = oh[rng.randi_range(0, oh.size() - 1)]
				oh.erase(c)
				players[1 - pi].graveyard.append(c.def.id)
				_log("%s discards %s." % [players[1 - pi].name, c.def.name])
		"pump":
			for t in targets:
				if t is CardInstance:
					t.temp_power += int(e.get("power", 0))
					t.temp_toughness += int(e.get("toughness", 0))
					event.emit("pump", { "uid": t.uid })
		"grant":
			for t in targets:
				if t is CardInstance:
					t.temp_keywords.append(e.get("keyword", ""))
		"buff_all":
			for c in players[pi].battlefield:
				if e.get("others", false) and c == src:
					continue
				if e.get("permanent", false):
					c.counters += int(e.get("power", 1))
				else:
					c.temp_power += int(e.get("power", 0))
					c.temp_toughness += int(e.get("toughness", 0))
				event.emit("pump", { "uid": c.uid })
		"bounce":
			for t in targets:
				if t is CardInstance:
					_remove_from_battlefield(t)
					if not t.def.is_token:
						var fresh := _make_instance(t.def, t.owner)
						players[t.owner].hand.append(fresh)
					_log("%s returns to hand." % t.def.name)
					event.emit("leave", { "uid": t.uid, "how": "bounce" })
		"tap":
			for t in targets:
				if t is CardInstance:
					t.tapped = true
					event.emit("tap", { "uid": t.uid })
		"destroy":
			var min_power := int(e.get("min_power", -999))
			for t in targets:
				if t is CardInstance and t.power() >= min_power:
					_destroy(t)
		"token":
			var tk: Dictionary = e.get("token", {})
			for i in int(e.get("count", 1)):
				var d := CardDef.new()
				d.id = "token_" + str(tk.get("name", "token")).to_lower()
				d.name = tk.get("name", "Token")
				d.type = "creature"
				d.subtype = tk.get("subtype", "")
				d.power = int(tk.get("power", 1))
				d.toughness = int(tk.get("toughness", 1))
				d.colors = tk.get("colors", []).duplicate()
				d.keywords = tk.get("keywords", []).duplicate()
				d.rarity = "common"
				d.is_token = true
				d.text = ""
				var ci := _make_instance(d, pi)
				players[pi].battlefield.append(ci)
				event.emit("enter", { "player": pi, "uid": ci.uid })
		"ramp":
			var col := _best_ramp_color(pi, src)
			var land := _make_instance("land_" + col, pi)
			land.tapped = true
			players[pi].lands.append(land)
			_log("%s gets a %s." % [players[pi].name, land.def.name])
			event.emit("land", { "player": pi, "uid": land.uid })
	_check_state()


func _best_ramp_color(pi: int, src: CardInstance) -> String:
	var need := {}
	for c in players[pi].hand:
		for col in c.def.cost_colors:
			need[col] = need.get(col, 0) + int(c.def.cost_colors[col])
	var best := ""
	var best_n := -1
	for col in need:
		if need[col] > best_n:
			best = col
			best_n = need[col]
	if best == "":
		best = src.def.colors[0] if not src.def.colors.is_empty() else "grove"
	return best


func _resolve_targets(pi: int, src: CardInstance, tgt: String, chosen: Dictionary) -> Array:
	match tgt:
		"", "self":
			return [pi]
		"enemy_player":
			return [1 - pi]
		"this":
			return [src] if find(src.uid) else []
		"all_enemy_creatures":
			return players[1 - pi].battlefield.duplicate()
		"all_creatures":
			return players[0].battlefield + players[1].battlefield
		"any", "creature", "enemy_creature", "own_creature":
			if chosen.is_empty():
				return []
			if chosen.get("kind") == "player":
				return [int(chosen["index"])]
			var c := find(int(chosen.get("uid", -1)))
			return [c] if c else []
	return []


func _destroy(c: CardInstance) -> void:
	if find(c.uid) == null:
		return
	_remove_from_battlefield(c)
	if not c.def.is_token:
		players[c.owner].graveyard.append(c.def.id)
	_log("%s is destroyed." % c.def.name)
	event.emit("leave", { "uid": c.uid, "how": "die" })
	_run_effects(c.owner, c, "dies", {})


func _remove_from_battlefield(c: CardInstance) -> void:
	players[c.owner].battlefield.erase(c)
	attackers.erase(c.uid)
	for a in blocks.keys():
		if a == c.uid:
			blocks.erase(a)


## State-based actions: lethal damage kills creatures, 0 life loses the game.
func _check_state() -> void:
	if phase == Phase.GAME_OVER:
		return
	var changed := true
	while changed:
		changed = false
		for p in players:
			for c in p.battlefield.duplicate():
				if c.toughness() <= 0 or c.damage >= c.toughness():
					_destroy(c)
					changed = true
	var dead := []
	for p in players:
		if p.life <= 0:
			dead.append(p.index)
	if dead.size() == 2:
		_lose(1 - active)  # simultaneous: active player wins ties, keeps games short
	elif dead.size() == 1:
		_lose(dead[0])


func _lose(pi: int) -> void:
	if phase == Phase.GAME_OVER:
		return
	winner = 1 - pi
	phase = Phase.GAME_OVER
	_log("%s wins!" % players[winner].name)
	event.emit("game_over", { "winner": winner })
