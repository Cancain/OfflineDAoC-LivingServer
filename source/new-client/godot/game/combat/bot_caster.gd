class_name BotCaster
extends Node
## Spells and bows for gamebots and companions (owner 2026-10-11: "wire in gamebot brains to buff their groups,
## themselves, heal, cast spells at range, use bows at range"). One per Combat (the game's and every world host zone's),
## the player's rules throughout: SpellRules for cast time, power, to-hit, damage and variance, Casting.sum_buffs /
## buff_eff for buffs, the interrupt rule (a blow in the first half of a cast spoils it, then 3 s before another), 5
## endurance a finished cast, recast delays; the bow's draw from its speed and quickness, arrows from the backpack, line
## of sight, and the arrow resolved as the bot's blow with the bow (Combat.bot_swing).
##   heals    the old triage - under 65% in a fight (a healer class under 80%), under 40% an emergency (instant heals
##            first), topping up under 90% out of one; the heal that fits the wound. A companion's group is you and
##            your companions, a gamebot's is itself (bot groups come later)
##   buffs    every buff it knows (best rank of each), kept up on its group - automatically (companions: never on the bar)
##   attacks  damage spells and damage over time on its prey from range; else the bow (classes that train a bow line);
##            else melee (BotSim). Hybrids (not list casters) melee and cast only while closing in; damage ranks under
##            half its best damage spell's level are skipped; instant self combat buffs go up in a fight
## A companion's heals and attacks are the ones on its TACTICS bar, first that fits (owner); passive never attacks.
## Its brain (BotSim) reads `hold` on the BotFoe: -1 stand still (casting / drawing), > 0 keep this range, 0 melee.
## Not yet: crowd control and debuffs, pet summons, spells on other bots' bars beyond these kinds.

const THINK := 0.6                           # seconds between a bot's looks at what to cast
const HEAL_BELOW_REST := 0.9
const REBUFF_LEFT := 20.0                    # recast a buff with less than this left
const INTERRUPT_S := 3.0
const PRESSED_S := 5.0                       # hit this recently: under melee pressure (old server, 5,000 ms)...
const PRESSED_M := Combat.REACH + 35.0 * 0.025   # ...with its prey this close (MeleeAttackRange + 35 units)
const DD_TYPES := ["DirectDamage", "Bolt", "Lifedrain", "DamageSpeedDecrease", "DirectDamageWithDebuff"]
const HEAL_TYPES := ["Heal", "SpreadHeal", "OmniHeal"]
const BUFF_TYPES := ["StrengthBuff", "ConstitutionBuff", "DexterityBuff", "QuicknessBuff", "StrengthConstitutionBuff",
		"DexterityQuicknessBuff", "AcuityBuff", "BaseArmorFactorBuff", "SpecArmorFactorBuff", "PaladinArmorFactorBuff",
		"MeleeDamageBuff", "CombatSpeedBuff", "HealthRegenBuff", "PowerRegenBuff", "EnduranceRegenBuff", "ArmorAbsorptionBuff",
		"FatigueConsumptionBuff", "DamageAdd", "DamageShield", "BodyResistBuff", "ColdResistBuff", "EnergyResistBuff",
		"HeatResistBuff", "MatterResistBuff", "SpiritResistBuff", "CrushResistBuff", "SlashResistBuff", "ThrustResistBuff",
		"HeatColdMatterBuff", "BodySpiritEnergyBuff"]
const BOW_RANGE := {9: 1760, 18: 1680, 15: 1600}         # Combat.BOW_RANGE (units)
const ARROW_TYPE := 43
const ARROW_SPEED := 1800.0 * 0.025                      # metres a second (Combat.PROJECTILE_UNITS)

var combat: Combat
var _st := {}                                # BotFoe -> its casting state
var _dots: Array = []                        # damage over time on monsters: {b, st, spell, every, next, until, stat, spec}
var _hots: Array = []                        # heals over time: {target, kind, value, every, next, until}
var _arrows: Array = []                      # in flight: [seconds left, BotFoe, NpcState, bow, arrow]
var _clock := 0.0


func _state(b: BotFoe) -> Dictionary:
	var s: Dictionary = _st.get(b, {})
	if s.is_empty():
		s = {"cast": {}, "target": null, "tkind": "", "left": 0.0, "total": 0.0, "recast": {}, "buffs": [],
				"think": randf() * THINK, "interrupt": 0.0, "draw": 0.0, "known_key": "", "known": {}}
		_st[b] = s
	return s


func is_companion(b: BotFoe) -> bool:
	return b.id >= Companions.ID_BASE


## A bot leaves the fights: its effects go (a companion's buffs on you that it keeps up - concentration - end with it).
func forget(b: BotFoe) -> void:
	_st.erase(b)
	_dots = _dots.filter(func(d): return d.b != b)
	if combat and combat.casting:
		for e in combat.casting.effects:
			if int(e.get("from_bot", -1)) == b.id and float(e.until) > 1e8:
				e.until = 0.0


func _physics_process(delta: float) -> void:
	if combat == null:
		return
	_clock += delta
	for b in combat.bots:
		_bot_tick(b as BotFoe, delta)
	_dot_tick(delta)
	_hot_tick(delta)
	_arrow_tick(delta)


func _bot_tick(b: BotFoe, delta: float) -> void:
	var s := _state(b)
	if not b.alive:
		if not (s.cast as Dictionary).is_empty() or float(s.draw) > 0.0 or not (s.buffs as Array).is_empty():
			s.cast = {}
			s.draw = 0.0
			s.buffs = []
			_refresh_buffs(b, s)
		b.hold = 0.0
		return
	_buff_timers(b, s, delta)
	for k in (s.recast as Dictionary).keys():
		s.recast[k] = float(s.recast[k]) - delta
		if float(s.recast[k]) <= 0.0:
			s.recast.erase(k)
	if not (s.cast as Dictionary).is_empty():
		if b.moving and float(s.total) > 0.0:
			b.note("interrupted", {"effect": int((s.cast as Dictionary).get("clienteffect", 0))})
			s.cast = {}
			b.hold = 0.0
			return
		s.left = float(s.left) - delta
		b.hold = -1.0
		if float(s.left) <= 0.0:
			_land(b, s)
		return
	if float(s.draw) > 0.0:
		_draw_tick(b, s, delta)
		return
	s.think = float(s.think) - delta
	if float(s.think) > 0.0:
		return
	s.think = THINK
	_think(b, s)


# ---------------------------------------------------------------- what it knows

## Its spells by kind, the best rank of each (cached until its level or specs change).
func _known(b: BotFoe, s: Dictionary) -> Dictionary:
	var sh := b.sheet
	var sum := 0
	for k in sh.specs:
		sum += int(sh.specs[k])
	var key := "%d|%d|%d" % [sh.class_id(), sh.level, sum]
	if key == String(s.known_key):
		return s.known
	var best := {}                                         # family -> entry (its best rank)
	var out := {"buffs": [], "heals": [], "dds": [], "dots": [], "hots": [], "by_id": {}}
	for line in ClassDb.spell_lines(sh.class_id(), sh.level, sh.specs):
		var levels: Array = line.get("levels", [])
		var spec := sh.level if bool(line.baseline) else int(sh.specs.get(String(line.spec), 1))
		for i in (line.spells as Array).size():
			var sp := ClassDb.spell(int(line.spells[i]))
			if sp.is_empty():
				continue
			var lv := int(levels[i]) if i < levels.size() else 1
			var group := int(sp.get("spellgroup", 0))
			var fam := "%s|%s|%s" % [line.key, str(group) if group != 0 else "%s/%s/%s" % [sp.get("type", ""), sp.get("target", ""), sp.get("damagetype", "")],
					"i" if float(sp.get("casttime", 0)) <= 0.0 else "c"]
			var e := {"spell": sp, "level": lv, "spec": spec, "range": maxf(float(sp.get("range", 0)), 0.0) * 0.025, "fam": fam,
					"cat": _category(sp)}
			out.by_id[int(sp.spellid)] = e                     # every rank (a companion's bar may hold a lower one)
			if not best.has(fam) or int(best[fam].level) < lv:
				best[fam] = e
	# its best damage spell's level: a damage rank under half of it is skipped (old server: a barely trained line's
	# top rank, a level 4 lifedrain on a level 50 Bonedancer, hit for 1)
	var top := 0
	for fam in best:
		if String(best[fam].cat) in ["dds", "dots"]:
			top = maxi(top, int(best[fam].level))
	for fam in best:
		var e: Dictionary = best[fam]
		if String(e.cat) in ["dds", "dots"] and top - int(e.level) >= 5 and int(e.level) * 2 < top:
			continue
		if String(e.cat) != "":
			(out[e.cat] as Array).append(e)
	var ct := String(ClassDb.cls(sh.class_id()).get("class_type", ""))
	out["hybrid"] = ct != "ListCaster"                     # melees, casts while closing in (old server)
	out["healer"] = (out.heals as Array).any(func(h): return String(h.spell.get("target", "")).to_lower() != "self")
	out.dds.sort_custom(func(x, y): return int(x.level) > int(y.level))
	out.heals.sort_custom(func(x, y): return int(x.level) > int(y.level))
	s.known_key = key
	s.known = out
	return out


## What a spell is to a bot: "dds" / "dots" (on its prey), "heals" / "hots" / "buffs" (on its group), "" (not yet used).
static func _category(sp: Dictionary) -> String:
	var kind := String(sp.get("type", ""))
	var tgt := String(sp.get("target", "")).to_lower()
	if tgt == "enemy" and kind in DD_TYPES and int(sp.get("damage", 0)) > 0:
		return "dds"
	if tgt == "enemy" and kind == "DamageOverTime":
		return "dots"
	if not (tgt in ["self", "realm", "group"]):
		return ""
	if kind in HEAL_TYPES:
		return "heals"
	if kind == "HealOverTime":
		return "hots"
	if kind in BUFF_TYPES:
		return "buffs"
	return ""


# ---------------------------------------------------------------- deciding

func _think(b: BotFoe, s: Dictionary) -> void:
	var known := _known(b, s)
	var comp := is_companion(b)
	var bow := _bow_ready(b)
	var has_any: bool = not (known.dds.is_empty() and known.dots.is_empty() and known.heals.is_empty() and known.hots.is_empty() and known.buffs.is_empty())
	if not has_any and bow.is_empty():
		b.hold = 0.0
		return
	var fighting := b.in_combat()
	b.wants_buffs = not fighting and _missing_buff(b, s, known)
	if b.sitting or b.riding:
		b.hold = 0.0
		return
	var prey: NpcState = b.prey if b.prey and b.prey.alive else null
	var attack_ok := prey != null and not (comp and b.stance == "passive")
	var hybrid: bool = known.hybrid
	var far := prey != null and b.pos.distance_to(prey.pos) > 14.0
	# heals first (the old triage), from the bar for a companion, all it knows for a gamebot
	var heals := []
	var attacks := []
	if comp:
		for t in b.tactics:
			if not (t is Dictionary) or String(t.get("kind", "")) != "spell":
				continue
			var e: Dictionary = known.by_id.get(int(t.get("id", 0)), {})
			if e.is_empty():
				continue
			if String(e.cat) in ["heals", "hots"]:
				heals.append(e)
			elif String(e.cat) in ["dds", "dots"]:
				attacks.append(e)
	else:
		heals = known.heals + known.hots
		attacks = known.dots + known.dds                   # damage over time first, when it is not on the prey yet
	if _heal_pass(b, s, heals, fighting, bool(known.healer)):
		return
	# a hybrid fights with its weapon and casts only while closing in (old server: within ~14 m it melees)
	if attack_ok and (not hybrid or far):
		for e in attacks:
			if _try_attack(b, s, e, prey):
				return
	if not fighting or prey == null:
		for e in known.buffs:
			if _try_buff(b, s, e):
				return
	else:
		for e in known.buffs:                              # in a fight: its instant self combat buffs (old server)
			var sp: Dictionary = e.spell
			if float(sp.get("casttime", 0)) <= 0.0 and String(sp.get("target", "")).to_lower() == "self" and _try_buff(b, s, e):
				return
	# the range it keeps from its prey: its spells', else its bow's, else melee
	# (out of its sight it closes in - melee - rather than standing at range with nothing to cast at)
	b.hold = 0.0
	if attack_ok and not hybrid and pressed(b) and b.pos.distance_to(prey.pos) <= PRESSED_M:
		return                                             # a monster on it: its melee weapon, instants only (owner:
															# casters walked in to cast and kept casting while hit)
	if attack_ok and not hybrid:
		var r := 0.0
		for e in attacks:
			if not _castable(b, s, e, true) or float(e.range) <= 0.0:
				continue
			if String(e.cat) == "dots" and _dots.any(func(d): return d.b == b and d.st == prey and int(d.spell.spellid) == int(e.spell.spellid)):
				continue                                       # (already on it)
			r = float(e.range) if r <= 0.0 else minf(r, float(e.range))
		if r > 0.0 and _sees(b, prey.pos):
			b.hold = r * 0.9
		elif not bow.is_empty() and _clear_shot(b, prey.pos):
			var reach := _bow_range(b, bow, prey)
			b.hold = reach * 0.9
			var d := b.pos.distance_to(prey.pos)
			if d <= 3.5 or (pressed(b) and d <= PRESSED_M):
				b.hold = 0.0                                   # a monster on it: its melee weapon, as a caster does (owner)
			elif d <= reach:
				_start_draw(b, s, bow)




## standing: whether it could cast it once it stands at range (the range it keeps) - only its recast and power.
func _castable(b: BotFoe, s: Dictionary, e: Dictionary, standing := false) -> bool:
	var sp: Dictionary = e.spell
	if (s.recast as Dictionary).has(int(sp.spellid)):
		return false
	var timed := float(sp.get("casttime", 0)) > 0.0
	if timed and not standing and not bool(sp.get("uninterruptible", false)):
		if _clock < float(s.interrupt) or pressed(b):
			return false                                   # (under attack: instants only - old server CheckHealSpell /
															# CheckDefensiveSpells, IsBeingInterrupted)
	if timed and b.moving and not standing:
		return false                                       # (a cast needs it standing - BotSim stops it while casting)
	return b.sheet.power_pts >= SpellRules.power_cost(sp, b.sheet.max_power)


## A monster has hit it in the last 5 s (old server TryEngageUnderMeleePressure: IsBeingInterruptedByOther, or its
## target's direct attack within 5 s) - a caster can't keep starting interruptible casts with a monster on it.
func pressed(b: BotFoe) -> bool:
	return Time.get_ticks_msec() / 1000.0 - b.hit_at < PRESSED_S


## Its group: [kind, object, health ratio, position] for each member alive.
func _group(b: BotFoe) -> Array:
	var out := [["bot", b, float(b.sheet.hp) / maxf(1.0, float(b.sheet.max_hp)), b.pos]]
	if not is_companion(b):
		return out
	if combat.player and not combat.player.dead and PlayerData.hp > 0:
		out.append(["player", null, float(PlayerData.hp) / maxf(1.0, float(PlayerData.max_hp)), combat.player.global_position])
	for o in combat.bots:
		var ob := o as BotFoe
		if ob != b and ob.alive and is_companion(ob):
			out.append(["bot", ob, float(ob.sheet.hp) / maxf(1.0, float(ob.sheet.max_hp)), ob.pos])
	return out


## The heal pass (old server triage): in a fight a member under 65% needs a heal (a healer class tops up under 80%),
## under 40% is an emergency (instant heals first); out of a fight it tops up under 90%. The neediest member first; the
## heal that best fits its wound (the smallest that covers it, else the biggest) - no big heal on a scratch.
func _heal_pass(b: BotFoe, s: Dictionary, heals: Array, fighting: bool, healer: bool) -> bool:
	if heals.is_empty():
		return false
	var below := (0.8 if healer else 0.65) if fighting else HEAL_BELOW_REST
	var worst: Array = []
	for m in _group(b):
		if float(m[2]) < below and (worst.is_empty() or float(m[2]) < float(worst[2])):
			worst = m
	if worst.is_empty():
		return false
	var emergency := float(worst[2]) < 0.4
	var max_hp := float(PlayerData.max_hp if worst[0] == "player" else (worst[1] as BotFoe).sheet.max_hp)
	var wound := max_hp * (1.0 - float(worst[2]))
	var instant_ready := emergency and heals.any(func(h): return float(h.spell.get("casttime", 0)) <= 0.0 and _castable(b, s, h))
	var fit := {}
	var fit_amount := INF
	var biggest := {}
	var big_amount := -1.0
	for e in heals:
		var sp: Dictionary = e.spell
		if not _castable(b, s, e):
			continue
		if String(sp.get("target", "")).to_lower() == "self" and worst[1] != b:
			continue
		var reach := maxf(float(e.range), float(sp.get("radius", 0)) * 0.025)
		if worst[1] != b and b.pos.distance_to(worst[3]) > maxf(reach, 1.0):
			continue
		if String(sp.type) == "HealOverTime" and (_has_hot(worst) or emergency):
			continue
		if instant_ready and float(sp.get("casttime", 0)) > 0.0:
			continue                                           # (an instant heal is ready: that first)
		var v := float(sp.get("value", 0))
		var amount := -v / 100.0 * max_hp if v < 0.0 else v
		if amount >= wound and amount < fit_amount:
			fit = e
			fit_amount = amount
		if amount > big_amount:
			biggest = e
			big_amount = amount
	var pick: Dictionary = fit if not fit.is_empty() else biggest
	if pick.is_empty():
		return false
	_begin(b, s, pick.spell, worst[0], worst[1])
	return true


## A buff of its missing on its group that it could cast (a companion casts it before it sits down to rest).
func _missing_buff(b: BotFoe, s: Dictionary, known: Dictionary) -> bool:
	for e in known.buffs:
		var sp: Dictionary = e.spell
		if (s.recast as Dictionary).has(int(sp.spellid)) or b.sheet.power_pts < SpellRules.power_cost(sp, b.sheet.max_power):
			continue
		var tgt := String(sp.get("target", "")).to_lower()
		for m in _group(b):
			if tgt == "self" and m[1] != b:
				continue
			if m[1] != b and b.pos.distance_to(m[3]) > maxf(float(e.range), 1.0):
				continue
			if not _has_buff(b, m, sp):
				return true
	return false




func _try_attack(b: BotFoe, s: Dictionary, e: Dictionary, prey: NpcState) -> bool:
	if not _castable(b, s, e):
		return false
	var sp: Dictionary = e.spell
	if b.pos.distance_to(prey.pos) > float(e.range):
		return false
	if String(sp.type) == "DamageOverTime" and _dots.any(func(d): return d.b == b and d.st == prey and int(d.spell.spellid) == int(sp.spellid)):
		return false
	if not _sees(b, prey.pos):
		return false
	_begin(b, s, sp, "npc", prey)
	return true


func _try_buff(b: BotFoe, s: Dictionary, e: Dictionary) -> bool:
	if not _castable(b, s, e):
		return false
	var sp: Dictionary = e.spell
	var tgt := String(sp.get("target", "")).to_lower()
	for m in _group(b):
		if tgt == "self" and m[1] != b:
			continue
		if m[1] != b and b.pos.distance_to(m[3]) > maxf(float(e.range), 1.0):
			continue
		if _has_buff(b, m, sp):
			continue
		_begin(b, s, sp, m[0], m[1])
		return true
	return false


func _has_buff(b: BotFoe, m: Array, sp: Dictionary) -> bool:
	var group := int(sp.get("spellgroup", 0))
	if m[0] == "player":
		if combat.casting == null:
			return true
		for e in combat.casting.effects:
			if e.on is String and String(e.kind) == "buff" and float(e.until) > REBUFF_LEFT and \
					((group != 0 and int(e.spell.get("spellgroup", 0)) == group) or int(e.spell.spellid) == int(sp.spellid)):
				return true
		return false
	var ob := m[1] as BotFoe
	for e in _state(ob).buffs:
		if float(e.until) > REBUFF_LEFT and ((group != 0 and int(e.spell.get("spellgroup", 0)) == group) or int(e.spell.spellid) == int(sp.spellid)):
			return true
	return false


func _has_hot(m: Array) -> bool:
	return _hots.any(func(h): return h.kind == m[0] and h.target == m[1])


# ---------------------------------------------------------------- casting

func _begin(b: BotFoe, s: Dictionary, sp: Dictionary, tkind: String, target: Variant) -> void:
	s.cast = sp
	s.tkind = tkind
	s.target = target
	s.total = SpellRules.cast_seconds(sp, int(b.sheet.effective_stats()[2]))
	s.left = s.total
	b.hold = -1.0
	b.note("cast", {"effect": int(sp.get("clienteffect", 0)), "name": String(sp.get("name", ""))})
	if float(s.total) <= 0.0:
		_land(b, s)


## A blow on a casting bot (the player's rule): the interrupt chance by level, then 3 s before a timed spell can start;
## a cast in its first half is spoilt; a bow's draw is lost.
func on_attacked(b: BotFoe, attacker_level: int) -> void:
	var s := _state(b)
	if randf() * 100.0 >= 100.0 + (attacker_level - b.sheet.level) * 3.0:
		return
	s.interrupt = maxf(float(s.interrupt), _clock + INTERRUPT_S)
	if float(s.draw) > 0.0:
		s.draw = 0.0
	var sp: Dictionary = s.cast
	if sp.is_empty() or bool(sp.get("uninterruptible", false)):
		return
	if float(s.total) > 0.0 and (float(s.total) - float(s.left)) >= float(s.total) * 0.5:
		return
	s.cast = {}
	b.note("interrupted", {"effect": int(sp.get("clienteffect", 0))})


func _land(b: BotFoe, s: Dictionary) -> void:
	var sp: Dictionary = s.cast
	s.cast = {}
	s.think = 0.0
	if sp.is_empty():
		b.hold = 0.0
		return
	var cost := SpellRules.power_cost(sp, b.sheet.max_power)
	if b.sheet.power_pts < cost:
		b.note("interrupted", {"effect": int(sp.get("clienteffect", 0))})
		return
	b.sheet.set_power(b.sheet.power_pts - cost)
	b.note("fired", {"effect": int(sp.get("clienteffect", 0))})
	b.sheet.spend_endurance(5)                              # every finished cast (SpellHandler.CastingCompleted)
	if float(sp.get("recastdelay", 0)) > 0.0:
		s.recast[int(sp.spellid)] = float(sp.recastdelay)
	var kind := String(sp.get("type", ""))
	var tkind := String(s.tkind)
	var target: Variant = s.target
	if tkind == "npc":
		var st := target as NpcState
		if st == null or not st.alive or b.pos.distance_to(st.pos) > float(sp.get("range", 0)) * 0.025 + 2.0:
			return                                             # (gone or out of reach: the spell fizzles)
		if kind == "DamageOverTime":
			_apply_dot(b, sp, st)
		else:
			_apply_dd(b, sp, st)
		return
	var targets: Array = []
	if String(sp.get("target", "")).to_lower() == "group" and (kind in HEAL_TYPES or kind in BUFF_TYPES or kind == "HealOverTime"):
		var reach := maxf(float(sp.get("radius", 0)), float(sp.get("range", 0))) * 0.025
		for m in _group(b):
			if m[1] == b or b.pos.distance_to(m[3]) <= maxf(reach, 1.0):
				targets.append(m)
	else:
		for m in _group(b):
			if m[0] == tkind and m[1] == target:
				targets.append(m)
	for m in targets:
		if kind in HEAL_TYPES:
			_apply_heal(b, sp, m)
		elif kind == "HealOverTime":
			_hots.append({"target": m[1], "kind": m[0], "value": float(sp.get("value", 0)), "every": float(sp.get("frequency", 30)) / 10.0,
					"next": float(sp.get("frequency", 30)) / 10.0, "until": float(sp.get("duration", 0)), "from": b})
		elif kind in BUFF_TYPES:
			_apply_buff(b, sp, m)


func _spell_stat(b: BotFoe) -> int:
	var i := SpellRules.mana_stat(b.sheet.class_id())
	return int(b.sheet.effective_stats()[i]) if i >= 0 else 0


func _apply_dd(b: BotFoe, sp: Dictionary, st: NpcState) -> void:
	var e: Dictionary = _known(b, _state(b)).by_id.get(int(sp.spellid), {})
	var spec := int(e.get("spec", b.sheet.level))
	var hit := SpellRules.hit_chance(int(e.get("level", 1)), b.sheet.level, st.level)
	if String(sp.get("type", "")) in ["DamageSpeedDecrease", "DirectDamageWithDebuff", "Lifedrain"]:
		hit -= 2.5                                         # IsDualComponentSpell
	_fx(sp, st)
	if randf() * 100.0 >= hit:
		combat.add_aggro(st, b, 0)
		combat._engage(st)
		if is_companion(b):
			PlayerData.message.emit("%s resists %s's spell!" % [combat._cap(combat._the(st)), b.name], "spells")
		return
	var dmg := SpellRules.damage(sp, _spell_stat(b), spec, b.sheet.level, st.level, st.resist(int(sp.get("damagetype", 0))))
	_hurt(b, st, dmg)
	if String(sp.get("type", "")) == "Lifedrain" and dmg > 0:
		var back := int(dmg * float(sp.get("lifedrainreturn", 0)) / 100.0)
		b.sheet.set_hp(mini(b.sheet.max_hp, b.sheet.hp + back))


func _hurt(b: BotFoe, st: NpcState, dmg: int) -> void:
	if dmg <= 0 or not st.alive:
		return
	st.damage(dmg)
	combat.add_aggro(st, b, dmg)
	combat._engage(st)
	if combat.npc_casting:
		combat.npc_casting.interrupt(st)
	if st.view:
		var v := st.view as Npc
		v.flinch()
		if st.alive and v.sounds:
			v.sounds.event("pain_light" if dmg < st.max_hp * 0.1 else "pain_medium")
	combat._update_target(st)
	b.last_hit_at = Time.get_ticks_msec() / 1000.0
	if is_companion(b):
		PlayerData.message.emit("%s hits %s for %d damage!" % [b.name, combat._the(st), dmg], "spells")
	if not st.alive:
		combat._bot_killed(b, st)


func _apply_dot(b: BotFoe, sp: Dictionary, st: NpcState) -> void:
	var e: Dictionary = _known(b, _state(b)).by_id.get(int(sp.spellid), {})
	_fx(sp, st)
	if randf() * 100.0 >= SpellRules.hit_chance(int(e.get("level", 1)), b.sheet.level, st.level):
		combat.add_aggro(st, b, 0)
		combat._engage(st)
		return
	_dots = _dots.filter(func(d): return not (d.b == b and d.st == st and int(d.spell.spellid) == int(sp.spellid)))
	var every := float(sp.get("frequency", 40)) / 10.0
	_dots.append({"b": b, "st": st, "spell": sp, "every": every, "next": every, "until": float(sp.get("duration", 0)),
			"stat": _spell_stat(b), "spec": int(e.get("spec", b.sheet.level))})
	combat.add_aggro(st, b, 1)
	combat._engage(st)


func _dot_tick(delta: float) -> void:
	for i in range(_dots.size() - 1, -1, -1):
		var d: Dictionary = _dots[i]
		var st := d.st as NpcState
		var b := d.b as BotFoe
		d.until = float(d.until) - delta
		d.next = float(d.next) - delta
		if not st.alive or b == null or float(d.until) < 0.0:
			_dots.remove_at(i)
			continue
		if float(d.next) <= 0.0:
			d.next = float(d.every)
			_hurt(b, st, SpellRules.damage(d.spell, int(d.stat), int(d.spec), b.sheet.level, st.level, st.resist(int(d.spell.get("damagetype", 0)))))


func _apply_heal(b: BotFoe, sp: Dictionary, m: Array) -> void:
	var e: Dictionary = _known(b, _state(b)).by_id.get(int(sp.spellid), {})
	var v := SpellRules.variance(int(e.get("spec", b.sheet.level)), b.sheet.level, b.sheet.level)
	var amount := float(sp.get("value", 0))
	var max_hp := PlayerData.max_hp if m[0] == "player" else (m[1] as BotFoe).sheet.max_hp
	amount = -amount / 100.0 * max_hp if amount < 0.0 else amount * randf_range(v[0], v[1])
	if m[0] == "player" and combat.player:
		_fx_on(sp, combat.player, 1.8)
	elif m[0] == "bot" and m[1]:
		(m[1] as BotFoe).note("landed", {"effect": int(sp.get("clienteffect", 0))})
	_heal_member(b, m, int(amount))


func _heal_member(b: BotFoe, m: Array, amount: int) -> void:
	if amount <= 0:
		return
	if m[0] == "player":
		if bool(PlayerData.buffs.get("diseased", false)):
			amount /= 2
		if PlayerData.hp < PlayerData.max_hp:
			PlayerData.set_hp(mini(PlayerData.max_hp, PlayerData.hp + amount))
			PlayerData.message.emit("%s heals you for %d hit points." % [b.name, amount], "spells")
	else:
		var ob := m[1] as BotFoe
		if ob and ob.alive:
			ob.sheet.set_hp(mini(ob.sheet.max_hp, ob.sheet.hp + amount))


func _hot_tick(delta: float) -> void:
	for i in range(_hots.size() - 1, -1, -1):
		var h: Dictionary = _hots[i]
		h.until = float(h.until) - delta
		h.next = float(h.next) - delta
		if float(h.until) < 0.0 or (h.kind == "bot" and not (h.target as BotFoe).alive):
			_hots.remove_at(i)
			continue
		if float(h.next) <= 0.0:
			h.next = float(h.every)
			_heal_member(h.from, [h.kind, h.target], int(h.value))


func _apply_buff(b: BotFoe, sp: Dictionary, m: Array) -> void:
	var kind := String(sp.get("type", ""))
	var dur := float(sp.get("duration", 0))
	if dur <= 0.0 and int(sp.get("concentration", 0)) > 0:
		dur = 1e9                                          # kept up while the caster is there (forget)
	var eff := Casting.buff_eff(sp, b.sheet.class_id(), b.sheet.level, b.sheet.specs)
	if m[0] == "player":
		if combat.casting == null:
			return
		combat.casting._add_effect("player", sp, "buff", dur, {"type": kind, "eff": eff, "from_bot": b.id})
		if SpellRules.msg(sp, "message1") != "":
			PlayerData.message.emit(SpellRules.msg(sp, "message1"), "spells")
		if combat.player:
			_fx_on(sp, combat.player, 1.8)
		return
	var ob := m[1] as BotFoe
	ob.note("landed", {"effect": int(sp.get("clienteffect", 0))})   # its effect on the bot (owner 2026-10-11: the
																	# Bonedancer's bone shield showed only on his hands)
	var os := _state(ob)
	var group := int(sp.get("spellgroup", 0))
	os.buffs = (os.buffs as Array).filter(func(x): return not ((group != 0 and int(x.spell.get("spellgroup", 0)) == group) or int(x.spell.spellid) == int(sp.spellid)))
	os.buffs.append({"type": kind, "spell": sp, "eff": eff, "until": dur, "from": b})
	_refresh_buffs(ob, os)


## A bot's buffs counting down; its sheet re-summed when one ends (Casting.sum_buffs - the player's rule).
func _buff_timers(b: BotFoe, s: Dictionary, delta: float) -> void:
	var list: Array = s.buffs
	if list.is_empty():
		return
	var gone := false
	for x in list:
		x.until = float(x.until) - delta
		var from := x.get("from") as BotFoe
		if float(x.until) <= 0.0 or (float(x.until) > 1e8 and from != null and not from.alive):
			gone = true
	if gone:
		s.buffs = list.filter(func(x): return float(x.until) > 0.0 and not (float(x.until) > 1e8 and x.get("from") != null and not (x.get("from") as BotFoe).alive))
		_refresh_buffs(b, s)


func _refresh_buffs(b: BotFoe, s: Dictionary) -> void:
	if b.sheet == null:
		return
	b.sheet.buffs = Casting.sum_buffs(s.buffs)
	b.sheet.recalc_max()


# ---------------------------------------------------------------- the bow

## A bow it can shoot now: the ranged slot holding a bow, arrows in its backpack, endurance for the shot.
func _bow_ready(b: BotFoe) -> Dictionary:
	var bow := b.sheet.item_at(13)
	if bow.is_empty() or not BOW_RANGE.has(int(bow.get("object_type", 0))) or not BotProgress.uses_bow(b):
		return {}
	if b.sheet.end_pts < 5:
		return {}
	for slot in range(CharacterState.BACKPACK, CharacterState.BACKPACK_END + 1):
		var it := b.sheet.item_at(slot)
		if not it.is_empty() and int(it.get("object_type", 0)) == ARROW_TYPE:
			return {"bow": bow, "slot": slot, "ammo": it}
	return {}


func _bow_range(b: BotFoe, ready: Dictionary, st: NpcState) -> float:
	var r := float(BOW_RANGE.get(int(ready.bow.get("object_type", 0)), 1200))
	match (int(ready.ammo.get("spd_abs", 0)) >> 2) & 3:
		0: r *= 0.85
		3: r *= 1.25
	if st:
		r += (b.pos.y - st.pos.y) / 0.025 / 2.0
	return maxf(32.0, r) * 0.025


## Clear shot for an arrow (the player's: walls only, eye to chest).
func _clear_shot(b: BotFoe, at: Vector3) -> bool:
	if combat.npcs == null or not combat.npcs.is_inside_tree():
		return true
	var q := PhysicsRayQueryParameters3D.create(b.pos + Vector3(0, 1.6, 0), at + Vector3(0, 1.0, 0), ZoneLoader.LAYER_WALL)
	return combat.npcs.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _start_draw(b: BotFoe, s: Dictionary, bow: Dictionary) -> void:
	s.draw = CombatRules.player_swing_seconds(bow.bow, int(b.sheet.effective_stats()[3]))
	b.hold = -1.0
	b.note("draw", {})


func _draw_tick(b: BotFoe, s: Dictionary, delta: float) -> void:
	b.hold = -1.0
	s.draw = float(s.draw) - delta
	if float(s.draw) > 0.0:
		return
	s.draw = 0.0
	s.think = 0.0
	var prey: NpcState = b.prey if b.prey and b.prey.alive else null
	var bow := _bow_ready(b)
	if prey == null or bow.is_empty():
		return
	var d := b.pos.distance_to(prey.pos)
	if d > _bow_range(b, bow, prey) or not _clear_shot(b, prey.pos):
		return
	b.sheet.take_one(int(bow.slot))
	b.sheet.spend_endurance(5)
	b.note("shoot", {})
	_arrows.append([d / ARROW_SPEED, b, prey, bow.bow, bow.ammo])


func _arrow_tick(delta: float) -> void:
	for i in range(_arrows.size() - 1, -1, -1):
		_arrows[i][0] = float(_arrows[i][0]) - delta
		if float(_arrows[i][0]) <= 0.0:
			var a: Array = _arrows[i]
			_arrows.remove_at(i)
			var b := a[1] as BotFoe
			var st := a[2] as NpcState
			if b and b.alive and st and st.alive:
				combat.bot_arrow(b, st, a[3], a[4])


# ---------------------------------------------------------------- helpers

func _sees(b: BotFoe, at: Vector3) -> bool:
	if combat.npcs == null or not combat.npcs.is_inside_tree():
		return true
	var q := PhysicsRayQueryParameters3D.create(b.pos + Vector3(0, 1.5, 0), at + Vector3(0, 1.5, 0), ZoneLoader.LAYER_WALL | ZoneLoader.LAYER_FLOOR)
	return combat.npcs.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _fx(sp: Dictionary, st: NpcState) -> void:
	if st.view and is_instance_valid(st.view):
		var v := st.view as Npc
		SpellFx.land(int(sp.get("clienteffect", 0)), v, v.height, v.sounds)


func _fx_on(sp: Dictionary, node: Node3D, height: float) -> void:
	if node and node.is_inside_tree():
		SpellFx.land(int(sp.get("clienteffect", 0)), node, height, null)
