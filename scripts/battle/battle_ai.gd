class_name BattleAI
extends RefCounted
## Heuristic opponent. Each NPC tunes `aggression` (0 = cautious, 1 = reckless).
## The AI never cheats: it only reads public board state plus its own hand.

var aggression: float = 0.5
var rng := RandomNumberGenerator.new()


func _init(p_aggression: float = 0.5) -> void:
	aggression = p_aggression
	rng.randomize()


# ---------------------------------------------------------------- valuation

static func creature_value(c) -> float:
	var v: float = c.power() * 1.5 + c.toughness()
	for k in ["flying", "deathtouch", "lifelink", "first_strike", "trample"]:
		if c.has_kw(k):
			v += 1.5
	if c.has_kw("vigilance"):
		v += 0.5
	if c.def.is_token:
		v -= 1.0
	return v


static func _kills(src, dst, src_p: int, dst_t: int, dst_dmg: int = 0) -> bool:
	if src_p <= 0:
		return false
	return src.has_kw("deathtouch") or src_p + dst_dmg >= dst_t


# ---------------------------------------------------------------- main phase

## Returns the next thing to do in a main phase: { "card": CardInstance, "target": {} },
## or an empty Dictionary when the AI is done.
func next_main_action(e: BattleEngine, pi: int) -> Dictionary:
	if not e.is_main_phase_for(pi):
		return {}
	var p: BattleEngine.PlayerState = e.me(pi)
	# 1) Land drop.
	if not p.land_played:
		var land = _choose_land(e, pi)
		if land:
			return { "card": land, "target": {} }
	# 2) Spells, most expensive first.
	var options: Array = p.hand.filter(func(c): return not c.def.is_land() and e.can_cast(pi, c))
	options.sort_custom(func(a, b): return a.def.mana_value() > b.def.mana_value())
	for c in options:
		if c.def.is_instant() and not _instant_ok_in_main(e, pi, c):
			continue
		var plan := _plan_cast(e, pi, c)
		if plan.get("skip", false):
			continue
		return { "card": c, "target": plan.get("target", {}) }
	return {}


func _choose_land(e: BattleEngine, pi: int):
	var p: BattleEngine.PlayerState = e.me(pi)
	var lands: Array = p.hand.filter(func(c): return c.def.is_land())
	if lands.is_empty():
		return null
	var have := {}
	for l in p.lands:
		have[l.def.produces] = have.get(l.def.produces, 0) + 1
	var need := {}
	for c in p.hand:
		for col in c.def.cost_colors:
			need[col] = need.get(col, 0) + int(c.def.cost_colors[col])
	var best = lands[0]
	var best_score := -999.0
	for l in lands:
		var col: String = l.def.produces
		var score: float = need.get(col, 0) * 2.0 - have.get(col, 0)
		if score > best_score:
			best_score = score
			best = l
	return best


## Instants we'd happily cast at sorcery speed (card draw, or clean removal).
func _instant_ok_in_main(e: BattleEngine, pi: int, c) -> bool:
	for eff in c.def.effects:
		var op: String = eff.get("op", "")
		if op == "draw" and c.def.targeted_effect().is_empty():
			# Only when nothing else wants the mana.
			var others: Array = e.me(pi).hand.filter(func(x): return x != c and not x.def.is_land() and not x.def.is_instant() and e.can_cast(pi, x))
			return others.is_empty()
		if op in ["destroy", "damage"]:
			var plan := _plan_cast(e, pi, c)
			return not plan.get("skip", false) and plan.get("target", {}).get("kind", "") == "creature"
	return false


## Decide the target for a card cast in a main phase, or { "skip": true }.
func _plan_cast(e: BattleEngine, pi: int, c) -> Dictionary:
	var te: Dictionary = c.def.targeted_effect()
	if te.is_empty():
		return _plan_untargeted(e, pi, c)
	var legal := e.legal_targets(pi, te)
	if legal.is_empty():
		return {} if c.def.is_creature() else { "skip": true }
	var op: String = te.get("op", "")
	var best := {}
	var best_score := 0.0
	for t in legal:
		var s := _score_main_target(e, pi, op, te, t)
		if s > best_score:
			best_score = s
			best = t
	if best.is_empty():
		if c.def.is_creature():
			# The creature is worth casting anyway: point the trigger somewhere harmless.
			return { "target": _least_bad_target(e, pi, legal, op) }
		return { "skip": true }
	return { "target": best }


func _plan_untargeted(e: BattleEngine, pi: int, c) -> Dictionary:
	for eff in c.def.effects:
		var op: String = eff.get("op", "")
		if eff.get("on", "") != "cast":
			continue
		match op:
			"damage":
				if eff.get("target", "") == "all_enemy_creatures":
					var n := 0
					for x in e.opp(pi).battlefield:
						if x.toughness() - x.damage <= int(eff.get("amount", 0)):
							n += 1
					if n < 2 and e.opp(pi).battlefield.size() < 3:
						return { "skip": true }
			"buff_all":
				if not eff.get("permanent", false):
					return { "skip": true }  # temporary buffs are combat tricks
				if e.me(pi).battlefield.size() < 2:
					return { "skip": true }
			"lose_life":
				if e.me(pi).life <= int(eff.get("amount", 0)) + 2:
					return { "skip": true }
	return {}


func _score_main_target(e: BattleEngine, pi: int, op: String, eff: Dictionary, t: Dictionary) -> float:
	var amt := int(eff.get("amount", 0))
	if t["kind"] == "player":
		if t["index"] == pi:
			return -1.0
		if op == "damage":
			var opp_life: int = e.opp(pi).life
			if amt >= opp_life:
				return 100.0
			return 0.5 + aggression  # burn to face is fine for aggressive NPCs
		return -1.0
	var c = e.find(t["uid"])
	var mine: bool = c.owner == pi
	match op:
		"damage":
			if mine:
				return -1.0
			return creature_value(c) + 2.0 if amt >= c.toughness() - c.damage else 0.0
		"pump":
			var tough_delta := int(eff.get("toughness", 0))
			if tough_delta < 0:
				if mine:
					return -1.0
				return creature_value(c) + 2.0 if c.toughness() + tough_delta - c.damage <= 0 else 0.0
			return -1.0  # positive pumps are saved for combat
		"destroy", "bounce":
			if mine:
				return -1.0
			var v := creature_value(c)
			if op == "bounce" and c.def.is_token:
				v += 3.0
			return v
		"tap":
			if mine:
				return -1.0
			return c.power() * 1.0 if not c.tapped else 0.0
	return 0.0


func _least_bad_target(e: BattleEngine, pi: int, legal: Array, op: String) -> Dictionary:
	for t in legal:
		if t["kind"] == "player" and t["index"] != pi:
			return t
	for t in legal:
		if t["kind"] == "creature" and e.find(t["uid"]).owner != pi:
			return t
	return legal[0]


# ---------------------------------------------------------------- combat

func choose_attackers(e: BattleEngine, pi: int) -> Array:
	var mine: Array = e.me(pi).battlefield.filter(func(c): return c.can_attack())
	if mine.is_empty():
		return []
	var theirs: Array = e.opp(pi).battlefield.filter(func(c): return not c.tapped)
	var opp_life: int = e.opp(pi).life
	# Lethal check: assume each untapped enemy creature blocks one of our biggest.
	var powers: Array = mine.map(func(c): return c.power())
	powers.sort()
	powers.reverse()
	var through := 0
	for i in powers.size():
		if i >= theirs.size():
			through += powers[i]
	var evasive := 0
	for c in mine:
		if c.has_kw("flying") and theirs.filter(func(b): return b.has_kw("flying") or b.has_kw("reach")).is_empty():
			evasive += c.power()
	if through >= opp_life or evasive >= opp_life:
		return mine.map(func(c): return c.uid)

	# Danger check: how hard can they swing back next turn?
	var their_power := 0
	for c in e.opp(pi).battlefield:
		their_power += c.power()
	var my_life: int = e.me(pi).life
	var keep_home := their_power >= my_life and aggression < 0.8

	var out: Array = []
	var held_back := 0
	for a in mine:
		var blockers: Array = theirs.filter(func(b): return b.can_block_creature(a))
		var bad := false
		var trade := false
		for b in blockers:
			var b_kills := _kills(b, a, b.power(), a.toughness(), a.damage)
			var a_kills := _kills(a, b, a.power(), b.toughness(), b.damage)
			if b_kills and not a_kills:
				bad = true
			elif b_kills and a_kills:
				if creature_value(a) > creature_value(b) + 1.0:
					trade = true
		var go := not bad and (not trade or rng.randf() < aggression)
		if bad and aggression > 0.9 and rng.randf() < 0.3:
			go = true
		if keep_home and not a.has_kw("vigilance") and held_back < 2 and a.toughness() >= 2:
			go = false
			held_back += 1
		if go:
			out.append(a.uid)
	return out


func choose_blocks(e: BattleEngine, pi: int) -> Dictionary:
	var attackers: Array = e.attackers.map(func(u): return e.find(u)).filter(func(c): return c != null)
	attackers.sort_custom(func(a, b): return a.power() > b.power())
	var available: Array = e.me(pi).battlefield.filter(func(c): return not c.tapped)
	var assign := {}
	var used := {}
	var incoming := 0
	for a in attackers:
		incoming += a.power()

	# Pass 1: blocks that win (kill it and survive) or are free (just survive).
	for a in attackers:
		var best = null
		var best_v := 999.0
		for b in available:
			if used.has(b.uid) or not b.can_block_creature(a):
				continue
			var survives := not _kills(a, b, a.power(), b.toughness(), b.damage)
			if survives and creature_value(b) < best_v:
				best = b
				best_v = creature_value(b)
		if best:
			assign[a.uid] = best.uid
			used[best.uid] = true
			incoming -= a.power()
	# Pass 2: trades that favour us.
	for a in attackers:
		if assign.has(a.uid):
			continue
		for b in available:
			if used.has(b.uid) or not b.can_block_creature(a):
				continue
			if _kills(b, a, b.power(), a.toughness(), a.damage) and creature_value(a) >= creature_value(b) - (1.0 - aggression):
				assign[a.uid] = b.uid
				used[b.uid] = true
				incoming -= a.power()
				break
	# Pass 3: chump block if we'd otherwise die (or nearly).
	var life: int = e.me(pi).life
	for a in attackers:
		if incoming < life - (1 if aggression > 0.6 else 3):
			break
		if assign.has(a.uid):
			continue
		var cheapest = null
		for b in available:
			if used.has(b.uid) or not b.can_block_creature(a):
				continue
			if cheapest == null or creature_value(b) < creature_value(cheapest):
				cheapest = b
		if cheapest:
			assign[a.uid] = cheapest.uid
			used[cheapest.uid] = true
			incoming -= a.power()
	return assign


# ---------------------------------------------------------------- tricks

## During the combat trick window: returns { "card", "target" } or {}.
func next_trick(e: BattleEngine, pi: int) -> Dictionary:
	if e.phase != BattleEngine.Phase.TRICKS or e.trick_player != pi:
		return {}
	var base := _combat_score(e, pi, {}, 0)
	var best := {}
	var best_gain := 2.5
	for c in e.me(pi).hand:
		if not c.def.is_instant() or not e.can_cast(pi, c):
			continue
		var te: Dictionary = c.def.targeted_effect()
		var targets: Array = [{}]
		if not te.is_empty():
			targets = e.legal_targets(pi, te)
		for t in targets:
			var sim := _simulate_trick(e, pi, c, t)
			var gain: float = _combat_score(e, pi, sim["mods"], sim["face"]) - base
			gain -= c.def.mana_value() * 0.3
			if gain > best_gain:
				best_gain = gain
				best = { "card": c, "target": t }
	return best


func _simulate_trick(e: BattleEngine, pi: int, c, t: Dictionary) -> Dictionary:
	var mods := {}
	var face := 0
	for eff in c.def.effects:
		var op: String = eff.get("op", "")
		var tg: String = eff.get("target", "")
		var uids: Array = []
		if tg in ["any", "creature", "enemy_creature", "own_creature"]:
			if t.get("kind", "") == "creature":
				uids.append(t["uid"])
			elif t.get("kind", "") == "player" and op == "damage":
				face += int(eff.get("amount", 0)) * (1 if t["index"] != pi else -1)
		elif tg == "all_enemy_creatures":
			uids = e.opp(pi).battlefield.map(func(x): return x.uid)
		if op == "buff_all":
			uids = e.me(pi).battlefield.map(func(x): return x.uid)
		for u in uids:
			if not mods.has(u):
				mods[u] = { "p": 0, "t": 0, "dmg": 0, "gone": false, "kw": [] }
			var m: Dictionary = mods[u]
			match op:
				"pump", "buff_all":
					m["p"] += int(eff.get("power", 0))
					m["t"] += int(eff.get("toughness", 0))
				"grant":
					m["kw"].append(eff.get("keyword", ""))
				"damage":
					m["dmg"] += int(eff.get("amount", 0))
				"destroy", "bounce":
					m["gone"] = true
	return { "mods": mods, "face": face }


## Rough evaluation of how the pending combat goes for player `pi`.
func _combat_score(e: BattleEngine, pi: int, mods: Dictionary, face: int) -> float:
	var score := face * 0.6
	var dmg_to := [0, 0]
	for a_uid in e.attackers:
		var a = e.find(a_uid)
		if a == null:
			continue
		var am: Dictionary = mods.get(a_uid, {})
		var a_p: int = a.power() + am.get("p", 0)
		var a_t: int = a.toughness() + am.get("t", 0)
		var a_d: int = a.damage + am.get("dmg", 0)
		var a_gone: bool = am.get("gone", false) or a_d >= a_t
		var a_sign := 1.0 if a.owner == pi else -1.0
		if a_gone:
			score -= a_sign * creature_value(a)
			continue
		var b_uid: int = e.blocks.get(a_uid, -1)
		var b = e.find(b_uid)
		if b == null:
			if b_uid == -1:
				dmg_to[1 - a.owner] += a_p
			continue
		var bm: Dictionary = mods.get(b_uid, {})
		var b_p: int = b.power() + bm.get("p", 0)
		var b_t: int = b.toughness() + bm.get("t", 0)
		var b_d: int = b.damage + bm.get("dmg", 0)
		if bm.get("gone", false) or b_d >= b_t:
			score += a_sign * creature_value(b)
			if a.has_kw("trample"):
				dmg_to[1 - a.owner] += a_p
			continue
		var a_fs: bool = a.has_kw("first_strike") or am.get("kw", []).has("first_strike")
		var b_fs: bool = b.has_kw("first_strike") or bm.get("kw", []).has("first_strike")
		var a_kills := _kills(a, b, a_p, b_t, b_d)
		var b_kills := _kills(b, a, b_p, a_t, a_d)
		if a_fs and not b_fs and a_kills:
			b_kills = false
		if b_fs and not a_fs and b_kills:
			a_kills = false
		if a_kills:
			score += a_sign * creature_value(b)
			if a.has_kw("trample"):
				dmg_to[1 - a.owner] += max(0, a_p - (b_t - b_d))
		if b_kills:
			score -= a_sign * creature_value(a)
	var opp_life: int = e.opp(pi).life - face
	var my_life: int = e.me(pi).life
	score += dmg_to[1 - pi] * 0.6 - dmg_to[pi] * 0.6
	if dmg_to[1 - pi] >= opp_life:
		score += 100.0
	if dmg_to[pi] >= my_life:
		score -= 100.0
	return score
