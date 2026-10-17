class_name MeleeMath
## Melee between a character - the player or a gamebot (owner 2026-10-11: bots and players share rules) - and the
## zone's NPCs: who defends, whether the swing lands, how hard. Only the numbers: Combat (the player) and the bots'
## combat both call these and keep their own lines, sounds and effects. CombatRules has the formulas underneath;
## a character is its CharacterState (PlayerData for the player).
##
## A character on defence is given as a dictionary:
##   sheet: CharacterState, pos: Vector3, fwd: Vector2 (its facing on the ground, x / z),
##   busy: bool (sitting, casting or dead: no evade / parry / block), berserk: bool (no defensive abilities),
##   stats: Array (its effective stats), evade_buff / parry_buff: float (Savage buffs, %), attackers: int (monsters on
##   it in melee), arrow: bool (the blow is an arrow), engage: Callable (-> extra block chance; Engage's endurance)


## GameObject.IsObjectInFront: `at` inside the arc (degrees) in front of `from`, facing `fwd`.
static func in_front(from: Vector3, fwd: Vector2, at: Vector3, arc: float) -> bool:
	var to := Vector2(at.x - from.x, at.z - from.z)
	if to.length() < 0.01:
		return true
	return rad_to_deg(absf(fwd.angle_to(to))) < arc / 2.0


## The ground facing of a character from its yaw (the player's convention: -Z ahead at 0).
static func char_fwd(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))


## ...and of an NPC (+Z ahead at 0).
static func npc_fwd(st: NpcState) -> Vector2:
	return Vector2(sin(st.yaw), cos(st.yaw))


## The weapon in the active set's hand (none for ranged: melee can't use a bow).
static func weapon(s: CharacterState) -> Dictionary:
	var slot: int = {"standard": 10, "twohand": 12}.get(s.active_weapon, -1)
	return s.item_at(slot) if slot >= 0 else {}


## The trained level in a spec the class has (0 when it hasn't).
static func spec_level(s: CharacterState, key: String) -> int:
	for e in ClassDb.specs_at(s.class_id(), s.level):
		if String(e.spec) == key:
			return maxi(1, int(s.specs.get(key, 1)))
	return 0


## The abilities the character has at its level and specs: key -> level.
static func known(s: CharacterState) -> Dictionary:
	var out := {}
	for a in ClassDb.abilities_known(s.class_id(), s.level, s.specs):
		out[String(a.key)] = int(a.level)
	return out


## Seconds between swings: weapon speed x (1 - (QUI - 60) x 0.002) x melee speed (haste buffs).
static func swing_seconds(s: CharacterState, w: Dictionary) -> float:
	var haste := float(s.buffs.get("haste", 0.0)) - float(s.buffs.get("slow", 0.0))
	return CombatRules.player_swing_seconds(w, int(s.effective_stats()[3]), 100.0 - haste)


## Where a blow lands, the old server's way (GamePlayer.CalculateArmorHitLocation): torso 40%, legs 25%, arms 15%,
## head 10%, hands 5%, feet 5%.
static func hit_location() -> int:
	var roll := randi_range(1, 100)
	return 25 if roll <= 40 else (27 if roll <= 65 else (28 if roll <= 80 else (21 if roll <= 90 else (22 if roll <= 95 else 23))))


## What is worn where a blow lands (GetArmorAF / GetArmorAbsorb): the piece's AF capped at the level (cloth) or twice
## the level (other armour), times quality and condition, + armour buffs; absorb = the piece's ABS %.
## Returns [af, absorb, slot, item]. (The player's piece also loses condition - Combat does that; bots' never do.)
static func armor(s: CharacterState, slot: int) -> Array:
	var it := s.item_at(slot)
	if it.is_empty():
		return [0.0, 0.0, slot, {}]
	var l := s.level
	var cap := l if int(it.get("object_type", 0)) == 32 else l * 2
	var af := minf(int(it.get("dps_af", 0)), cap) + int(s.buffs.get("af_base", 0)) / 5.0
	af *= int(it.get("quality", 85)) * 0.01 * ItemDb.pct(it, "condition") * 0.01
	af = minf(af, l * 2)
	af += (mini(int(s.buffs.get("af_spec", 0)), int(l * 1.875)) + mini(s.item_bonus(148), l) + int(s.buffs.get("af_other", 0))) / 5.0
	var absorb := int(it.get("spd_abs", 0)) * 0.01 * (1.0 + float(s.buffs.get("absorb", 0.0)) * 0.01)
	return [af, clampf(absorb, 0.0, 1.0), slot, it]


## A character's swing at an NPC: the NPC's template evade / parry / block % (NpcTemplate EvadeChance / ParryChance /
## BlockChance), front arcs, parry halved against a two-handed swing, block only with a left-hand item and no
## left-hand swings; all times 1 - the attacker's defence penetration. Mezzed / stunned: none. `gear`: the NPC's
## equipment (slot -> model). Returns "evade" / "parry" / "block" / "".
static func npc_defends(st: NpcState, s: CharacterState, w: Dictionary, attacker_pos: Vector3, gear: Dictionary) -> String:
	if st.mezzed or st.stunned:
		return ""
	var d: Array = st.spawn.get("defense", [0, 0, 0, 0])
	if int(d[0]) <= 0 and int(d[1]) <= 0 and int(d[2]) <= 0:
		return ""
	var spec := int(s.specs.get(CombatRules.weapon_spec_key(w), 1))
	var pen := CombatRules.defense_penetration(CombatRules.player_weapon_skill(w, s.level, s.class_id(), s.effective_stats()), spec, st.level)
	if int(d[0]) > 0 and in_front(st.pos, npc_fwd(st), attacker_pos, 180.0) and randf() < int(d[0]) * 10 * 0.001 * (1.0 - pen):
		return "evade"
	if int(d[1]) > 0 and in_front(st.pos, npc_fwd(st), attacker_pos, 120.0):
		var c := int(d[1]) * 10 * 0.001 * (1.0 - pen)
		if s.active_weapon == "twohand":
			c *= 0.5
		if randf() < c:
			return "parry"
	if int(d[2]) > 0 and int(d[3]) <= 0 and gear.has(11) and not gear.has(12) and in_front(st.pos, npc_fwd(st), attacker_pos, 120.0):
		if randf() < int(d[2]) * 10 / 1000.0 * (1.0 - pen):
			return "block"
	return ""


## An NPC's swing at a character: "evade", "parry", "block" or "" (GameLiving.TryEvade / TryParry / TryBlock). Nothing
## while busy; evade needs the Evade ability (front 180 degrees), parry the Parry spec and a melee weapon (front 120,
## shared among the attackers, halved against a two-hander), block the Shield ability and a shield with a one-hand
## weapon set (front 120, times the shield's quality and condition, its size = attackers covered).
static func character_defends(st: NpcState, f: Dictionary, npc_two_hand: bool) -> String:
	if bool(f.get("busy", false)) or bool(f.get("berserk", false)):
		return ""
	var s: CharacterState = f.sheet
	var pos: Vector3 = f.pos
	var fwd: Vector2 = f.fwd
	var arrow := bool(f.get("arrow", false))                # arrows: no parry, evade / 5, block + 25% base
	var stats: Array = f.get("stats", s.effective_stats())
	var attackers := maxi(1, int(f.get("attackers", 1)))
	var pen := CombatRules.defense_penetration(CombatRules.npc_weapon_skill(st.level, st.eff(0)), st.level, s.level)
	var k := known(s)
	var evade := int(k.get("Evade", 0))
	var evade_buff := float(f.get("evade_buff", 0.0))
	if (evade > 0 or evade_buff > 0.0) and (k.has("Advanced Evade") or k.has("Enhanced Evade") or in_front(pos, fwd, st.pos, 180.0)):
		if randf() < (CombatRules.evade_permille(int(stats[3]), int(stats[2]), evade) + evade_buff * 10.0) * 0.001 * (1.0 - pen) / (5.0 if arrow else 1.0):
			return "evade"
	var parry := spec_level(s, "Parry")
	var parry_buff := float(f.get("parry_buff", 0.0))
	if not arrow and (parry > 0 or parry_buff > 0.0) and not weapon(s).is_empty() and s.active_weapon != "ranged" and in_front(pos, fwd, st.pos, 120.0):
		var c := ((CombatRules.parry_permille(int(stats[2]), parry) if parry > 0 else 0) + parry_buff * 10.0) * 0.001 / attackers * (1.0 - pen)
		if npc_two_hand:
			c *= 0.5                                        # GameLiving.TwoHandedDefensePenetrationFactor
		if randf() < c:
			return "parry"
	var shield := s.item_at(11)
	if int(k.get("Shield", 0)) > 0 and not shield.is_empty() and int(shield.get("object_type", 0)) == 42 \
			and s.active_weapon == "standard" and in_front(pos, fwd, st.pos, 120.0):
		var c := CombatRules.block_permille(int(stats[2]), spec_level(s, "Shields")) / 1000.0 + (0.25 if arrow else 0.0)
		var engage: Callable = f.get("engage", Callable())
		if engage.is_valid():
			c += float(engage.call())                       # Engage: +65% base block chance (its endurance is the caller's)
		c *= int(shield.get("quality", 85)) * 0.01 * ItemDb.pct(shield, "condition") * 0.01 * (1.0 - pen)
		var covers := maxi(1, int(shield.get("type_damage", 1)))
		if attackers > covers:
			c *= float(covers) / attackers
		if randf() < c:
			return "block"
	return ""


## A character's landed-or-missed swing at an NPC, after its defence was rolled (the old server's order: evade, parry,
## block, then hit or miss). The miss roll (with the style's to-hit and the NPC's last style), its bladeturn, the
## weapon damage (base x skill / armour, x melee damage mods, x its resist to the weapon's damage type, capped at
## 3 x base), the style's damage on top (resisted, its own cap; stealth openers their own uncapped damage), and the
## critical hit (10%; Berserk: every hit, 10% .. level x 25%).
## opts: melee_mult (melee damage debuffs, x), crit_chance (%), crit_top (largest crit share), style_ok (the style's
## opening held before this swing).
## Returns {result: "miss" / "bladeturn" / "hit" / "style", style_failed: bool, dmg, extra (style part), shown (style
## damage before resists), modifier (what resists took, shown "(-N)"), crit, cap}.
static func character_blow(s: CharacterState, st: NpcState, w: Dictionary, style: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var out := {"result": "miss", "style_failed": false, "dmg": 0, "extra": 0, "shown": 0, "modifier": 0, "crit": 0, "cap": 0.0}
	var adjust := 0.0                                      # GetMissChance's style terms
	if not style.is_empty():
		adjust -= float(style.get("bonustohit", 0))
	if st.swing_result == "style" and not st.swing_style.is_empty():
		adjust += float(st.swing_style.get("bonustodefense", 0))
	if randf() < CombatRules.miss_chance(s.level, st.level, adjust, -mini(int(w.get("bonus", 0)), CombatRules.bonus_cap(s.level))):
		return out
	if st.bladeturn:                                       # its bladeturn takes the blow
		st.bladeturn = false
		out.result = "bladeturn"
		return out
	var spec := int(s.specs.get(CombatRules.weapon_spec_key(w), 1))
	var parts := CombatRules.player_damage_parts(w, s.level, s.class_id(), s.effective_stats(), spec, st.level, 1.0,
			st.af_bonus - st.af_debuff, st.absorb())
	var snap: float = parts[0]                             # baseDamageSnapshot: the style works on this
	parts[0] *= float(opts.get("melee_mult", 1.0))         # melee damage debuffs
	parts[0] *= 1.0 + float(s.buffs.get("melee_damage", 0.0)) * 0.01   # melee damage buffs (CalculateDamageTypeModifier)
	# its resist to the weapon's damage type (none in hand: natural) - on the base damage and the style damage alike
	var resist_mod := 1.0 - st.resist(int(w.get("type_damage", 0)) if not w.is_empty() else 0) * 0.01
	var base_f := minf(parts[0] * resist_mod, parts[1])
	var modifier: float = parts[0] * resist_mod - parts[0]
	var extra_f := 0.0
	out.result = "hit"
	out.cap = float(parts[1])
	if not style.is_empty():
		if bool(opts.get("style_ok", false)):
			var s_spec := int(s.specs.get(String(style.speckeyname), 1))
			var sp := CombatRules.style_damage_parts(style, s_spec, swing_seconds(s, w), snap, parts[1])
			out.shown = int(sp[0])
			extra_f = minf(float(sp[0]) * resist_mod, float(sp[1]))   # resisted, then its own cap
			modifier += float(sp[0]) * resist_mod - float(sp[0])
			if bool(style.get("stealthrequirement", false)):
				# StyleProcessor.ExecuteStyle: stealth openers have their own damage (not weapon speed), x the target's
				# absorb factor, uncapped: Backstab I min(5, spec / 10) + spec x 14 / 3, Backstab II min(45, spec) +
				# spec x 6, Perforate Artery min(75, spec x 1.5) + spec x 9
				var sd := 0.0
				match int(style.id):
					335: sd = minf(5.0, s_spec / 10.0) + s_spec * 14.0 / 3.0
					339: sd = minf(45.0, s_spec) + s_spec * 6.0
					343: sd = minf(75.0, s_spec * 1.5) + s_spec * 9.0
				out.shown = int(sd * (1.0 - st.absorb()))
				extra_f = sd * (1.0 - st.absorb()) * resist_mod          # uncapped
				modifier = parts[0] * resist_mod - parts[0] + sd * (1.0 - st.absorb()) * (resist_mod - 1.0)
			out.result = "style"
		else:
			out.style_failed = true                        # "You fail to execute your <style> perfectly!"
	var dmg := maxi(1, int(base_f + extra_f))              # ad.Damage = (int)(capped base + capped style)
	out.extra = int(extra_f)
	out.modifier = floori(modifier)
	# critical hits (AttackComponent.CalculateCriticalDamage): an extra 10-100% of the hit against a monster
	if randf() * 100.0 < float(opts.get("crit_chance", 10.0)):
		out.crit = int(dmg * randf_range(0.1, float(opts.get("crit_top", 1.0))))
	out.dmg = dmg
	return out


## An NPC's swing at a character, after the character's defence was rolled - does it miss? None on a sitting
## character; the NPC style's to-hit, the character's last style's defence (f.last_result / f.last_style: its own
## last swing) and the bonus of the piece struck (`slot`, from hit_location() - set before the miss roll).
static func npc_misses(st: NpcState, f: Dictionary, style: Dictionary, slot: int) -> bool:
	var s: CharacterState = f.sheet
	var piece_bonus := mini(int(s.item_at(slot).get("bonus", 0)), CombatRules.bonus_cap(s.level))
	var adjust := 0.0
	if not style.is_empty():
		adjust -= float(style.get("bonustohit", 0))
	var my_style: Dictionary = f.get("last_style", {})
	if String(f.get("last_result", "")) == "style" and not my_style.is_empty():
		adjust += float(my_style.get("bonustodefense", 0))
	return not bool(f.get("sitting", false)) and randf() < CombatRules.miss_chance(st.level, s.level, adjust, piece_bonus)


## ...and its damage when it lands (after the character's bladeturn): base x skill / armour on the struck piece, its
## melee damage debuff, the character's resists (race, items, buffs, the piece's armour resist), the 3 x base cap,
## and its style's damage on top (GetModifiedSpecLevel: its level). weapon_kind: the NPC's "one_hand" / "two_hand" /
## "ranged"; secs: its swing time (styles scale with it). Returns {result: "hit" / "style", dmg, modifier, where}.
static func npc_damage(st: NpcState, s: CharacterState, slot: int, style: Dictionary, style_ok: bool, weapon_kind: String,
		secs: float) -> Dictionary:
	var worn := armor(s, slot)
	var where: String = {25: "torso", 27: "leg", 28: "arm", 21: "head", 22: "hand", 23: "foot"}.get(int(worn[2]), "torso")
	var dt := int(st.spawn.get("damage_type", 2))
	var resist_mod := 1.0 - (s.resist(dt) + CombatRules.armor_resist(worn[3], dt)) * 0.01
	var parts := CombatRules.npc_damage_parts(st.level, st.eff(0), s.level, worn[0], worn[1], weapon_kind)
	var raw: float = parts[0] * (1.0 - st.melee_debuff * 0.01)
	var modifier := raw * resist_mod - raw
	var dmg := maxi(1, int(minf(raw * resist_mod, parts[1])))
	var result := "hit"
	if style_ok:
		var sp := CombatRules.style_damage_parts(style, st.level, secs, parts[0], parts[1])
		modifier += float(sp[0]) * resist_mod - float(sp[0])
		dmg = maxi(1, int(minf(raw * resist_mod, parts[1]) + minf(float(sp[0]) * resist_mod, float(sp[1]))))
		result = "style"
	return {"result": result, "dmg": dmg, "modifier": floori(modifier), "where": where}
