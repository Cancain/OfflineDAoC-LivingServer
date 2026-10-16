class_name SpellRules
extends RefCounted
## Spell numbers, written for this engine from the old OfflineDAoC server's rules (SpellHandler / GameLiving /
## GamePlayer, read for the formulas - no code reused). Spells come from content/classes/spells.json.
##   cast time   CastTime x (1 - (DEX - 60) / 600), never under 40% of the listed time; quickcast = 2 s
##   power       Power (negative = % of the max power pool); quickcast doubles it
##   max power   max(5, level x 5 + (mana stat - 50))
##   power regen 2.5 + level x 0.2 a tick (same ticks as hit points), halved under 50% for list casters
##   to hit      87.5% + (spell level - target level) / 2, + (caster level - target level) against monsters
##   damage      Damage x (1 + mana stat x 0.005) x variance; variance from the spec against the target's level
##               (0.208 floor, up to 1.0) shifted by (caster - target level) x max(2, 10 - caster level x 0.16)%;
##               then the target's resist; cap 3 x Damage
const MIN_VARIANCE := 0.208
const STAT_INDEX := {"STR": 0, "CON": 1, "DEX": 2, "QUI": 3, "INT": 4, "PIE": 5, "EMP": 6, "CHA": 7, "CHR": 7}


## A spell's message line (message1..4), "" when the row has none (JSON null).
static func msg(spell: Dictionary, key: String) -> String:
	var v = spell.get(key)
	return v if v is String else ""


static func mana_stat(class_id: int) -> int:
	return STAT_INDEX.get(String(ClassDb.cls(class_id).get("mana_stat", "")), -1)


static func max_power(class_id: int, level: int, stats: Array) -> int:
	var i := mana_stat(class_id)
	if i < 0:
		return 0
	return maxi(5, level * 5 + (int(stats[i]) - 50))


static func cast_seconds(spell: Dictionary, dex: int, quick := false) -> float:
	var t := float(spell.get("casttime", 0.0))
	if t <= 0.0:
		return 0.0
	if quick:
		return 2.0
	return maxf(t * (1.0 - (dex - 60) / 600.0), t * 0.4)


static func power_cost(spell: Dictionary, max_pow: int, quick := false) -> int:
	var p := float(spell.get("power", 0))
	if p < 0.0:
		p = max_pow * -p * 0.01
	if quick and float(spell.get("casttime", 0.0)) > 0.0:
		p *= 2.0
	return int(p)


static func hit_chance(spell_level: int, caster_level: int, target_level: int) -> float:
	return 87.5 + (spell_level - target_level) / 2.0 + (caster_level - target_level)


## [min, max] damage variance (CalculateDamageVariance / CalculateLowerVarianceBound).
static func variance(spec_level: int, caster_level: int, target_level: int) -> Array:
	var tl := maxi(1, target_level)
	var steps := int((tl + 1 - spec_level) * 100.0 / tl) - 1
	var lo := clampf(1.0 - 0.008 * steps, MIN_VARIANCE, 1.0)
	var off := (caster_level - target_level) * maxf(2.0, 10.0 - caster_level * 0.16) * 0.01
	var hi := maxf(MIN_VARIANCE, 1.0 + off)
	return [clampf(lo + off, MIN_VARIANCE, hi), hi]


## An NPC's (a pet's) spell damage (CalculateDamageBase / Mob_Spells variance): Damage x (1 + INT x 0.005), life drains
## x (1 + LifeDrainReturn x 0.001), x 0.6..1.0 shifted by the level difference, x (1 - resist), area falloff, cap 3x.
static func npc_damage(spell: Dictionary, intel: int, caster_level: int, target_level: int, resist_pct := 0, falloff := 0.0) -> int:
	var base := float(spell.get("damage", 0.0))
	if base <= 0.0:
		return 0
	if String(spell.get("type", "")) == "Lifedrain":
		base *= 1.0 + float(spell.get("lifedrainreturn", 0)) * 0.001
	base *= 1.0 + intel * 0.005
	base *= 1.0 - clampf(falloff, 0.0, 1.0)
	var off := (caster_level - target_level) * maxf(2.0, 10.0 - caster_level * 0.16) * 0.01
	var hi := maxf(MIN_VARIANCE, 1.0 + off)
	var lo := clampf(0.6 + off, MIN_VARIANCE, hi)
	var d := base * randf_range(lo, hi)
	d -= d * resist_pct * 0.01
	return maxi(1, int(minf(d, float(spell.damage) * 3.0)))


## One spell's damage on a target (before any resist); 0 if the spell has no damage.
## falloff: an area spell's distance from its centre / its radius (SpellHandler.DistanceFallOff): damage x (1 - falloff).
static func damage(spell: Dictionary, stat: int, spec_level: int, caster_level: int, target_level: int, resist_pct := 0,
		falloff := 0.0) -> int:
	var base := float(spell.get("damage", 0.0))
	if base <= 0.0:
		return 0
	base *= 1.0 + stat * 0.005
	base *= 1.0 - clampf(falloff, 0.0, 1.0)
	var v := variance(spec_level, caster_level, target_level)
	var d := base * randf_range(v[0], v[1])
	d -= d * resist_pct * 0.01
	return maxi(1, int(minf(d, float(spell.damage) * 3.0)))
