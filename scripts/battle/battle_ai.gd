class_name BattleAI
extends RefCounted
## Heuristic Sparkfolk opponent. Each NPC tunes `aggression` (0 = cautious, 1 = reckless).
## The AI never cheats: it reads the public board plus its own hand.
##
## Turn plan (driven by the battle scene): repeat next_action() until it returns
## {}, then attack with choose_attackers(), then next_action() again, then end turn.

var aggression: float = 0.5
var rng := RandomNumberGenerator.new()


func _init(p_aggression: float = 0.5) -> void:
	aggression = p_aggression
	rng.randomize()


# ---------------------------------------------------------------- valuation

static func creature_value(c) -> float:
	var v: float = c.power() * 1.2 + c.health()
	for k in ["soar", "shield", "sweep", "swift", "reach", "move"]:
		if c.has_kw(k):
			v += 1.0
	if c.def.is_token:
		v -= 0.5
	return v


## Would `a` kill `b` if it hit it once?
static func kills(a, b) -> bool:
	return a.power() > 0 and not b.has_kw("shield") and a.power() >= b.health()


# ---------------------------------------------------------------- actions

## Returns { kind: "play", card, lane, target } / { kind: "move", uid, lane } / {}.
func next_action(e: BattleEngine, pi: int) -> Dictionary:
	if not e.is_my_turn(pi):
		return {}
	var p: BattleEngine.PlayerState = e.me(pi)
	# Lucky Penny: only when it lets us play something bigger right now.
	for c in p.hand:
		if c.def.id == "lucky_penny":
			var wants := p.hand.any(func(x): return x.def.cost == p.sparks + 1 and _plan(e, pi, x, p.sparks + 1).get("ok", false))
			if wants:
				return { "kind": "play", "card": c, "lane": -1, "target": {} }
	var best := {}
	var best_score := -INF
	for c in p.hand:
		if c.def.id == "lucky_penny" or not e.can_play(pi, c):
			continue
		var plan := _plan(e, pi, c, p.sparks)
		if not plan.get("ok", false):
			continue
		# Spend sparks efficiently: bigger cards first, then better plans.
		var score: float = c.def.cost * 10.0 + plan.get("score", 0.0)
		if score > best_score:
			best_score = score
			best = { "kind": "play", "card": c, "lane": plan.get("lane", -1), "target": plan.get("target", {}) }
	if not best.is_empty():
		return best
	return _plan_move(e, pi)


func _plan(e: BattleEngine, pi: int, c, sparks: int) -> Dictionary:
	if c.def.cost > sparks:
		return {}
	var out := { "ok": true, "score": 0.0, "lane": -1, "target": {} }
	if c.def.is_creature():
		var best_l := -1
		var best_s := -INF
		for l in BattleEngine.LANES:
			var s := _lane_score(e, pi, c.def, l)
			var old: BattleEngine.CardInstance = e.me(pi).lanes[l]
			if old:
				# Replacing costs us the creature already there; only worth it for an upgrade.
				var upgrade: float = (c.def.power * 1.2 + c.def.health) - creature_value(old)
				if upgrade < 3.0:
					continue
				s -= creature_value(old) + 1.0
			if s > best_s:
				best_s = s
				best_l = l
		if best_l < 0:
			return {}
		out["lane"] = best_l
		out["score"] = best_s
	var te: Dictionary = c.def.targeted_effect()
	if not te.is_empty():
		var legal := e.legal_targets(pi, te)
		var best_t := {}
		var best_ts := 0.0
		for t in legal:
			var s := _target_score(e, pi, c.def, te, t)
			if s > best_ts:
				best_ts = s
				best_t = t
		if best_t.is_empty():
			if c.def.is_spell():
				return {}
			best_t = _harmless_target(e, pi, legal)
		out["target"] = best_t
		out["score"] += best_ts
	elif c.def.is_spell():
		var s2 := _untargeted_score(e, pi, c.def)
		if s2 <= 0.0:
			return {}
		out["score"] = s2
	return out


## How good is it to put this creature in this lane?
func _lane_score(e: BattleEngine, pi: int, d: CardDef, lane: int) -> float:
	var enemy: BattleEngine.CardInstance = e.opp(pi).lanes[lane]
	var p := d.power
	var h := d.health
	var soar := d.has_keyword("soar")
	var shield := d.has_keyword("shield")
	if enemy == null:
		# Open lane: free damage next turn, but nothing to guard.
		return p * (0.6 + aggression)
	var s := 0.0
	var we_kill := p >= enemy.health() and not enemy.has_kw("shield")
	var they_kill := enemy.power() >= h and not shield
	var flies_over := soar and not (enemy.has_kw("soar") or enemy.has_kw("reach"))
	var they_fly_over := enemy.has_kw("soar") and not (soar or d.has_keyword("reach"))
	if flies_over:
		s += p * (0.6 + aggression)
	elif we_kill and not they_kill:
		s += creature_value(enemy) + 2.0
	elif we_kill and they_kill:
		s += creature_value(enemy) - (p * 1.2 + h) * 0.7
	elif they_kill:
		s -= (p * 1.2 + h) * 0.8
	if not they_fly_over:
		# Guarding this lane stops its attacker from hitting our face.
		s += enemy.power() * (1.5 - aggression)
	if d.has_keyword("sweep"):
		for l in [lane - 1, lane + 1]:
			if l >= 0 and l < BattleEngine.LANES and e.opp(pi).lanes[l]:
				s += 1.5
	return s


func _target_score(e: BattleEngine, pi: int, d: CardDef, eff: Dictionary, t: Dictionary) -> float:
	var op: String = eff.get("op", "")
	var amt := int(eff.get("amount", 0))
	if t["kind"] == "player":
		if t["index"] == pi:
			return -1.0
		if op == "damage":
			return 100.0 if amt >= e.opp(pi).life else 0.4 + aggression
		return -1.0
	var c = e.find(t["uid"])
	var mine: bool = c.owner == pi
	match op:
		"damage":
			if mine:
				return -1.0
			if c.has_kw("shield"):
				return 0.8
			return creature_value(c) + 2.0 if amt >= c.health() else amt * 0.3
		"buff", "grant":
			if not mine:
				return -1.0
			var s := 1.0 + creature_value(c) * 0.2
			var b := e.blocker_for(c) if c.lane >= 0 else null
			if eff.get("keyword", "") == "shield" and c.has_kw("shield"):
				return 0.1
			if b and not kills(c, b) and c.power() + int(eff.get("power", 0)) >= b.health():
				s += 3.0
			return s
		"destroy":
			return -1.0 if mine else creature_value(c) + 1.0
		"bounce":
			return -1.0 if mine else c.def.cost + (3.0 if c.def.is_token else 0.0) + c.bonus_power + c.bonus_health
		"freeze":
			return -1.0 if mine else c.power() * 0.8 + 0.5
		"push":
			if mine:
				return -1.0
			var room := false
			for l in [c.lane - 1, c.lane + 1]:
				if l >= 0 and l < BattleEngine.LANES and e.opp(pi).lanes[l] == null:
					room = true
			if not room:
				return 0.0
			var ours: BattleEngine.CardInstance = e.me(pi).lanes[c.lane]
			return 1.0 + (ours.power() if ours else 0.0)
	return 0.0


func _harmless_target(e: BattleEngine, pi: int, legal: Array) -> Dictionary:
	for t in legal:
		if t["kind"] == "player" and t["index"] != pi:
			return t
	for t in legal:
		if t["kind"] == "creature" and e.find(t["uid"]).owner != pi:
			return t
	return legal[0] if not legal.is_empty() else {}


func _untargeted_score(e: BattleEngine, pi: int, d: CardDef) -> float:
	var s := 0.0
	var mine: Array = e.me(pi).creatures()
	var theirs: Array = e.opp(pi).creatures()
	for eff in d.effects:
		match eff.get("op", ""):
			"draw":
				s += 2.0 if e.me(pi).hand.size() < 7 else 0.2
			"heal":
				s += 1.0 if e.me(pi).life < 15 else 0.3
			"lose_life":
				if e.me(pi).life <= int(eff.get("amount", 0)) + 3:
					return -1.0
			"drain":
				s += 1.5
			"buff_all", "grant_all":
				s += mine.size() * 1.2 - 1.0
				if not eff.get("permanent", true) and e.attacked:
					return -1.0
			"token":
				s += 1.0 if not e.empty_lanes(pi).is_empty() else -5.0
			"damage":
				var killed := 0.0
				for c in theirs:
					if not c.has_kw("shield") and c.health() <= int(eff.get("amount", 0)):
						killed += creature_value(c)
				s += killed - 2.0
			"destroy_all":
				var mp := int(eff.get("max_power", 0))
				var gain := 0.0
				for c in theirs:
					if c.power() <= mp:
						gain += creature_value(c)
				for c in mine:
					if c.power() <= mp:
						gain -= creature_value(c)
				s += gain - 4.0
			"freeze":
				s += theirs.size() * 0.8
	return s


func _plan_move(e: BattleEngine, pi: int) -> Dictionary:
	for c in e.me(pi).creatures():
		var opts := e.move_options(pi, c.uid)
		if opts.is_empty():
			continue
		var here := _lane_score(e, pi, c.def, c.lane)
		for l in opts:
			var there := _lane_score(e, pi, c.def, l)
			if there > here + 2.0:
				return { "kind": "move", "uid": c.uid, "lane": l }
	return {}


# ---------------------------------------------------------------- combat

func choose_attackers(e: BattleEngine, pi: int) -> Array:
	var ready: Array = e.me(pi).creatures().filter(func(c): return e.can_attack(c))
	if ready.is_empty():
		return []
	var face := 0
	for c in ready:
		if e.blocker_for(c) == null:
			face += c.power()
	if face >= e.opp(pi).life:
		return ready.map(func(c): return c.uid)
	var out: Array = []
	for a in ready:
		var b = e.blocker_for(a)
		if b == null:
			out.append(a.uid)
			continue
		var a_kills := kills(a, b)
		var b_kills := kills(b, a)
		var go := false
		if not b_kills:
			go = true                      # free hit (or pops a shield)
		elif a_kills:
			go = creature_value(b) >= creature_value(a) - aggression * 3.0
		elif aggression > 0.8 and rng.randf() < 0.15:
			go = true                      # reckless chip damage
		if a.has_kw("sweep") and not b_kills:
			go = true
		if go:
			out.append(a.uid)
	return out
