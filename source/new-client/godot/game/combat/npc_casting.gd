class_name NpcCasting
extends RefCounted
## Monsters' spells (their NPC template's, pipeline/build_npcs.py -> content/spells/npc_spells.json), run the old
## server's way (StandardMobBrain.CheckSpells, GameNPC):
## - a fighting monster thinks every 1.5 s: below 75% health it heals itself (NPC_HEAL_THRESHOLD); then it picks one
##   castable harmful spell at random (in range, recast over, not already on the player for spells that last) - instant
##   ones on a shared 1-6 s cooldown (and not right at the start of a fight), cast-time ones stop its melee and it
##   stands still to cast them; the player's hits interrupt a cast;
## - its own buffs (armour, stats, damage add / shield, haste, bladeturn, offensive procs) are up from the start
##   (it casts them while idle);
## - to-hit 87.5 + 1.5 x (its level - the player's); damage = Damage x (1 + INT x 0.005) x 0.6..1.0 (Mob_Spells).
## The effects on the player are Casting.apply_to_player.

const THINK := 1.5
const HEAL_BELOW := 0.75
const SPELLS := "res://content/spells/npc_spells.json"
static var _spells := {}

var combat: Combat
var casting: Casting
var _state := {}                         # NpcState -> {cast, left, think, recast {}, instant_at, buffs_up}


static func spell(id: int) -> Dictionary:
	if _spells.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SPELLS)) if FileAccess.file_exists(SPELLS) else null
		_spells = parsed if parsed is Dictionary else {"": {}}
	return _spells.get(str(id), {})


## GameNPC.GetScaledSpell: a monster's proc / sub-spells (factor level / 50) and summoned pets' spells (level /
## floor(50 x |summon Damage| / 100)) scale their damage, value or duration by the factor; a copy.
const SCALE_DAMAGE := ["DamageOverTime", "DamageShield", "DamageAdd", "DirectDamage", "DirectDamageNoVariance", "Lifedrain",
		"DamageSpeedDecrease", "StyleBleeding"]
const SCALE_VALUE := ["EnduranceRegenBuff", "Heal", "StormEnduDrain", "PowerRegenBuff", "PowerHealthEnduranceRegenBuff",
		"CombatSpeedBuff", "HasteBuff", "CelerityBuff", "CombatSpeedDebuff", "StyleCombatSpeedDebuff", "CombatHeal",
		"HealthRegenBuff", "HealOverTime", "ConstitutionBuff", "DexterityBuff", "StrengthBuff", "ConstitutionDebuff",
		"DexterityDebuff", "StrengthDebuff", "ArmorFactorDebuff", "BaseArmorFactorBuff", "SpecArmorFactorBuff",
		"PaladinArmorFactorBuff", "ArmorAbsorptionBuff", "ArmorAbsorptionDebuff", "DexterityQuicknessBuff",
		"StrengthConstitutionBuff", "DexterityQuicknessDebuff", "StrengthConstitutionDebuff", "Taunt", "SpeedDecrease",
		"SavageCombatSpeedBuff"]
const SCALE_DURATION := ["Disease", "Stun", "UnrresistableNonImunityStun", "Mesmerize", "StyleStun", "StyleSpeedDecrease"]


static func scaled(sp: Dictionary, factor: float) -> Dictionary:
	if sp.is_empty() or is_equal_approx(factor, 1.0):
		return sp
	var out := sp.duplicate()
	var t := String(sp.get("type", ""))
	if t in SCALE_DAMAGE:
		out.damage = snappedf(float(sp.get("damage", 0)) * factor, 0.01)
	elif t in SCALE_VALUE:
		out.value = snappedf(float(sp.get("value", 0)) * factor, 0.01)
	elif t in SCALE_DURATION:
		out.duration = ceili(float(sp.get("duration", 0)) * factor)
	elif t == "DirectDamageWithDebuff":
		out.value = snappedf(float(sp.get("value", 0)) * factor, 0.01)
		out.damage = snappedf(float(sp.get("damage", 0)) * factor, 0.01)
		out.duration = ceili(float(sp.get("duration", 0)) * factor)
	return out


func _s(st: NpcState) -> Dictionary:
	if not _state.has(st):
		_state[st] = {"cast": {}, "left": 0.0, "think": randf() * THINK, "recast": {}, "instant_at": 0.0}
	return _state[st]


func busy(st: NpcState) -> bool:
	return _state.has(st) and not (_state[st].cast as Dictionary).is_empty()


## The monster's own buffs (it keeps them up while idle) - applied once per life.
func ensure_buffs(st: NpcState) -> void:
	if st.buffs_ready:
		return
	st.buffs_ready = true
	_state.erase(st)                                     # a new life: no cast, cooldowns or timers left over
	st.af_bonus = 0
	st.stat_buff = [0, 0, 0, 0]
	st.npc_buffs = []
	for sid in st.spawn.get("spells", []):
		var sp := spell(int(sid))
		if sp.is_empty() or String(sp.get("target", "")).to_lower() == "enemy" or String(sp.get("type", "")) in Combat.NPC_HEALS:
			continue
		var v := int(sp.get("value", 0))
		match String(sp.get("type", "")):
			"BaseArmorFactorBuff", "SpecArmorFactorBuff", "PaladinArmorFactorBuff": st.af_bonus = maxi(st.af_bonus, v)
			"StrengthBuff": st.stat_buff[0] = maxi(int(st.stat_buff[0]), v)
			"ConstitutionBuff": st.stat_buff[1] = maxi(int(st.stat_buff[1]), v)
			"DexterityBuff": st.stat_buff[2] = maxi(int(st.stat_buff[2]), v)
			"QuicknessBuff": st.stat_buff[3] = maxi(int(st.stat_buff[3]), v)
			"StrengthConstitutionBuff":
				st.stat_buff[0] = int(st.stat_buff[0]) + v
				st.stat_buff[1] = int(st.stat_buff[1]) + v
			"DexterityQuicknessBuff":
				st.stat_buff[2] = int(st.stat_buff[2]) + v
				st.stat_buff[3] = int(st.stat_buff[3]) + v
			"Bladeturn": st.bladeturn = true
			_: st.npc_buffs.append(sp)               # damage add / shield, haste, bladeturn, procs: Combat reads them


## Called from Combat._monsters for a fighting monster; true while it casts or wants to (it stands still then).
func think(st: NpcState, delta: float, dist: float) -> bool:
	var s := _s(st)
	var now := Time.get_ticks_msec() / 1000.0
	for k in (s.recast as Dictionary).keys():
		s.recast[k] = float(s.recast[k]) - delta
		if float(s.recast[k]) <= 0.0:
			s.recast.erase(k)
	if not (s.cast as Dictionary).is_empty():
		s.left = float(s.left) - delta
		if float(s.left) <= 0.0:
			var sp: Dictionary = s.cast
			s.cast = {}
			_land(st, sp)
		return true
	s.think = float(s.think) - delta
	if float(s.think) > 0.0:
		return false
	s.think = THINK
	var spells: Array = st.spawn.get("spells", [])
	if spells.is_empty():
		return false
	# heals first, below 75%
	if float(st.hp) / maxf(1.0, st.max_hp) < HEAL_BELOW:
		for sid in spells:
			var sp := spell(int(sid))
			if String(sp.get("type", "")) in Combat.NPC_HEALS and not (s.recast as Dictionary).has(int(sid)):
				return _begin(st, sp)
	# harmful: instants on the shared cooldown, then one cast-time spell at random
	var pick := {}
	var n := 0
	for sid in spells:
		var sp := spell(int(sid))
		if sp.is_empty() or String(sp.get("target", "")).to_lower() != "enemy" or (s.recast as Dictionary).has(int(sid)):
			continue
		if dist > float(sp.get("range", 1500)) * 0.025 * (1.0 - st.nearsight / 100.0):
			continue
		if float(sp.get("casttime", 0)) <= 0.0 and now < float(s.instant_at):
			continue
		if int(sp.get("duration", 0)) > 0 and String(sp.get("type", "")) not in ["DirectDamageWithDebuff", "DamageSpeedDecrease"] and st.target_pet == null and casting.player_has(sp):
			continue
		n += 1
		if randi() % n == 0:
			pick = sp
	if pick.is_empty():
		return false
	return _begin(st, pick)


func _begin(st: NpcState, sp: Dictionary) -> bool:
	var s := _s(st)
	var t := float(sp.get("casttime", 0))
	if t <= 0.0:
		if String(sp.get("target", "")).to_lower() == "enemy":
			s.instant_at = Time.get_ticks_msec() / 1000.0 + 1.0 + randf() * 2.5 + randf() * 2.5
		_land(st, sp)
		return false
	s.cast = sp
	s.left = maxf(t * (1.0 - (st.eff(2) - 60) / 600.0), t * 0.4)   # DEX speeds its casting like a player's
	PlayerData.message.emit("%s begins casting a spell!" % combat._cap(combat._the(st)), "spells")
	if st.view and (st.view as Npc).anim and (st.view as Npc).anim.has_animation("cast_start"):
		(st.view as Npc)._one_shot("cast_start")
	if st.view:                                           # its gather effects + sound (SpellFx)
		s.gather = SpellFx.begin(int(sp.get("clienteffect", 0)), st.view, (st.view as Npc).sounds)
	return true


## The player's hit breaks a cast (not an uninterruptible one).
func interrupt(st: NpcState) -> void:
	if busy(st) and not bool(_state[st].cast.get("uninterruptible", false)):
		SpellFx.fizzle(int(_state[st].cast.get("clienteffect", 0)), _state[st].get("gather", []),
				(st.view as Npc).sounds if st.view else null)
		_state[st].cast = {}
		PlayerData.message.emit("%s's spell is interrupted!" % combat._cap(combat._the(st)), "spells")


func _land(st: NpcState, sp: Dictionary) -> void:
	if not st.alive:
		return
	var s := _s(st)
	if int(sp.get("recastdelay", 0)) > 0:
		s.recast[int(sp.spellid)] = float(sp.recastdelay)
	if String(sp.get("type", "")) in Combat.NPC_HEALS:
		var amount := int(sp.get("value", 0))
		if amount < 0:
			amount = int(-amount / 100.0 * st.max_hp)
		st.hp = mini(st.max_hp, st.hp + amount)
		st.health = float(st.hp) / st.max_hp
		PlayerData.message.emit("%s heals itself!" % combat._cap(combat._the(st)), "spells")
		combat._update_target(st)
		return
	var intel0 := 30 + st.level - 1
	var foe: NpcState = st.target_pet if st.target_pet and st.target_pet.alive else null
	if foe and not (combat.pets and combat.pets.is_pet(foe)):
		# another monster (enemy faction): its damage spells hit it (the NPC formula, its resists); nothing else lands
		if st.pos.distance_to(foe.pos) <= float(sp.get("range", 1500)) * 0.025 + 2.0 \
				and String(sp.get("type", "")) in ["DirectDamage", "Bolt", "DirectDamageNoVariance", "DamageSpeedDecrease", "Lifedrain", "DirectDamageWithDebuff"] \
				and randf() * 100.0 < SpellRules.hit_chance(st.level, st.level, foe.level):
			var dmg := SpellRules.npc_damage(sp, intel0, st.level, foe.level, foe.resist(int(sp.get("damagetype", 0))), 0.0)
			if dmg > 0:
				combat.npc_hurts_npc(foe, st, dmg)
		return
	if foe:                                                # it fights a pet: the spell goes on the pet
		if st.pos.distance_to(foe.pos) <= float(sp.get("range", 1500)) * 0.025 + 2.0:
			casting._apply_hostile(sp.merged({"_npc_caster": {"level": st.level, "intel": intel0,
					"name": String(st.spawn.name), "foe": true, "who": st}}), foe)
		return
	if combat.player.dead:
		return
	if st.pos.distance_to(combat.player.global_position) > float(sp.get("range", 1500)) * 0.025 + 2.0:
		return
	var hit := 87.5 + 1.5 * (st.level - PlayerData.level)
	if String(sp.get("type", "")) in ["DamageSpeedDecrease", "DirectDamageWithDebuff", "Lifedrain"]:
		hit -= 2.5                                         # IsDualComponentSpell
	var who := combat._the(st)
	var ce := int(sp.get("clienteffect", 0))
	if st.view:                                           # it goes off: cast effects + sound on the monster
		SpellFx.fire(ce, _s(st).get("gather", []), st.view, (st.view as Npc).sounds)
	var resisted := randf() * 100.0 >= hit
	SpellFx.land(ce, combat.player, 1.8, combat.player.sounds, resisted)   # on you: its effect, or the resist
	if resisted:
		PlayerData.message.emit("You resist the effect!", "spells")
		# StartSpellNegatedInterruptTimer: a resisted spell that would have done damage, or wasn't instant
		if float(sp.get("damage", 0)) > 0.0 or float(sp.get("casttime", 0)) > 0.0:
			casting.on_attacked(who, st.level, 3.0)
		return
	casting.on_attacked(who, st.level, 3.0)               # a landed hostile spell: spell_interrupt_duration 3 s
	var intel := 30 + st.level - 1                       # mob_autoset_int (forced)
	casting.apply_to_player(sp, st, intel)
