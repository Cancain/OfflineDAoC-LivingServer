class_name CombatRules
extends RefCounted
## The melee and experience rules, written for this engine. The numbers come from content/rules/rules.json
## (pipeline/build_rules.py: the old OfflineDAoC server's tables and constants, read as data - no old code), the
## formulas are the period ones that server documents (camelotherald Melee_Damage, 1.65 quickness, pre-1.117C miss
## rate). Notes per function; the full list is in memory "mmoengine-combat-build".

static var _r := {}

## A weapon's object type -> the specialization its damage and styles use (old server eObjectType / Specs).
const OBJECT_SPEC := {2: "Crush", 3: "Slash", 4: "Thrust", 5: "Longbows", 6: "Two Handed", 7: "Polearm", 8: "Staff",
		9: "Longbows", 10: "Crossbow", 11: "Sword", 12: "Hammer", 13: "Axe", 14: "Spear", 15: "Composite Bow",
		16: "Thrown Weapons", 17: "Left Axe", 18: "Recurve Bow", 19: "Blades", 20: "Blunt", 21: "Piercing",
		22: "Large Weapons", 23: "Celtic Spear", 24: "Flexible", 25: "Hand to Hand", 26: "Scythe"}


static func weapon_spec_key(item: Dictionary) -> String:
	return OBJECT_SPEC.get(int(item.get("object_type", 0)), "")


static func r() -> Dictionary:
	if _r.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://content/rules/rules.json"))
		_r = parsed if parsed is Dictionary else {}
	return _r


static func melee() -> Dictionary:
	return r().get("melee", {})


# --- health -----------------------------------------------------------------------------------------------------

## A player: 20 + BaseHP x L / 50 + (BaseHP x L) x (CON - 50) / 10000, a CON under 50 counting double.
static func player_max_hp(class_id: int, level: int, con: int) -> int:
	var base := int(ClassDb.cls(class_id).get("base_hp", r().get("base_classes", {}).get(str(class_id), {}).get("base_hp", 700)))
	var c := con - 50
	if c < 0:
		c *= 2
	var hp1 := base * level
	return maxi(1, 20 + hp1 / 50 + hp1 * c / 10000)


## A monster's unstyled damage cap (3 x its base damage) - damage shields can't hurt it for more.
static func npc_damage_cap(level: int) -> float:
	var m := melee()
	var speed := float(m.get("npc_weapon_speed", {}).get("one_hand", 3.0)) * 10.0
	var base := (1.0 + level / float(m.get("npc_damage_f1", 3.2)) + level * level / float(m.get("npc_damage_f2", 150))) * speed * 0.1
	return base * float(m.get("damage_cap_factor", 3.0))


## A monster: 11 x (L + 1) + 0.6 x L^2 + (CON - 25) x 1.8.
static func npc_max_hp(level: int, con: int) -> int:
	var h: Dictionary = r().get("npc_hp", {})
	return maxi(1, int(float(h.get("per_level_plus_one", 11)) * (level + 1) + float(h.get("per_level_squared", 0.6)) * level * level
			+ (con - float(h.get("con_offset", 25))) * float(h.get("per_con", 1.8))))


## A monster's STR / CON / DEX / QUI: with force_mob_autoset_stats (on in the old server) base + (L - 1) x
## multiplier each (30 + (L - 1)); otherwise its own values, autoset where they are below 1.
## martial: GameNPC.AutoSetStats' penalty for monster casters (build_npcs.py martial_factor) on STR, CON and QUI.
static func npc_stats(level: int, own: Array, martial := 1.0) -> Array:
	var a: Dictionary = r().get("npc_autoset", {})
	var out := []
	for i in 4:
		var k: String = ["str", "con", "dex", "qui"][i]
		var auto := maxi(1, int((float(a.get(k + "_base", 30)) + (level - 1) * float(a.get(k + "_multiplier", 1))) * (martial if i != 2 else 1.0)))
		var mine := int(own[i]) if i < own.size() else 0
		out.append(auto if bool(a.get("force", true)) or mine < 1 else mine)
	return out


## GetMissChance's item bonus cap by level: 0 under 15, then 5 more each 5 levels, 35 from 45.
static func bonus_cap(level: int) -> int:
	return 0 if level < 15 else mini(35, (level - 10) / 5 * 5)


# --- hitting ----------------------------------------------------------------------------------------------------

## Miss chance (0..1): 18% base, 1.33% less per level the attacker is above the defender (PvE), floor 0.
## style_adjust (GetMissChance): - the attacker's style BonusToHit + the defender's last landed style BonusToDefense.
## item_bonus: the struck armour piece's Bonus less the attacker's weapon's (each capped by bonus_cap) - x (1 + it / 100).
static func miss_chance(attacker_level: int, defender_level: int, style_adjust := 0.0, item_bonus := 0) -> float:
	var m := melee()
	var c := float(m.get("base_miss_percent", 18)) - (attacker_level - defender_level) * float(m.get("miss_per_level_pve", 1.3333))
	c += c * item_bonus / 100.0 + style_adjust
	return clampf(c / 100.0, 0.0, 1.0)


## Seconds between a player's swings: weapon speed x (1 - (QUI - 60) x 0.002), QUI capped at 250.
## melee_speed: the MeleeSpeed property in % (100, less with haste buffs); never under 1.5 s (AttackComponent.AttackSpeed:
## the player minimum is 1500 ms).
static func player_swing_seconds(item: Dictionary, quickness: int, melee_speed := 100.0) -> float:
	var speed := int(item.get("spd_abs", 30)) / 10.0
	return maxf(1.5, speed * (1.0 - (mini(quickness, 250) - 60) * float(melee().get("quickness_speed", 0.002))) * melee_speed / 100.0)


## The stat a weapon's damage uses: DEX for staffs / bows, (STR + DEX) / 2 for thrust weapons, STR otherwise.
static func weapon_stat(item: Dictionary, stats: Array) -> int:
	var ot := int(item.get("object_type", 0))
	if ot in [8, 9, 15, 18, 42]:
		return int(stats[2])
	if int(item.get("type_damage", 0)) == 3:
		return (int(stats[0]) + int(stats[2])) / 2
	return int(stats[0])


## One player swing's damage against a monster (before the 3x cap and the minimum of 1).
##   base   = DPS x speed x 0.1 x (1 + (speed - 2.0s) x 0.03) [x two-hand / bow bonus] x quality x condition
##   skill  = L x class weapon-skill base / 200 x (1 + stat / 200) x variance
##   armor  = monster AF / (1 - monster absorb)
##   damage = base x skill / armor   (capped at 3 x base)
## variance: min = 0.75 + 0.5 x min((spec - 1) / (target level + 1), 1), then a roll up to min + 0.5.
static func player_damage(item: Dictionary, level: int, class_id: int, stats: Array, spec: int,
		target_level: int) -> int:
	var p := player_damage_parts(item, level, class_id, stats, spec, target_level)
	return maxi(1, int(minf(p[0], p[1])))


## [damage before the cap, the cap (3 x base)] of one swing - styles grow from these (style_damage).
## Two-handers and bows add 10% + 0.5% per spec level (AttackComponent.CalculateTwoHandedDamageModifier); arrows
## their head's damage (ammo_mod: 0.85 blunt / 1.0 bodkin / 1.25 broadhead). The cap is 3 x the base before quality and
## condition ("Quality and condition don't affect damage cap").
static func player_damage_parts(item: Dictionary, level: int, class_id: int, stats: Array, spec: int,
		target_level: int, ammo_mod := 1.0, target_af_bonus := 0, target_absorb := -1.0) -> Array:
	var m := melee()
	var dps := minf(int(item.get("dps_af", 0)) / 10.0, 1.2 + 0.3 * level)   # the level's DPS cap
	var spd := int(item.get("spd_abs", 30))
	var base := dps * spd * 0.1 * (1.0 + (spd - 20) * float(m.get("slow_weapon_per_speed", 0.003)))
	if int(item.get("item_type", 10)) in [12, 13]:                       # two-handed / ranged slot
		base *= 1.1 + spec * 0.005
	base *= ammo_mod
	var cap := base * float(m.get("damage_cap_factor", 3.0))
	base *= int(item.get("quality", 85)) / 100.0 * ItemDb.pct(item, "condition") / 100.0
	var ws_base := int(ClassDb.cls(class_id).get("weapon_skill", r().get("base_classes", {}).get(str(class_id), {}).get("weapon_skill", 400)))
	var low := 0.75 + 0.5 * minf((spec - 1.0) / (target_level + 1.0), 1.0)
	var skill := level * ws_base / 200.0 * (1.0 + 0.01 * weapon_stat(item, stats) / 2.0) * randf_range(low, low + 0.5)
	var dmg := base * skill / npc_armor(target_level, target_af_bonus, target_absorb) * float(m.get("pve_melee_damage", 1.0))
	return [dmg, cap]


## A style's extra damage (old server StyleProcessor.ExecuteStyle): growth rate x spec x swing seconds, as a share of
## the unstyled cap, times the unstyled damage; at least 1 when the style grows at all.
## Returns [style damage, its cap]: GR x spec x seconds x unstyled / unstyled cap, capped (after resists, by the caller)
## at GR x spec x seconds; a growing style under 1 does 1 with a cap of 0 - so it shows "+1" and adds nothing, as the
## old code (its "at least 1" is undone by its own cap).
static func style_damage_parts(style: Dictionary, spec: int, swing_seconds: float, unstyled: float, cap: float) -> Array:
	var g := float(style.get("growthrate", 0.0))
	if cap <= 0.0:
		return [0.0, 0.0]
	var r := g * spec * swing_seconds / cap
	var d := r * unstyled
	var c := r * cap
	if d < 1.0 and g > 0.0:
		return [1.0, 0.0]
	return [d, c]


static func style_damage(style: Dictionary, spec: int, swing_seconds: float, unstyled: float, cap: float) -> int:
	var p := style_damage_parts(style, spec, swing_seconds, unstyled, cap)
	return int(minf(float(p[0]), float(p[1])))


## Endurance a style costs (CalculateEnduranceCost): weapon speed (tenths) x cost / 40, +1 under 4.0 s, at least 1.
static func style_endurance(style: Dictionary, weapon_spd: int) -> int:
	var cost := weapon_spd * int(style.get("endurancecost", 0)) / 40
	if weapon_spd < 40:
		cost += 1
	return maxi(1, cost)


## A monster's armour against melee: AF / (1 - absorb), AF = (1 + L / 200) x L x 12.5 / 5 (GetArmorAF divides the
## ArmorFactor property by 5), absorb = L x 0.54%.
## af_bonus: its armour buffs less armour debuffs; absorb: NpcState.absorb() (its CON / DEX buffs and debuffs and
## absorb debuffs counted), or < 0 for the plain level absorb.
## divisor: ArmorFactorCalculator's level divisor - 200 for monsters, 175 for summoned pets.
static func npc_armor(level: int, af_bonus := 0, absorb := -1.0, divisor := 0.0) -> float:
	var m := melee()
	# the monster's real level (ArmorFactorCalculator / GameLiving.GetBaseAbsorb use Level as is): a level 0 monster has
	# AF 0 and absorb 0, so the floor of 1 applies. (Was clamped to 1 here, ~2.5x the armour on level 0 monsters -
	# owner 2026-10-10: a level 1 Guardian hit an annoying lucradan for 2-3, the old client for 5-8.)
	var l := maxi(level, 0)
	var af: Dictionary = m.get("npc_af", {})
	var div := divisor if divisor > 0.0 else float(af.get("divisor", 200))
	var armor_factor := ((1.0 + l / div) * l * float(af.get("factor", 12.5)) + af_bonus) / 5.0
	if absorb < 0.0:
		absorb = l * float(m.get("npc_absorb_per_level", 0.0054))
	return maxf(1.0, armor_factor / (1.0 - minf(absorb, 0.99)))


# --- debuffs and resists (StatCalculator.ApplyDebuffs, ResistCalculator, SkillBase race / armour resists) -------------

const DAMAGE_NAMES := {0: "natural", 1: "crush", 2: "slash", 3: "thrust", 10: "body", 11: "cold", 12: "energy", 13: "heat",
		14: "matter", 15: "spirit"}
const RESIST_PROP := {0: 249, 1: 13, 2: 17, 3: 19, 10: 11, 11: 12, 12: 14, 13: 15, 14: 16, 15: 18}   # eProperty Resist_*


static func _debuff_vs(debuff: int, stat: int, modifier: float) -> Array:
	var rem := debuff - stat * modifier
	if rem > 0.0:
		return [int(rem), 0]
	return [0, stat - int(debuff / modifier)]


## StatCalculator.ApplyDebuffs: single-stat (base) debuffs take 100% off buffs, then 50% off base + item stats; dual-stat
## (spec) debuffs 200% off buffs, then 50% off base + item. Returns [base debuff left, spec debuff left, buff, base + item].
static func apply_debuffs(base_debuff: int, spec_debuff: int, buff: int, base_item: int) -> Array:
	var bd := absi(base_debuff)
	var sd := absi(spec_debuff)
	var x: Array
	if sd > 0 and buff > 0:
		x = _debuff_vs(sd, buff, 0.5)
		sd = x[0]
		buff = x[1]
	if sd > 0 and base_item > 0:
		x = _debuff_vs(sd, base_item, 2.0)
		sd = x[0]
		base_item = x[1]
	if bd > 0 and buff > 0:
		x = _debuff_vs(bd, buff, 1.0)
		bd = x[0]
		buff = x[1]
	if bd > 0 and base_item > 0:
		x = _debuff_vs(bd, base_item, 2.0)
		bd = x[0]
		base_item = x[1]
	return [bd, sd, buff, base_item]


## A stat with its buffs and debuffs, at least 1.
static func debuffed_stat(base_item: int, buff: int, base_debuff: int, spec_debuff: int) -> int:
	var r := apply_debuffs(base_debuff, spec_debuff, buff, base_item)
	return maxi(1, int(r[3]) + int(r[2]))


## StatCalculator.CalculateBuffContributionToAbsorbOrResist (monsters): (buff - leftover debuffs / 2) / 100.
static func buff_contribution(buff: int, base_debuff: int, spec_debuff: int) -> float:
	var r := apply_debuffs(base_debuff, spec_debuff, buff, 0)
	return (int(r[2]) - (int(r[0]) + int(r[1])) / 2.0) * 0.01


## A race's resist to a damage type (the Race table; players' and monsters' races).
static func race_resist(race: int, damage_type: int) -> int:
	if race == 0:
		return 0
	return int(r().get("race_resists", {}).get(str(race), {}).get(String(DAMAGE_NAMES.get(damage_type, "")), 0))


## An armour piece's resist to a damage type by its realm and armour type (SkillBase.GetArmorResist: +10 / -10).
static func armor_resist(item: Dictionary, damage_type: int) -> int:
	if item.is_empty():
		return 0
	var key := "%d|%d" % [int(item.get("realm", 0)), int(item.get("object_type", 0))]
	return int(r().get("armor_resists", {}).get(key, {}).get(String(DAMAGE_NAMES.get(damage_type, "")), 0))


## Seconds between a monster's swings (one-hand 3.0 s, slowed or sped by its quickness like a player's).
static func npc_swing_seconds(quickness: int, weapon := "one_hand") -> float:
	return maxf(0.5, float(melee().get("npc_weapon_speed", {}).get(weapon, 3.0)) * (1.0 - (quickness - 60) / 500.0))   # NPC minimum 500 ms


## One monster swing against the player:
##   base   = (1 + L / 3.2 + L^2 / 150) x speed x 0.1
##   skill  = L x 2.5 x (1 + (STR + 30) / 200) x 0.9..1.1
##   armor  = (worn AF + L x 0.4 player bonus) / (1 - worn absorb)
## weapon: "one_hand", "two_hand" or "ranged" (AttackComponent.NpcWeaponSpeed: 3.0 / 4.0 / 4.5 s by the slot of the
## weapon it holds).
## resist_mod: 1 - (the player's resist + the struck piece's armour resist) / 100, before the cap
## (AttackComponent.CalculateTargetResistanceFactor).
static func npc_damage(level: int, strength: int, player_level: int, worn_af: float, worn_absorb: float, weapon := "one_hand",
		resist_mod := 1.0) -> int:
	var p := npc_damage_parts(level, strength, player_level, worn_af, worn_absorb, weapon)
	return maxi(1, int(minf(p[0] * resist_mod, p[1])))


## The same blow before resists and the cap: [base x skill / armour, the cap 3 x base] (the style damage works on these).
static func npc_damage_parts(level: int, strength: int, player_level: int, worn_af: float, worn_absorb: float, weapon := "one_hand") -> Array:
	var m := melee()
	var l := maxi(level, 1)
	var speed := float(m.get("npc_weapon_speed", {}).get(weapon, 3.0)) * 10.0
	var base := (1.0 + level / float(m.get("npc_damage_f1", 3.2)) + level * level / float(m.get("npc_damage_f2", 150))) * speed * 0.1
	var v: Array = m.get("npc_variance", [0.9, 1.1])
	var skill := l * float(m.get("npc_weapon_skill_per_level", 2.5)) * (1.0 + 0.01 * (strength + 30) / 2.0) * randf_range(v[0], v[1])
	# exactly the old server (owner: "just look at the code of the offlinedaoc"): worn AF + L x 0.4, floor 1. A player
	# wearing nothing takes capped hits (its starter kits always dressed players; the 1.65 start is weapon-only).
	var armor := maxf(1.0, (worn_af + player_level * float(m.get("player_extra_af_per_level", 0.4))) / maxf(0.01, 1.0 - worn_absorb))
	return [base * skill / armor, base * float(m.get("damage_cap_factor", 3.0))]


## One NPC's blow on another (a pet on a monster, a monster on a pet): the monster formula (base by level and weapon
## speed, weapon skill L x 2.5 x (1 + (STR + 30) / 200) x 0.9..1.1) against the target's armour (AF / (1 - absorb),
## AF divisor 200 monsters / 175 pets), x resist, capped at 3 x base.
static func npc_vs_npc_damage(level: int, strength: int, weapon: String, target_level: int, target_af_bonus: int,
		target_absorb: float, resist_mod: float, target_divisor: float) -> int:
	var p := npc_vs_npc_parts(level, strength, weapon, target_level, target_af_bonus, target_absorb, target_divisor)
	return maxi(1, int(minf(float(p[0]) * resist_mod, float(p[1]))))


## The same before resists and the cap: [base x skill / armour, 3 x base] (styles work on these).
static func npc_vs_npc_parts(level: int, strength: int, weapon: String, target_level: int, target_af_bonus: int,
		target_absorb: float, target_divisor: float) -> Array:
	var m := melee()
	var l := maxi(level, 1)
	var speed := float(m.get("npc_weapon_speed", {}).get(weapon, 3.0)) * 10.0
	var base := (1.0 + level / float(m.get("npc_damage_f1", 3.2)) + level * level / float(m.get("npc_damage_f2", 150))) * speed * 0.1
	var v: Array = m.get("npc_variance", [0.9, 1.1])
	var skill := l * float(m.get("npc_weapon_skill_per_level", 2.5)) * (1.0 + 0.01 * (strength + 30) / 2.0) * randf_range(v[0], v[1])
	var armor := npc_armor(target_level, target_af_bonus, target_absorb, target_divisor)
	return [base * skill / armor, base * float(m.get("damage_cap_factor", 3.0))]


# --- defence (GameLiving.TryEvade / TryParry / TryBlock, PlayerDefenseFormula, per mille) --------------------------

## Weapon skill without the variance roll (the attacker's side of defence penetration): L x class base / 200 x
## (1 + stat / 200) for a player, L x 2.5 x (1 + (STR + 30) / 200) for a monster.
static func player_weapon_skill(item: Dictionary, level: int, class_id: int, stats: Array) -> float:
	var ws_base := int(ClassDb.cls(class_id).get("weapon_skill", r().get("base_classes", {}).get(str(class_id), {}).get("weapon_skill", 400)))
	return level * ws_base / 200.0 * (1.0 + 0.01 * weapon_stat(item, stats) / 2.0)


static func npc_weapon_skill(level: int, strength: int) -> float:
	return maxi(level, 1) * float(melee().get("npc_weapon_skill_per_level", 2.5)) * (1.0 + 0.01 * (strength + 30) / 2.0)


## Defence penetration (AttackComponent.CalculateDefensePenetration): weapon skill x (1 + (the attacker's weapon spec,
## or a monster's level, minus the defender's level) x 1%) x 0.08%. Every defence chance is multiplied by 1 - this.
static func defense_penetration(weapon_skill: float, spec_or_level: int, target_level: int) -> float:
	return weapon_skill * (1.0 + (spec_or_level - target_level) * 0.01) * 0.08 / 100.0


## Parry with the Parry spec: (DEX x 2 - 100) / 4 + (spec - 1) x 5 + 50; block the same with the Shields spec.
static func parry_permille(dexterity: int, spec: int) -> int:
	return int((dexterity * 2 - 100) / 4.0) + (spec - 1) * 5 + 50


static func block_permille(dexterity: int, shield_spec: int) -> int:
	return int((dexterity * 2 - 100) / 4.0) + (shield_spec - 1) * 5 + 50


## Evade with the Evade ability (its level 1..7): (900 + QUI + DEX) x level x 5 / 100.
static func evade_permille(quickness: int, dexterity: int, evade_level: int) -> int:
	return int((900 + quickness + dexterity) * evade_level * 5 / 100.0) if evade_level > 0 else 0


# --- experience -------------------------------------------------------------------------------------------------

## Total experience needed to reach a level (level 1 = 0).
static func xp_for_level(level: int) -> int:
	var t: Array = r().get("xp_for_level", [0])
	return int(t[clampi(level - 1, 0, t.size() - 1)])


## A solo kill: the monster's level value, capped at 125% of a same-level kill; grey cons give nothing.
static func kill_xp(mob_level: int, player_level: int, grey: bool) -> int:
	if grey:
		return 0
	var t: Array = r().get("xp_for_living", [5])
	var xp := int(t[clampi(mob_level, 0, t.size() - 1)])
	var cap := int(t[clampi(player_level, 0, t.size() - 1)] * float(r().get("xp_cap_percent", 125)) / 100.0)
	return mini(xp, cap)
