class_name BattleEngine
extends RefCounted
## Rules engine for Sparkfolk, the Maplebrook card game. Pure logic, no nodes:
## the battle scene and the AI drive it through the action methods below and
## listen to `event` to animate what happened. Full rules: docs/GAME_RULES.md.
##
## In short: each turn you gain +1 max Spark (up to 10) and refill. Creatures
## are played into one of 4 lanes. When you attack, each attacker strikes the
## creature directly across (both deal damage to each other) or, if the lane
## is open, the opponent's Heart. First to 0 Heart loses.

signal event(kind: String, data: Dictionary)

enum Phase { PLAY, GAME_OVER }

const LANES := 4
const START_LIFE := 20
const MAX_SPARKS := 10
const MAX_HAND := 10
const HAND_FIRST := 3
const HAND_SECOND := 4

var players: Array = []          # [PlayerState, PlayerState]
var active: int = 0
var turn: int = 0
var phase: Phase = Phase.PLAY
var attacked: bool = false       # one attack per turn
var winner: int = -1
var rng := RandomNumberGenerator.new()
var _next_uid: int = 1
var log_lines: Array = []


class PlayerState:
	var index: int
	var name: String
	var life: int = 20
	var max_sparks: int = 0
	var sparks: int = 0
	var library: Array = []      # card ids, top = back
	var hand: Array = []         # CardInstance
	var lanes: Array = []        # CardInstance or null, size LANES
	var graveyard: Array = []    # card ids
	var fatigue: int = 0

	func creatures() -> Array:
		return lanes.filter(func(c): return c != null)


class CardInstance:
	var uid: int
	var def: CardDef
	var owner: int
	var lane: int = -1
	var fresh: bool = true       # played this turn: can't attack unless Swift
	var damage: int = 0
	var bonus_power: int = 0     # permanent buffs
	var bonus_health: int = 0
	var temp_power: int = 0      # until end of turn
	var temp_health: int = 0
	var extra_keywords: Array = []
	var shield: bool = false
	var frozen: int = 0
	var moved: bool = false

	func power() -> int:
		return maxi(0, def.power + bonus_power + temp_power)

	func max_health() -> int:
		return def.health + bonus_health + temp_health

	func health() -> int:
		return max_health() - damage

	func has_kw(k: String) -> bool:
		if k == "shield":
			return shield
		return def.has_keyword(k) or extra_keywords.has(k)

	func clear_temp() -> void:
		temp_power = 0
		temp_health = 0


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
		p.lanes = []
		p.lanes.resize(LANES)
		_shuffle(p.library)
		players.append(p)
	winner = -1
	turn = 0
	phase = Phase.PLAY
	active = rng.randi_range(0, 1)
	_opening_hand(players[active], HAND_FIRST)
	var second: PlayerState = players[1 - active]
	_opening_hand(second, HAND_SECOND)
	second.hand.append(_make_instance("lucky_penny", second.index))


## Cozy mulligan: a hand with nothing costing 2 or less is redrawn once, free.
func _opening_hand(p: PlayerState, n: int) -> void:
	for attempt in 2:
		for i in n:
			_draw(p, false)
		var cheap := p.hand.filter(func(c): return c.def.cost <= 2).size()
		if attempt == 0 and cheap == 0:
			for c in p.hand:
				p.library.append(c.def.id)
			p.hand.clear()
			_shuffle(p.library)
			_log("%s takes a free mulligan." % p.name)
			continue
		break


func start() -> void:
	_begin_turn()


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
	ci.shield = ci.def.has_keyword("shield")
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
		for c in p.lanes:
			if c != null and c.uid == uid:
				return c
	return null


func is_over() -> bool:
	return phase == Phase.GAME_OVER


func is_my_turn(pi: int) -> bool:
	return active == pi and phase == Phase.PLAY


func empty_lanes(pi: int) -> Array:
	var out: Array = []
	for i in LANES:
		if players[pi].lanes[i] == null:
			out.append(i)
	return out


## The creature an attacker in `lane` would actually fight, or null if it gets through.
func blocker_for(a: CardInstance) -> CardInstance:
	var b: CardInstance = players[1 - a.owner].lanes[a.lane]
	if b == null:
		return null
	if a.has_kw("soar") and not (b.has_kw("soar") or b.has_kw("reach")):
		return null
	return b


func can_attack(c: CardInstance) -> bool:
	return c != null and c.owner == active and phase == Phase.PLAY and not attacked \
		and (not c.fresh or c.has_kw("swift")) and c.frozen == 0 and c.power() > 0


func can_play(pi: int, ci: CardInstance) -> bool:
	if not is_my_turn(pi) or ci.def.cost > players[pi].sparks:
		return false
	var te := ci.def.targeted_effect()
	if ci.def.is_spell() and not te.is_empty() and legal_targets(pi, te).is_empty():
		return false
	return true


## Targets are { "kind": "player", "index": i } or { "kind": "creature", "uid": n }.
func legal_targets(pi: int, effect: Dictionary) -> Array:
	var out: Array = []
	var t: String = effect.get("target", "")
	var max_power := int(effect.get("max_power", 999))
	if t == "any":
		out.append({ "kind": "player", "index": 1 - pi })
		out.append({ "kind": "player", "index": pi })
	for p in players:
		for c in p.creatures():
			var ok := false
			match t:
				"any", "creature": ok = true
				"enemy_creature": ok = c.owner != pi
				"own_creature": ok = c.owner == pi
			if ok and c.power() <= max_power:
				out.append({ "kind": "creature", "uid": c.uid })
	return out


func move_options(pi: int, uid: int) -> Array:
	var c := find(uid)
	if c == null or c.owner != pi or not is_my_turn(pi) or not c.has_kw("move") or c.moved:
		return []
	var out: Array = []
	for l in [c.lane - 1, c.lane + 1]:
		if l >= 0 and l < LANES and players[pi].lanes[l] == null:
			out.append(l)
	return out


# ---------------------------------------------------------------- turn flow

func _begin_turn() -> void:
	turn += 1
	attacked = false
	phase = Phase.PLAY
	var p := me(active)
	p.max_sparks = mini(MAX_SPARKS, p.max_sparks + 1)
	p.sparks = p.max_sparks
	for c in p.creatures():
		c.fresh = false
		c.moved = false
	event.emit("turn_start", { "player": active, "turn": turn })
	_log("-- Turn %d: %s --" % [turn, p.name])
	_draw(p, true)


func _draw(p: PlayerState, announce: bool) -> void:
	if p.library.is_empty():
		if announce:
			p.fatigue += 1
			p.life -= p.fatigue
			_log("%s is out of cards and loses %d Heart." % [p.name, p.fatigue])
			event.emit("player_damage", { "player": p.index, "amount": p.fatigue, "source": -1 })
			_check_state()
		return
	var ci := _make_instance(p.library.pop_back(), p.index)
	if p.hand.size() >= MAX_HAND:
		p.graveyard.append(ci.def.id)
		_log("%s's hand is full; %s is discarded." % [p.name, ci.def.name])
		return
	p.hand.append(ci)
	if announce:
		event.emit("draw", { "player": p.index, "uid": ci.uid })


## Play a card from hand. Creatures need a `lane` (or -1 for the leftmost empty
## lane). Playing into a lane you already hold retires the creature there.
## Cards with a chosen target need `target`.
func play(pi: int, ci: CardInstance, lane: int = -1, target: Dictionary = {}) -> bool:
	if not can_play(pi, ci) or not me(pi).hand.has(ci):
		return false
	var p := me(pi)
	if ci.def.is_creature():
		var free := empty_lanes(pi)
		if lane < 0:
			lane = free[0] if not free.is_empty() else 0
		if lane < 0 or lane >= LANES:
			return false
	var te := ci.def.targeted_effect()
	if not te.is_empty():
		var legal := legal_targets(pi, te)
		if legal.is_empty():
			target = {}
		elif not _target_in(target, legal):
			return false
	p.sparks -= ci.def.cost
	p.hand.erase(ci)
	_log("%s plays %s." % [p.name, ci.def.name])
	event.emit("play", { "player": pi, "uid": ci.uid, "card": ci.def.id, "target": target })
	if ci.def.is_creature():
		var old: CardInstance = p.lanes[lane]
		if old:
			_retire(old)
		_place(ci, lane)
		_run_effects(pi, ci, "enter", target)
	else:
		_run_effects(pi, ci, "cast", target)
		if not ci.def.is_token:
			p.graveyard.append(ci.def.id)
	_check_state()
	return true


func _place(ci: CardInstance, lane: int) -> void:
	ci.lane = lane
	ci.fresh = true
	players[ci.owner].lanes[lane] = ci
	event.emit("enter", { "player": ci.owner, "uid": ci.uid, "lane": lane })


func _target_in(t: Dictionary, legal: Array) -> bool:
	for l in legal:
		if l.get("kind") == t.get("kind") and l.get("uid", -1) == t.get("uid", -1) and l.get("index", -1) == t.get("index", -1):
			return true
	return false


func move(pi: int, uid: int, lane: int) -> bool:
	if not move_options(pi, uid).has(lane):
		return false
	var c := find(uid)
	_relocate(c, lane)
	c.moved = true
	_log("%s moves to lane %d." % [c.def.name, lane + 1])
	return true


func _relocate(c: CardInstance, lane: int) -> void:
	var from := c.lane
	players[c.owner].lanes[from] = null
	players[c.owner].lanes[lane] = c
	c.lane = lane
	event.emit("move", { "uid": c.uid, "from": from, "to": lane })


## Attack with the given creatures. Lanes resolve left to right.
func attack(uids: Array) -> bool:
	if phase != Phase.PLAY or attacked:
		return false
	attacked = true
	var list: Array = uids.map(func(u): return find(u)).filter(func(c): return c != null and can_attack_now(c))
	list.sort_custom(func(a, b): return a.lane < b.lane)
	for a in list:
		if find(a.uid) == null or phase == Phase.GAME_OVER:
			continue
		_run_effects(a.owner, a, "attack", {})
		if find(a.uid) == null or phase == Phase.GAME_OVER:
			continue
		var b: CardInstance = blocker_for(a)
		event.emit("clash", { "attacker": a.uid, "blocker": b.uid if b else -1, "lane": a.lane, "player": a.owner })
		if b:
			_log("%s fights %s." % [a.def.name, b.def.name])
			var ap: int = a.power()
			var bp: int = b.power()
			_damage_creature(a, b, ap)
			_damage_creature(b, a, bp)
		else:
			_damage_player(a, 1 - a.owner, a.power())
		if a.has_kw("sweep"):
			for l in [a.lane - 1, a.lane + 1]:
				if l >= 0 and l < LANES:
					var side: CardInstance = players[1 - a.owner].lanes[l]
					if side:
						_damage_creature(a, side, a.power())
		_check_state()
	event.emit("attack_done", {})
	return true


## Like can_attack, but ignores the `attacked` flag (used while resolving).
func can_attack_now(c: CardInstance) -> bool:
	return c.owner == active and (not c.fresh or c.has_kw("swift")) and c.frozen == 0 and c.power() > 0


func end_turn() -> void:
	if phase != Phase.PLAY:
		return
	for pl in players:
		for c in pl.creatures():
			c.clear_temp()
			if c.owner == active and c.frozen > 0:
				c.frozen -= 1
	_check_state()
	if phase == Phase.GAME_OVER:
		return
	event.emit("turn_end", { "player": active })
	active = 1 - active
	_begin_turn()


# ---------------------------------------------------------------- damage

func _damage_player(src: CardInstance, pi: int, amount: int) -> void:
	if amount <= 0:
		return
	players[pi].life -= amount
	_log("%s deals %d to %s." % [src.def.name, amount, players[pi].name])
	event.emit("player_damage", { "player": pi, "amount": amount, "source": src.uid })


func _damage_creature(_src: CardInstance, dst: CardInstance, amount: int) -> void:
	if amount <= 0 or find(dst.uid) == null:
		return
	if dst.shield:
		dst.shield = false
		event.emit("shield_pop", { "uid": dst.uid })
		return
	dst.damage += amount
	event.emit("creature_damage", { "uid": dst.uid, "amount": amount })


func _gain_life(pi: int, amount: int) -> void:
	players[pi].life += amount
	event.emit("life_gain", { "player": pi, "amount": amount })


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
	var targets := _resolve_targets(pi, src, e.get("target", ""), target)
	var permanent: bool = e.get("permanent", true)
	match e.get("op", ""):
		"damage":
			for t in targets:
				if t is CardInstance:
					_damage_creature(src, t, amt)
				else:
					_damage_player(src, t, amt)
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
		"spark":
			players[pi].sparks += amt
		"buff":
			for t in targets:
				if t is CardInstance:
					_buff(t, int(e.get("power", 0)), int(e.get("health", 0)), permanent)
		"buff_all":
			for c in players[pi].creatures():
				if e.get("others", false) and c == src:
					continue
				_buff(c, int(e.get("power", 0)), int(e.get("health", 0)), permanent)
		"grant":
			for t in targets:
				if t is CardInstance:
					_grant(t, e.get("keyword", ""))
		"grant_all":
			for c in players[pi].creatures():
				if e.get("others", false) and c == src:
					continue
				_grant(c, e.get("keyword", ""))
		"token":
			var tk: Dictionary = e.get("token", {})
			var col: String = src.def.color
			for i in int(e.get("count", 1)):
				var free := empty_lanes(pi)
				if free.is_empty():
					break
				var ci := _make_instance(CardDef.make_token(tk, col), pi)
				_place(ci, _nearest_lane(free, src.lane))
		"destroy":
			var max_power := int(e.get("max_power", 999))
			for t in targets:
				if t is CardInstance and t.power() <= max_power:
					_destroy(t)
		"destroy_all":
			var mp := int(e.get("max_power", 0))
			for p in players:
				for c in p.creatures():
					if c.power() <= mp:
						_destroy(c)
		"bounce":
			for t in targets:
				if t is CardInstance:
					_remove(t)
					if not t.def.is_token:
						players[t.owner].hand.append(_make_instance(t.def, t.owner))
					_log("%s returns to %s's hand." % [t.def.name, players[t.owner].name])
					event.emit("leave", { "uid": t.uid, "how": "bounce" })
		"freeze":
			for t in targets:
				if t is CardInstance:
					t.frozen = 1
					event.emit("freeze", { "uid": t.uid })
		"push":
			for t in targets:
				if t is CardInstance:
					for l in [t.lane - 1, t.lane + 1]:
						if l >= 0 and l < LANES and players[t.owner].lanes[l] == null:
							_relocate(t, l)
							break
	_check_state()


func _buff(c: CardInstance, p: int, h: int, permanent: bool) -> void:
	if permanent:
		c.bonus_power += p
		c.bonus_health += h
	else:
		c.temp_power += p
		c.temp_health += h
	event.emit("buff", { "uid": c.uid })


func _grant(c: CardInstance, kw: String) -> void:
	if kw == "shield":
		c.shield = true
	elif not c.extra_keywords.has(kw):
		c.extra_keywords.append(kw)
	event.emit("buff", { "uid": c.uid })


func _nearest_lane(free: Array, near: int) -> int:
	if near < 0:
		return free[0]
	var best: int = free[0]
	for l in free:
		if absi(l - near) < absi(best - near):
			best = l
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
			return players[1 - pi].creatures()
		"all_creatures":
			return players[0].creatures() + players[1].creatures()
		"random_enemy_creature":
			var list: Array = players[1 - pi].creatures()
			return [] if list.is_empty() else [list[rng.randi_range(0, list.size() - 1)]]
		"any", "creature", "enemy_creature", "own_creature":
			if chosen.is_empty():
				return []
			if chosen.get("kind") == "player":
				return [int(chosen["index"])]
			var c := find(int(chosen.get("uid", -1)))
			return [c] if c else []
	return []


func _remove(c: CardInstance) -> void:
	if c.lane >= 0 and players[c.owner].lanes[c.lane] == c:
		players[c.owner].lanes[c.lane] = null


## Replaced by a new creature: leaves without dying (no Last Breath).
func _retire(c: CardInstance) -> void:
	_remove(c)
	if not c.def.is_token:
		players[c.owner].graveyard.append(c.def.id)
	_log("%s heads home to make room." % c.def.name)
	event.emit("leave", { "uid": c.uid, "how": "retire" })


func _destroy(c: CardInstance) -> void:
	if find(c.uid) == null:
		return
	_remove(c)
	if not c.def.is_token:
		players[c.owner].graveyard.append(c.def.id)
	_log("%s is defeated." % c.def.name)
	event.emit("leave", { "uid": c.uid, "how": "die" })
	_run_effects(c.owner, c, "dies", {})


## State-based checks: creatures at 0 health leave, players at 0 Heart lose.
func _check_state() -> void:
	if phase == Phase.GAME_OVER:
		return
	var changed := true
	while changed:
		changed = false
		for p in players:
			for c in p.creatures():
				if c.health() <= 0:
					_destroy(c)
					changed = true
	var dead := []
	for p in players:
		if p.life <= 0:
			dead.append(p.index)
	if dead.size() == 2:
		_lose(1 - active)
	elif dead.size() == 1:
		_lose(dead[0])


func _lose(pi: int) -> void:
	if phase == Phase.GAME_OVER:
		return
	winner = 1 - pi
	phase = Phase.GAME_OVER
	_log("%s wins!" % players[winner].name)
	event.emit("game_over", { "winner": winner })
