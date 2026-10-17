class_name Casting
extends Node
## The player's spellcasting (SpellRules for the numbers; spells from content/classes/spells.json). The client's
## way: a spell on the quickbar starts a cast ("You begin casting a <spell> spell!"), the cast bar fills for the
## cast time, then the spell lands. Moving interrupts ("You move and interrupt your spellcast!") unless the spell
## casts on the move; a monster's blow interrupts ("<monster> is attacking you and your spell is interrupted!")
## unless quickcast is up; another spell while casting is queued as the follow-up. Power is spent when the spell
## lands; spells with a recast delay wait before the next use.
## Effects: damage (direct, bolt, lifedrain, damage + snare, damage over time), heals, snare / root, mesmerize,
## stun, and the player's buffs (stats, armour factor, damage add, damage shield, regeneration, speed). Pets,
## charm, area pulses and resurrection come later (AUTONOMOUS WORK LOG).

signal cast_progress(spell_name: String, frac: float)      # the cast bar (frac < 0: hide)

const RESIST := {1: "crush", 2: "slash", 3: "thrust", 10: "body", 11: "cold", 12: "energy", 13: "heat", 14: "matter", 15: "spirit"}

var player: Player
var npcs: NpcManager
var combat: Combat
var casting := {}                           # the spell being cast
var _cast_left := 0.0
var _cast_total := 0.0
var _cast_target: NpcState                  # monster target (or null for self / friendly spells)
var _queued := {}                           # the follow-up spell
var _cast_mode := ""                        # "area" / "pbaoe" / "self" / "" (a monster target)
var pulse := {}                             # the pulsing spell running (song / chant / pulsing area): {spell, next, mode, target}
var _recast := {}                           # spell id -> seconds left
var _start_pos := Vector3.ZERO
var quickcast := false                      # the Quickcast ability is up: next spell 2 s, can't be interrupted
var effects: Array = []                     # timed effects: {on: "player" | NpcState, spell, kind, until, ...}
var buffs := {}                             # player stat / armour bonuses from active buffs: key -> amount
var ground_target: Variant = null           # Vector3 set by the Ground Target key (area spells land there)


## Seamless zones: you crossed a border and the scene moved by -d.
func rebase(d: Vector3) -> void:
	_start_pos -= d


func setup(p: Player, n: NpcManager, c: Combat) -> void:
	player = p
	npcs = n
	combat = c
	PlayerData.use_skill.connect(_use)


func _use(e: Dictionary) -> void:
	if String(e.get("kind", "")) != "spell":
		return
	var spell := ClassDb.spell(int(e.get("id", 0)))
	if spell.is_empty():
		return
	if player.dead or PlayerData.hp <= 0:
		PlayerData.message.emit("You are dead and can't cast!", "spells")
		return
	if player.cc in ["stun", "mez"]:
		PlayerData.message.emit("You can't cast while %s!" % ("stunned" if player.cc == "stun" else "mesmerized"), "spells")
		return
	if player.sitting and int(spell.get("instrumentrequirement", 0)) == 0:
		PlayerData.message.emit("You can't cast while sitting!", "spells")
		return
	if not casting.is_empty():
		_queued = spell
		PlayerData.message.emit("You are already casting a spell! You prepare this spell as a follow up!", "spells")
		return
	_begin(spell)


func _begin(spell: Dictionary) -> void:
	var sid := int(spell.get("spellid", 0))
	# a pulsing spell already running: casting it again stops it (SpellHandler.CastSpell)
	if _pulsing(spell) and not pulse.is_empty() and int(pulse.spell.spellid) == sid:
		stop_pulse("You stop playing your song." if int(spell.get("instrumentrequirement", 0)) != 0 else "You cancel your effect.")
		return
	if int(spell.get("instrumentrequirement", 0)) != 0 and not _instrument_ok():
		PlayerData.message.emit("You are not wielding the right type of instrument!", "spells")
		return
	if String(spell.get("type", "")).begins_with("Summon") and combat.pets:
		var why := combat.pets.cannot_summon(spell)
		if why != "":
			PlayerData.message.emit(why, "spells")
			return
	if float(_recast.get(sid, 0.0)) > 0.0:
		PlayerData.message.emit("You must wait %d seconds to cast a spell!" % ceili(_recast[sid]), "spells")
		return
	# the interrupt timer (being attacked, or your own swing) blocks non-instant, interruptible spells
	var blocked := maxf(interrupt_until, self_interrupt_until) - _now()
	if blocked > 0.0 and not quickcast and not bool(spell.get("uninterruptible", false)) and float(spell.get("casttime", 0)) > 0.0:
		PlayerData.message.emit("You must wait %d seconds to cast a spell!" % int(blocked * 1000.0 / 1001.0), "spells")
		return
	var max_pow := SpellRules.max_power(PlayerData.class_id(), PlayerData.level, effective_stats())
	if _health_cost(spell):
		if PlayerData.hp < _savage_cost(spell):
			PlayerData.message.emit("You do not have enough health to cast that!", "spells")
			return
	elif PlayerData.power_pts < SpellRules.power_cost(spell, max_pow, quickcast):
		PlayerData.message.emit("You don't have enough power to cast that!", "spells")
		return
	if int(spell.get("concentration", 0)) > 0 and not _recasting_conc(spell):   # SpellHandler.CheckConcentrationCost
		if max_conc() - conc_used() < int(spell.concentration):
			PlayerData.message.emit("This spell requires %d concentration points to cast!" % int(spell.concentration), "spells")
			return
		if conc_effects().size() >= MAX_CONC_SPELLS:
			PlayerData.message.emit("You can only cast up to %d simultaneous concentration spells!" % MAX_CONC_SPELLS, "spells")
			return
	var target: Variant = _target_for(spell)
	if target is String and target == "fail":
		return
	_cast_target = target if target is NpcState else null
	_cast_mode = target if target is String else ""
	if combat.abilities:
		combat.abilities.break_stealth()                    # SpellHandler: casting brings you out
	casting = spell
	_cast_total = SpellRules.cast_seconds(spell, int(effective_stats()[2]), quickcast)
	_cast_left = _cast_total
	_start_pos = player.global_position
	if _cast_total > 0.0:
		if int(spell.get("instrumentrequirement", 0)) != 0:
			PlayerData.message.emit("You begin playing %s!" % String(spell.name), "spells")
		else:
			PlayerData.message.emit("You begin casting a %s spell!" % String(spell.name), "spells")
		var ce := int(spell.get("clienteffect", 0))
		player.cast_start(SpellFx.effect(ce).get("anims", []))          # the spell's own casting style
		_gather = SpellFx.begin(ce, player, player.sounds)              # hand glows + the gather sound
	else:
		_land()


## Songs, chants and pulsing areas (Spell.IsPulsing with a frequency; a pulsing mez is cast once).
func _pulsing(spell: Dictionary) -> bool:
	return int(spell.get("pulse", 0)) != 0 and int(spell.get("frequency", 0)) > 0 and String(spell.get("type", "")) != "Mesmerize"


## Songs need an instrument in hand (SpellHandler.CheckInstrument: the active weapon is an instrument, object type 45).
func _instrument_ok() -> bool:
	var slot: int = {"standard": 10, "twohand": 12, "ranged": 13}.get(PlayerData.active_weapon, -1)
	return slot >= 0 and int(PlayerData.item_at(slot).get("object_type", 0)) == 45


func stop_pulse(msg := "") -> void:
	if pulse.is_empty():
		return
	var was: Dictionary = pulse.spell
	pulse = {}
	if String(was.get("type", "")) == "Charm" and combat.pets and combat.pets.pet 			and combat.pets.is_pet(combat.pets.pet) and String(combat.pets._b[combat.pets.pet].kind) == "Charm":
		combat.pets.release(combat.pets.pet)              # the charm song stops: control ends
	if msg != "":
		PlayerData.message.emit(msg, "spells")


## One pulse (EffectService.TickPulsingEffect): every Frequency the spell lands again for its pulse power ("You do not
## have enough power and your spell was canceled."); a song stops without its instrument; nothing while stunned /
## mesmerized (the timer keeps running).
func _pulse_tick(delta: float) -> void:
	if pulse.is_empty():
		return
	pulse.next = float(pulse.next) - delta
	if float(pulse.next) > 0.0:
		return
	var sp: Dictionary = pulse.spell
	pulse.next = float(sp.frequency) / 10.0
	if player.dead or PlayerData.hp <= 0:
		stop_pulse()
		return
	if player.cc in ["stun", "mez"]:
		return
	if int(sp.get("instrumentrequirement", 0)) != 0 and not _instrument_ok():
		stop_pulse("You stop playing your song.")
		return
	var cost := int(sp.get("pulsepower", 0))
	if cost > 0:
		if PlayerData.power_pts < cost:
			stop_pulse("You do not have enough power and your spell was canceled.")
			return
		PlayerData.set_power(PlayerData.power_pts - cost)
	_apply_spell(sp, String(pulse.mode), pulse.target)


## Who a spell goes on: an enemy spell needs a live monster target in range and in view; self / realm / group
## spells land on the player (no friendly targets yet). Returns an NpcState, "self", or "fail".
func _target_for(spell: Dictionary) -> Variant:
	var t := String(spell.get("target", "Enemy"))
	if t in ["Self", "Realm", "Group"]:
		return "self"
	if t == "Pet":                                         # SpellHandler.CheckBeginCast, eSpellTarget.PET
		if combat.pets == null or combat.pets.pet == null:
			PlayerData.message.emit("You must cast this spell on a creature you are controlling.", "spells")
			return "fail"
		return "pet"
	if t != "Enemy" and t != "Area":
		PlayerData.message.emit("Invalid target.", "spells")
		return "fail"
	if t == "Area":                                        # SpellHandler.CheckBeginCast, eSpellTarget.AREA
		if ground_target == null or (ground_target as Vector3).distance_to(player.global_position) > float(spell.get("range", 1500)) * 0.025:
			PlayerData.message.emit("Your area target is out of range. Select a closer target.", "spells")
			return "fail"
		return "area"
	if int(spell.get("range", 0)) <= 0:                     # point blank: around the caster, no target needed
		return "pbaoe"
	var n: Npc = npcs.target
	if n == null or not is_instance_valid(n) or not n.state.alive:
		PlayerData.message.emit("You must select a target for this spell!", "spells")
		return "fail"
	if n.is_friendly() or int(n.spawn.realm) != 0:
		PlayerData.message.emit("You can't attack that!", "spells")
		return "fail"
	var range_m := float(spell.get("range", 1500)) * 0.025 * nearsight_mult()
	if n.global_position.distance_to(player.global_position) > range_m:
		PlayerData.message.emit("That target is too far away!", "spells")
		return "fail"
	return n.state


func _physics_process(delta: float) -> void:
	for k in _recast.keys():
		_recast[k] = float(_recast[k]) - delta
		if float(_recast[k]) <= 0.0:
			_recast.erase(k)
	_effects_tick(delta)
	_pulse_tick(delta)
	if casting.is_empty():
		return
	# songs (an instrument) and move-cast spells go on while moving (SpellHandler.CasterMoves)
	if not bool(casting.get("movecast", false)) and int(casting.get("instrumentrequirement", 0)) == 0 \
			and player.global_position.distance_to(_start_pos) > 0.15 and not quickcast:
		PlayerData.message.emit("You move and interrupt your spellcast!", "spells")
		interrupt()
		return
	_cast_left -= delta
	cast_progress.emit(String(casting.name), 1.0 - _cast_left / maxf(_cast_total, 0.01))
	if _cast_left <= 0.0:
		_land()


## A monster's blow while casting (Combat calls this): the spell is interrupted unless quickcast is up.
## The Ground Target key: the ground under the mouse becomes the ground target (PlayerGroundTargetHandler).
func set_ground_target(camera: Camera3D, screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var to := from + camera.project_ray_normal(screen_pos) * 250.0
	var q := PhysicsRayQueryParameters3D.create(from, to, ZoneLoader.LAYER_FLOOR | ZoneLoader.LAYER_WALL)
	var hit := player.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		PlayerData.message.emit("Your ground target is not visible!", "system")
		return
	ground_target = hit.position


## Being attacked (GameLiving.StartInterruptTimer + SpellHandler.CasterIsAttacked, the old server's rules):
##   - a chance of 100% + 3% per level the attacker is above you (less from lower-level attackers);
##   - the interrupt timer runs `duration` s (a melee blow: the attacker's swing time; a spell: 3 s,
##     spell_interrupt_duration) - while it runs no spell can be started ("You must wait N seconds to cast a spell!");
##   - a spell being cast is interrupted only in its first half ("<The attacker> attacks you and your spell is
##     interrupted!"); quickcast and uninterruptible spells never are.
var interrupt_until := 0.0                  # (engine seconds) attacked: no new cast before this
var self_interrupt_until := 0.0             # your own melee swing: 3 s (SelfInterruptDurationOnMeleeAttack)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func on_attacked(by: String, attacker_level := -1, duration := 3.0) -> void:
	var lvl := PlayerData.level if attacker_level < 0 else attacker_level
	if randf() * 100.0 >= 100.0 + (lvl - PlayerData.level) * 3.0:
		return
	var until := _now() + duration
	if interrupt_until >= until:
		return
	var was := interrupt_until > _now()
	interrupt_until = until
	if was or casting.is_empty() or quickcast or bool(casting.get("uninterruptible", false)):
		return
	if _cast_total > 0.0 and (_cast_total - _cast_left) >= _cast_total * 0.5:
		return                                            # past half way: the spell goes off
	PlayerData.message.emit("%s attacks you and your spell is interrupted!" % (by.left(1).to_upper() + by.substr(1)), "spells")
	interrupt()


func on_own_swing() -> void:
	self_interrupt_until = _now() + 3.0


var _gather: Array = []                     # the gather effects on the caster (SpellFx), dropped at fire / fizzle


func interrupt() -> void:
	if not casting.is_empty():
		SpellFx.fizzle(int(casting.get("clienteffect", 0)), _gather, player.sounds)
	casting = {}
	_queued = {}
	cast_progress.emit("", -1.0)
	player.cast_end()


func _land() -> void:
	var spell := casting
	casting = {}
	cast_progress.emit("", -1.0)
	player.cast_end(true)
	var max_pow := SpellRules.max_power(PlayerData.class_id(), PlayerData.level, effective_stats())
	if _health_cost(spell):
		PlayerData.set_hp(PlayerData.hp - _savage_cost(spell))
	else:
		PlayerData.set_power(PlayerData.power_pts - SpellRules.power_cost(spell, max_pow, quickcast))
	# SpellHandler.CastingCompleted: every finished cast also costs 5 endurance (CalculateEnduranceCost; no check
	# beforehand - an empty endurance bar doesn't stop casting)
	combat._spend_endurance(5)
	quickcast = false
	if float(spell.get("recastdelay", 0)) > 0.0:
		_recast[int(spell.spellid)] = float(spell.recastdelay)
	if _pulsing(spell):                                    # one pulsing spell at a time (CancelIncompatiblePulseEffects)
		pulse = {"spell": spell, "next": float(spell.frequency) / 10.0, "mode": _cast_mode, "target": _cast_target}
	# it goes off: the cast effects + sound; a bolt (BoltSpellHandler) lands when its projectile arrives, the rest now
	var view: Node3D = _cast_target.view if _cast_target and _cast_target.view else null
	if String(spell.get("type", "")) == "Bolt" and view:
		var mode := _cast_mode
		var tgt: Variant = _cast_target
		SpellFx.fire(int(spell.get("clienteffect", 0)), _gather, player, player.sounds, view,
				func(): _apply_spell(spell, mode, tgt))
	else:
		SpellFx.fire(int(spell.get("clienteffect", 0)), _gather, player, player.sounds, view)
		_apply_spell(spell, _cast_mode, _cast_target)
	if not _queued.is_empty():
		var next := _queued
		_queued = {}
		_begin(next)


## A landed spell (or a pulse of one) on its targets.
func _apply_spell(spell: Dictionary, mode: String, target: Variant) -> void:
	var t := String(spell.get("target", "Enemy"))
	var keep_mode := _cast_mode
	var keep_target := _cast_target
	_cast_mode = mode
	_cast_target = target if target is NpcState else null
	if String(spell.get("type", "")) == "PetSpell" and combat.pets:
		combat.pets.necro_cast(spell, _cast_target)
	elif String(spell.get("type", "")) == "Charm" and combat.pets:
		if _cast_target:
			combat.pets.charm(spell, _cast_target, _spec_level_for(spell))
	elif t == "Pet" and combat.pets:
		combat.pets.pet_spell(spell)
	elif (String(spell.get("type", "")).begins_with("Summon") or String(spell.get("type", "")) == "Bomber") and combat.pets:
		combat.pets.summon(spell, _cast_target)
	elif t in ["Self", "Realm", "Group"]:
		_friendly_targets(spell, t)
	elif int(spell.get("radius", 0)) > 0 or mode in ["area", "pbaoe"]:
		for hit in _area_targets(spell):
			_apply_hostile(spell, hit[0], hit[1])
	elif _cast_target and _cast_target.alive:
		_apply_hostile(spell, _cast_target)
	_cast_mode = keep_mode
	_cast_target = keep_target


# --- hostile spells --------------------------------------------------------------------------------------------------

## An area spell's monsters (SpellHandler.SelectTargets) with each one's distance falloff (CalculateDistanceFallOff):
## ground-targeted (Area) around the ground target / radius; point blank (range 0) around the caster / radius; a
## targeted one around its target / radius (the target itself 0). Only hostile monsters (aggressive realm-0 ones).
func _area_targets(spell: Dictionary) -> Array:
	var radius := maxf(0.01, float(spell.get("radius", 0)) * 0.025)
	var centre: Vector3
	if _cast_mode == "area":
		centre = ground_target
	elif _cast_mode == "pet" and combat.pets and combat.pets.pet:
		centre = combat.pets.pet.pos
	elif _cast_mode == "pbaoe":
		centre = player.global_position
	elif _cast_target and _cast_target.alive:
		centre = _cast_target.pos
	else:
		return []
	var out := []
	for s in npcs.states:
		var st: NpcState = s
		if not st.alive or int(st.spawn.realm) != 0 or (st.view and (st.view as Npc).is_friendly()):
			continue
		var d := st.pos.distance_to(centre)
		if d <= radius:
			out.append([st, d / radius])
	return out


func _apply_hostile(spell: Dictionary, st: NpcState, falloff := 0.0) -> void:
	var who := combat._the(st)
	var npc: Dictionary = spell.get("_npc_caster", {})
	var line_spec := _spec_level_for(spell)
	var spell_level := _spell_level(spell)
	# an NPC caster's spell level is its own level (SpellHandler.CalculateToHitChance)
	var hit := SpellRules.hit_chance(spell_level, PlayerData.level, st.level) if npc.is_empty() \
			else SpellRules.hit_chance(int(npc.level), int(npc.level), st.level) + float(npc.get("hit_bonus", 0.0))
	if String(spell.get("type", "")) in ["DamageSpeedDecrease", "DirectDamageWithDebuff", "Lifedrain"]:
		hit -= 2.5                                         # IsDualComponentSpell
	var fx_view: Node3D = st.view if st.view else null
	var fx_snd: CharacterSounds = (st.view as Npc).sounds if st.view and (st.view as Npc).sounds else player.sounds
	if randf() * 100.0 >= hit:
		PlayerData.message.emit("%s resists the effect!" % combat._cap(who), "spells")
		if fx_view:
			SpellFx.land(int(spell.get("clienteffect", 0)), fx_view, (st.view as Npc).height, fx_snd, true)
		combat._engage(st)
		return
	if fx_view:
		SpellFx.land(int(spell.get("clienteffect", 0)), fx_view, (st.view as Npc).height, fx_snd)
	var stat_i := SpellRules.mana_stat(PlayerData.class_id())
	var stat := int(effective_stats()[stat_i]) if stat_i >= 0 else 0
	var kind := String(spell.get("type", ""))
	var dmg := 0
	match kind:
		"DirectDamage", "Bolt", "DirectDamageWithDebuff", "NightshadeNuke", "DamageSpeedDecrease", "Lifedrain", "TurretPBAoE", "PowerDrainPet":
			if npc.is_empty():
				dmg = SpellRules.damage(spell, stat, line_spec, PlayerData.level, st.level, st.resist(int(spell.get("damagetype", 0))), falloff)
			else:
				dmg = SpellRules.npc_damage(spell, int(npc.intel), int(npc.level), st.level, st.resist(int(spell.get("damagetype", 0))), falloff)
	if dmg > 0 and bool(spell.get("_style_proc", false)):
		# a combat style's damage proc (SpellHandler.CalculateDamageBase, Combat_Styles_Effect): weapon skill x
		# Damage / 124, no variance
		var w: Dictionary = combat._weapon()
		dmg = maxi(1, int(CombatRules.player_weapon_skill(w, PlayerData.level, PlayerData.class_id(), effective_stats()) * float(spell.get("damage", 0)) / 124.0))
	if dmg > 0 and bool(npc.get("foe", false)):            # a monster's spell on your pet
		PlayerData.message.emit("%s hits your %s for %d damage." % [combat._cap(_the_name(String(npc.name))), String(st.spawn.name), dmg], "damage_taken")
		_hurt(st, dmg, null)
	elif dmg > 0 and not npc.is_empty():
		PlayerData.message.emit("Your %s hits %s for %d damage!" % [String(npc.name), who, dmg], "spells")
		_hurt(st, dmg, null)
	elif dmg > 0:
		PlayerData.message.emit("You hit %s for %d damage!" % [who, dmg], "spells")
		# list casters' spell crits (CriticalSpellHitChance 10): an extra 10-100% against a monster
		if String(ClassDb.cls(PlayerData.class_id()).get("class_type", "")) == "ListCaster" and randf() * 100.0 < 10.0:
			var crit := int(dmg * randf_range(0.1, 1.0))
			if crit > 0:
				PlayerData.message.emit("You critically hit for an additional %d damage! (10%%)" % crit, "spells")
				dmg += crit
		_hurt(st, dmg)
	if kind == "PowerDrainPet" and dmg > 0:                 # PowerDrain.DrainPower: damage x LifeDrainReturn % to you
		var gain := mini(int(dmg * float(spell.get("lifedrainreturn", 0)) / 100.0), PlayerData.max_power - PlayerData.power_pts)
		if gain > 0:
			PlayerData.set_power(PlayerData.power_pts + gain)
			PlayerData.message.emit("Your summon channels %d power to you!" % gain, "spells")
		else:
			PlayerData.message.emit("You cannot absorb any more power.", "spells")
	if kind == "Lifedrain" and dmg > 0 and npc.is_empty():
		var back := int(dmg * float(spell.get("lifedrainreturn", 0)) / 100.0)
		if back > 0:
			PlayerData.set_hp(mini(PlayerData.max_hp, PlayerData.hp + back))
			PlayerData.message.emit("You steal %d hit points." % back, "spells")
	if not st.alive:
		return
	var dur := float(spell.get("duration", 0))
	# AbstractCCSpellHandler / SpeedDecreaseSpellHandler: a CC-immune monster takes no stun, mez or snare
	if kind in ["DamageSpeedDecrease", "SpeedDecrease", "UnbreakableSpeedDecrease", "Mesmerize", "Stun"] 			and "CCImmunity" in (st.spawn.get("abilities", []) as Array):
		PlayerData.message.emit("Your target is immune to this effect!", "spells")
		combat._engage(st)
		return
	match kind:
		"DamageSpeedDecrease", "SpeedDecrease":
			_add_effect(st, spell, "snare", dur, {"value": float(spell.get("value", 0))})
		"Mesmerize":
			dur = _cc_duration(st, "mez", dur)
			if dur <= 0.0:
				return
			_add_effect(st, spell, "mez", dur, {})
		"Stun":
			dur = _cc_duration(st, "stun", dur)
			if dur <= 0.0:
				return
			_add_effect(st, spell, "stun", dur, {})
		"DamageOverTime":
			_add_effect(st, spell, "dot", dur, {"every": float(spell.get("frequency", 40)) / 10.0, "next": float(spell.get("frequency", 40)) / 10.0,
					"stat": stat, "spec": line_spec, "falloff": falloff, "npc": npc})
		"Nearsight":                                       # its spells' range shortened by Value % (NearsightSpellHandler)
			_add_effect(st, spell, "nearsight", dur, {"value": float(spell.get("value", 0))})
		"Amnesia":                                         # AmnesiaSpellHandler: its spell is lost (a lone player stays its target)
			if combat.npc_casting:
				combat.npc_casting.interrupt(st)
		"Taunt":                                           # TauntSpellHandler: threat max(1, Value x caster level x 0.1)
			var lvl := PlayerData.level if npc.is_empty() else int(npc.level)
			combat.add_aggro(st, "player" if npc.is_empty() else npc.get("who"), maxi(1, int(float(spell.get("value", 0)) * lvl * 0.1)))
		"Confusion":
			_add_effect(st, spell, "confusion", dur, {})   # target switching: with no other target, none
		_ when DEBUFFS.has(kind) or kind.ends_with("ResistDebuff") or kind in ["Disease", "UnbreakableSpeedDecrease"]:
			# SingleStatDebuff / DualStatDebuff / ResistDebuff / DiseaseSpellHandler: the value scaled like a buff by the
			# caster's spec; the duration shortened by the monster's resist to the spell's damage type (1 s .. 4 x)
			var d2 := dur * (1.0 - st.resist(int(spell.get("damagetype", 0))) * 0.01)
			d2 = clampf(d2, 1.0, dur * 4.0)
			var v := absf(float(spell.get("value", 0))) * buff_effectiveness(spell)
			if kind == "UnbreakableSpeedDecrease":
				_add_effect(st, spell, "snare", d2, {"value": float(spell.get("value", 0))})
			elif kind == "Disease":
				_add_effect(st, spell, "disease", d2, {})
			else:
				_add_effect(st, spell, "debuff", d2, {"type": kind, "value": v})
	if SpellRules.msg(spell, "message2") != "" and kind not in ["DirectDamage", "Bolt"]:
		PlayerData.message.emit(SpellRules.msg(spell, "message2").format([combat._cap(who)]), "spells")
	combat._engage(st)


## Monsters' crowd-control immunity (NpcStunImmunityEffect / NpcMezImmunityEffect): the first stun (mez) starts a
## 60 s window; each later one in it lasts duration / (2 x count), and under 1 s it doesn't take ("Your target is
## immune to this effect!"). Returns the duration to use, 0 when immune.
var _cc_immunity := {}                                    # [NpcState, kind] -> {until, count}


func _cc_duration(st: NpcState, kind: String, dur: float) -> float:
	var key := [st, kind]
	var now := Time.get_ticks_msec() / 1000.0
	var im: Dictionary = _cc_immunity.get(key, {})
	if im.is_empty() or now >= float(im.until):
		_cc_immunity[key] = {"until": now + 60.0, "count": 1}
		return dur
	var d := dur / (2.0 * int(im.count))
	if d < 1.0:
		PlayerData.message.emit("Your target is immune to this effect!", "spells")
		return 0.0
	im.count = int(im.count) + 1
	return d


## A style proc (StyleProcessor -> the proc spell's handler). The Style* spells can't be resisted; the others (damage,
## life drain, damage over time, debuffs) roll like any spell. Self buffs from a style land on the player.
func apply_proc(spell: Dictionary, st: NpcState) -> void:
	if spell.is_empty() or not st.alive:
		return
	var kind := String(spell.get("type", ""))
	var dur := float(spell.get("duration", 0))
	var who := combat._cap(combat._the(st))
	var msg2 := SpellRules.msg(spell, "message2").format([who])
	if kind in ["StyleStun", "StyleSpeedDecrease"] and "CCImmunity" in (st.spawn.get("abilities", []) as Array):
		PlayerData.message.emit("Your target is immune to this effect!", "spells")
		return
	match kind:
		"StyleStun":
			dur = _cc_duration(st, "stun", dur)
			if dur > 0.0:
				_add_effect(st, spell, "stun", dur, {})
				if msg2 != "":
					PlayerData.message.emit(msg2, "spells")
		"StyleSpeedDecrease":
			_add_effect(st, spell, "snare", dur, {"value": float(spell.get("value", 0))})
			if msg2 != "":
				PlayerData.message.emit(msg2, "spells")
		"StyleCombatSpeedDebuff":
			_add_effect(st, spell, "slow", dur, {"value": float(spell.get("value", 0))})
			if msg2 != "":
				PlayerData.message.emit(msg2, "spells")
		"StyleBleeding":                                  # BleedECSEffect: Damage on the first tick, 1 less each tick
			var every := float(spell.get("frequency", 40)) / 10.0
			_add_effect(st, spell, "bleed", dur, {"every": every, "next": every, "tick": int(spell.get("damage", 1))})
			if msg2 != "":
				PlayerData.message.emit(msg2, "spells")
		"StyleTaunt":                                     # StyleTaunt: floor(the blow's damage x Value x 0.1); negative detaunts
			combat.add_aggro(st, "player", int(floor(combat.last_damage * float(spell.get("value", 0)) * 0.1)))
		"StrengthDebuff":
			_add_effect(st, spell, "str_debuff", dur, {"value": int(spell.get("value", 0))})
			if msg2 != "":
				PlayerData.message.emit(msg2, "spells")
		"DirectDamage", "Lifedrain", "DamageOverTime":
			_apply_hostile(spell.merged({"_style_proc": true}), st)
		"DamageAdd", "DamageShield", "SavageStyleParryBuff", "SavageStyleEvadeBuff":
			_add_effect("player", spell, "buff", dur, {"type": kind})
			if SpellRules.msg(spell, "message1") != "":
				PlayerData.message.emit(SpellRules.msg(spell, "message1"), "spells")
		_:
			pass                                          # resist debuffs, multi-target, range, Nature's Shield: not yet


# --- monster spells on the player (NpcCasting) --------------------------------------------------------------------

var _player_immune := {}                                  # "stun" / "mez" -> seconds of immunity left (60 s, players)


## A monster's spell lands on the player: damage (direct, bolt, life drain, damage + snare, damage over time), snares /
## roots, stun / mez (60 s immunity after one wears off), disease (no health regeneration), stat / melee damage / attack
## speed debuffs. Damage = Damage x (1 + INT x 0.005) x 0.6..1.0 (Mob_Spells variance). "X hits you for N damage!".
func apply_to_player(sp: Dictionary, st: NpcState, intel: int) -> void:
	var who := combat._cap(combat._the(st))
	if combat.abilities:
		combat.abilities.break_stealth()
	var kind := String(sp.get("type", ""))
	var dur := float(sp.get("duration", 0))
	var msg1 := SpellRules.msg(sp, "message1")
	var dmg := 0
	match kind:
		"DirectDamage", "Bolt", "DirectDamageNoVariance", "DamageSpeedDecrease", "Lifedrain", "DirectDamageWithDebuff":
			var v := 1.0 if kind == "DirectDamageNoVariance" else randf_range(0.6, 1.0)
			var base := float(sp.get("damage", 0))
			if kind == "Lifedrain":
				base *= 1.0 + float(sp.get("lifedrainreturn", 0)) * 0.001     # CalculateDamageBase: life drains
			var res := PlayerData.resist(int(sp.get("damagetype", 0)))
			dmg = maxi(0, int(minf(base * (1.0 + intel * 0.005) * v * (1.0 - res * 0.01), float(sp.get("damage", 0)) * 3.0)))
	if dmg > 0:
		PlayerData.message.emit("%s hits you for %d damage!" % [who, dmg], "damage_taken")
		PlayerData.set_hp(PlayerData.hp - dmg)
		break_player_mez()
		player.flinch()                                    # the same combat animation as a blow: flinch + pain vocal
		if player.sounds and PlayerData.hp > 0:
			player.sounds.event("pain_light" if dmg < PlayerData.max_hp * 0.1 else "pain_medium")
		if kind == "Lifedrain" and st.alive:
			st.hp = mini(st.max_hp, st.hp + int(dmg * float(sp.get("lifedrainreturn", 0)) / 100.0))
			st.health = float(st.hp) / st.max_hp
	var immune := kind in ["Stun", "Mesmerize"] and float(_player_immune.get("stun" if kind == "Stun" else "mez", 0.0)) > 0.0
	if msg1 != "" and not immune and kind not in ["DirectDamage", "Bolt", "DirectDamageNoVariance"]:
		PlayerData.message.emit(msg1, "damage_taken")
	match kind:
		"DamageSpeedDecrease", "SpeedDecrease":
			var value := float(sp.get("value", 0))
			_add_effect("player", sp, "p_root" if value >= 99.0 else "p_snare", dur, {"type": kind, "value": value, "hostile": true})
		"Stun", "Mesmerize":
			var cc := "stun" if kind == "Stun" else "mez"
			if cc == "mez":
				dur *= 1.0 - minf(float(PlayerData.buffs.get("mez_duration", 0.0)), 100.0) / 100.0
			if float(_player_immune.get(cc, 0.0)) <= 0.0 and dur > 0.0:
				_add_effect("player", sp, "p_" + cc, dur, {"type": kind, "hostile": true})
				if not casting.is_empty():
					interrupt()
		"DamageOverTime":
			_add_effect("player", sp, "p_dot", dur, {"type": kind, "hostile": true, "every": float(sp.get("frequency", 40)) / 10.0,
					"next": float(sp.get("frequency", 40)) / 10.0, "from": who,
					"tick": maxi(1, int(float(sp.get("damage", 0)) * (1.0 + intel * 0.005) * (1.0 - PlayerData.resist(int(sp.get("damagetype", 0))) * 0.01)))})
		"Disease":
			_add_effect("player", sp, "p_disease", dur, {"type": kind, "hostile": true})
		"Nearsight":
			_add_effect("player", sp, "p_nearsight", dur, {"type": kind, "hostile": true, "value": float(sp.get("value", 0))})
		"Amnesia":                                         # your queued styles and your spell are lost
			combat.next_style = {}
			combat.backup_style = {}
			if not casting.is_empty() and int(casting.get("instrumentrequirement", 0)) == 0:
				interrupt()
		"StrengthDebuff", "DexterityDebuff", "ConstitutionDebuff", "StrengthConstitutionDebuff", "MeleeDamageDebuff", "CombatSpeedDebuff":
			_add_effect("player", sp, "p_debuff", dur, {"type": kind, "hostile": true, "value": float(sp.get("value", 0))})
		# a monster's style procs (StyleProcessor.ExecuteStyle -> the Combat_Styles_Effect handlers)
		"StyleCombatSpeedDebuff":
			_add_effect("player", sp, "p_debuff", dur, {"type": "CombatSpeedDebuff", "hostile": true, "value": float(sp.get("value", 0))})
		"StyleSpeedDecrease":
			_add_effect("player", sp, "p_snare", dur, {"type": kind, "value": float(sp.get("value", 0)), "hostile": true})
		"StyleStun":
			if float(_player_immune.get("stun", 0)) <= 0.0 and dur > 0.0:
				_add_effect("player", sp, "p_stun", dur, {"type": kind, "hostile": true})
				if not casting.is_empty():
					interrupt()
		"StyleBleeding":                                  # BleedECSEffect: Damage the first tick, 1 less each tick
			var every := float(sp.get("frequency", 40)) / 10.0
			_add_effect("player", sp, "p_dot", dur, {"type": kind, "hostile": true, "every": every, "next": every,
					"from": who, "tick": maxi(1, int(sp.get("damage", 1))), "bleed": true})
	if PlayerData.hp <= 0 and not combat.player.dead:
		combat._player_died()
		combat.killed_by.emit(String(st.spawn.name))


## Whether a lasting monster spell of this kind is already on the player (it isn't cast again then).
func player_has(sp: Dictionary) -> bool:
	for e in effects:
		if e.on is String and int(e.spell.get("spellid", -1)) == int(sp.get("spellid", -2)):
			return true
	return false


func break_player_mez() -> void:
	for e in effects:
		if e.on is String and e.kind == "p_mez":
			e.until = 0.0


## Nearsight on the player: its ranged attacks' and spells' range x (1 - value %).
func nearsight_mult() -> float:
	var m := 1.0
	for e in effects:
		if e.on is String and e.kind == "p_nearsight" and float(e.until) > 0.0:
			m = minf(m, 1.0 - float(e.get("value", 0)) / 100.0)
	return maxf(0.0, m)


## Melee damage debuffs on the player (MeleeDamageDebuff): x (1 - value%).
func player_melee_mult() -> float:
	var m := 1.0
	for e in effects:
		if e.on is String and e.kind == "p_debuff" and String(e.get("type", "")) == "MeleeDamageDebuff":
			m = minf(m, 1.0 - absf(float(e.get("value", 0))) / 100.0)
	return maxf(0.0, m)


## The player's crowd control from its effects: "stun" / "mez" / "root" / "" and the snare speed factor.
func _apply_player_cc() -> void:
	var cc := ""
	var snare := 1.0
	for e in effects:
		if not (e.on is String) or float(e.until) <= 0.0:
			continue
		match String(e.kind):
			"p_stun": cc = "stun"
			"p_mez": cc = "mez" if cc != "stun" else cc
			"p_root": cc = "root" if cc == "" else cc
			"p_snare": snare = minf(snare, maxf(0.0, 1.0 - float(e.get("value", 0)) / 100.0))
			"p_disease": snare = minf(snare, 0.85)
	combat.player.cc = cc
	combat.player.snare_mult = snare


## A buff of a type on the player (its value, 0 when none) - the savage style parry / evade buffs.
## Savage buffs and Kelgor's endurance heals cost health: max health x |Power| % (or Power when positive).
func _health_cost(spell: Dictionary) -> bool:
	var t := String(spell.get("type", ""))
	return t.begins_with("Savage") and t not in ["SavageStyleParryBuff", "SavageStyleEvadeBuff"]


func _savage_cost(spell: Dictionary) -> int:
	var p := float(spell.get("power", 0))
	return int(PlayerData.max_hp * absf(p) * 0.01) if p < 0.0 else int(p)


func player_buff(kind: String) -> float:
	var v := 0.0
	for e in effects:
		if e.on is String and e.kind == "buff" and String(e.get("type", "")) == kind:
			v = maxf(v, float(e.spell.get("value", 0)))
	return v


## who: whose threat the damage is ("player"; null when a pet's own threat is counted by Pets).
func _hurt(st: NpcState, dmg: int, who: Variant = "player") -> void:
	st.damage(dmg)
	if who != null:
		combat.add_aggro(st, who, dmg)
	_break_mez(st)
	if st.view:
		(st.view as Npc).flinch()
		# spell damage sends the same combat animation as a blow (SpellHandler.DamageTarget -> SendCombatAnimation,
		# result 0x14): the client plays the target's flinch and pain vocal (cc_creatures: light under 10% of its hits)
		if st.alive and (st.view as Npc).sounds:
			(st.view as Npc).sounds.event("pain_light" if dmg < st.max_hp * 0.1 else "pain_medium")
	if not st.alive and not (combat.pets and combat.pets.is_pet(st)):
		combat._killed(st)                                 # (a pet's death is Pets' business)
	combat._update_target(st)


## "the X" for a lower-case name, as the chat names monsters.
func _the_name(n: String) -> String:
	return ("the " + n) if n.length() > 0 and n[0] == n[0].to_lower() else n


func _break_mez(st: NpcState) -> void:
	for e in effects:
		if is_same(e.on, st) and e.kind == "mez":
			e.until = 0.0                                     # damage wakes a mesmerized monster


# --- friendly spells (on the player for now) --------------------------------------------------------------------------

const STAT_BUFFS := {"StrengthBuff": [0], "ConstitutionBuff": [1], "DexterityBuff": [2], "QuicknessBuff": [3],
		"AcuityBuff": [-1], "StrengthConstitutionBuff": [0, 1], "DexterityQuicknessBuff": [2, 3]}


## Who a friendly spell lands on (SpellHandler.SelectTargets, owner 2026-10-10: "buffs that target group, self or pet
## work without extra targeting"): Self - you, whatever is selected; Realm - the friendly creature you have selected
## (your pet, one of your commander's minions, a turret), else you; Group - you and your pets (the controlled pet and
## its minions) within the spell's range (point blank: its radius), with no group of players yet.
func _friendly_targets(spell: Dictionary, t: String) -> void:
	var mine: Array = combat.pets.all_pets() if combat.pets else []
	if t == "Realm":
		var n: Npc = npcs.target
		if n != null and is_instance_valid(n) and n.state.alive and mine.has(n.state):
			SpellFx.land(int(spell.get("clienteffect", 0)), n, 1.8, null)
			combat.pets._pet_friendly(n.state, spell)
			return
	_apply_friendly(spell)
	if t == "Group" and combat.pets and combat.pets.pet:
		var reach := float(spell.get("range", 0)) if float(spell.get("range", 0)) > 0.0 else float(spell.get("radius", 0))
		reach = maxf(reach, 500.0) * 0.025
		for q in [combat.pets.pet] + combat.pets.minions:
			var st: NpcState = q
			if st.alive and st.pos.distance_to(player.global_position) <= reach:
				if st.view:
					SpellFx.land(int(spell.get("clienteffect", 0)), st.view, 1.8, null)
				combat.pets._pet_friendly(st, spell)


func _apply_friendly(spell: Dictionary) -> void:
	SpellFx.land(int(spell.get("clienteffect", 0)), player, 1.8, player.sounds)     # its effect on you
	var kind := String(spell.get("type", ""))
	var dur := float(spell.get("duration", 0))
	if dur <= 0.0 and int(spell.get("concentration", 0)) > 0:
		dur = 1e9                                             # a concentration buff lasts while it is kept up
	match kind:
		"SavageEnduranceHeal":                             # Kelgor's Gift: endurance for health
			PlayerData.end_pts = mini(PlayerData.MAX_END, PlayerData.end_pts + int(float(spell.get("value", 0))))
			PlayerData.endurance = float(PlayerData.end_pts) / PlayerData.MAX_END
			PlayerData.changed.emit()
		"SavageParryBuff", "SavageEvadeBuff", "SavageCombatSpeedBuff", "SavageDPSBuff", "SavageCrushResistanceBuff", \
				"SavageSlashResistanceBuff", "SavageThrustResistanceBuff":
			_add_effect("player", spell, "buff", dur, {"type": kind, "eff": 1.0, "savage": true})
			if SpellRules.msg(spell, "message1") != "":
				PlayerData.message.emit(SpellRules.msg(spell, "message1"), "spells")
		"HealOverTime":                                    # HoTSpellHandler: Value every Frequency for the duration
			_add_effect("player", spell, "hot", dur, {"every": float(spell.get("frequency", 30)) / 10.0, "next": float(spell.get("frequency", 30)) / 10.0})
			if SpellRules.msg(spell, "message1") != "":
				PlayerData.message.emit(SpellRules.msg(spell, "message1"), "spells")
		"CombatHeal":                                      # a chant that heals only in combat (CombatHealSpellHandler)
			if combat.in_combat():
				_heal_player(float(spell.get("value", 0)), spell)
		"Bladeturn":                                       # the next blow is absorbed (BladeturnECSEffect)
			_add_effect("player", spell, "bladeturn", dur if dur > 0.0 else 1e9, {"type": kind, "caster_level": PlayerData.level})
			if SpellRules.msg(spell, "message1") != "":
				PlayerData.message.emit(SpellRules.msg(spell, "message1"), "spells")
		"AblativeArmor":                                   # absorbs Damage % of melee hits until Value is used up
			_add_effect("player", spell, "ablative", dur, {"type": kind, "left": int(float(spell.get("value", 0))),
					"pct": clampi(int(spell.get("damage", 0)), 1, 100) if int(spell.get("damage", 0)) >= 1 else 25})
			if SpellRules.msg(spell, "message1") != "":
				PlayerData.message.emit(SpellRules.msg(spell, "message1"), "spells")
		"OffensiveProc", "DefensiveProc", "OffensiveProcPvE":
			_add_effect("player", spell, "proc", dur, {"type": kind})
			if SpellRules.msg(spell, "message1") != "":
				PlayerData.message.emit(SpellRules.msg(spell, "message1"), "spells")
		"CureMezz", "CurePoison", "CureDisease", "CureNearsightCustom", "CureAll":
			var gone: Array = {"CureMezz": ["p_mez"], "CurePoison": ["p_dot"], "CureDisease": ["p_disease"],
					"CureNearsightCustom": ["p_nearsight"], "CureAll": ["p_mez", "p_dot", "p_disease", "p_nearsight"]}[kind]
			for e in effects:
				if e.on is String and String(e.kind) in gone:
					e.until = 0.0
		"Heal", "SpreadHeal", "OmniHeal":
			var v := SpellRules.variance(_spec_level_for(spell), PlayerData.level, PlayerData.level)
			var amount := float(spell.get("value", 0))
			if amount < 0.0:
				amount = -amount / 100.0 * PlayerData.max_hp
			else:
				amount *= randf_range(v[0], v[1])
			if bool(PlayerData.buffs.get("diseased", false)):
				PlayerData.message.emit("Your target is diseased!", "spells")
				amount *= 0.5
			var before := PlayerData.hp
			PlayerData.set_hp(mini(PlayerData.max_hp, PlayerData.hp + int(amount)))
			if PlayerData.hp >= PlayerData.max_hp and before >= PlayerData.max_hp:
				PlayerData.message.emit("You are fully healed.", "spells")
			else:
				PlayerData.message.emit("You heal yourself for %d hit points." % int(amount), "spells")
		_ when STAT_BUFFS.has(kind) or kind in ["BaseArmorFactorBuff", "SpecArmorFactorBuff", "DamageAdd", "DamageShield",
				"HealthRegenBuff", "PowerRegenBuff", "EnduranceRegenBuff", "SpeedEnhancement", "CombatSpeedBuff",
				"PaladinArmorFactorBuff", "MeleeDamageBuff", "FatigueConsumptionBuff", "MesmerizeDurationBuff",
				"ArmorAbsorptionBuff", "HeatColdMatterBuff", "BodySpiritEnergyBuff"] or kind.ends_with("ResistBuff"):
			_add_effect("player", spell, "buff", dur, {"type": kind, "eff": buff_effectiveness(spell)})
			if SpellRules.msg(spell, "message1") != "":
				PlayerData.message.emit(SpellRules.msg(spell, "message1"), "spells")
		_:
			PlayerData.message.emit("You cast a %s Spell!" % String(spell.name), "spells")


## A flat heal on the player (CombatHeal pulses): "You heal yourself for N hit points." / "You are fully healed.".
func _heal_player(amount: float, _spell: Dictionary) -> void:
	if bool(PlayerData.buffs.get("diseased", false)):
		amount *= 0.5
	if PlayerData.hp >= PlayerData.max_hp:
		PlayerData.message.emit("You are fully healed.", "spells")
		return
	PlayerData.set_hp(mini(PlayerData.max_hp, PlayerData.hp + int(amount)))
	PlayerData.message.emit("You heal yourself for %d hit points." % int(amount), "spells")


## The player's bladeturn takes a monster's blow (AttackComponent: consumed either way; a higher-level attacker gets
## through unless chance(caster level / attacker level)). Returns true when the blow is absorbed.
func player_bladeturn(attacker_level: int) -> bool:
	for e in effects:
		if e.on is String and e.kind == "bladeturn" and float(e.until) > 0.0:
			e.until = 0.0
			var cl := int(e.get("caster_level", PlayerData.level))
			if attacker_level > cl and randf() >= float(cl) / attacker_level:
				PlayerData.message.emit("The blow penetrated the magical barrier!", "spells")
				return false
			PlayerData.message.emit("The blow was absorbed by a magical barrier!", "spells")
			return true
	return false


## Ablative armour on a landed melee hit: Damage % of it up to what is left ("Your ablative absorbs N damage!").
func player_ablative(dmg: int) -> int:
	for e in effects:
		if e.on is String and e.kind == "ablative" and float(e.until) > 0.0 and dmg > 0:
			var a := mini(int(0.01 * int(e.pct) * dmg), int(e.left))
			if a <= 0:
				continue
			dmg -= a
			e.left = int(e.left) - a
			PlayerData.message.emit("Your ablative absorbs %d damage!" % a, "spells")
			if int(e.left) <= 0:
				e.until = 0.0
	return dmg


## The player's proc buffs (OffensiveProcSpellHandler / DefensiveProcSpellHandler): Frequency / 100 % per landed hit;
## an enemy spell goes on the monster, others on the player. The proc spell inherits the buff's level and line.
func player_procs(kind: String, st: NpcState) -> void:
	for e in effects.duplicate():
		if not (e.on is String and e.kind == "proc" and float(e.until) > 0.0):
			continue
		var t := String(e.get("type", ""))
		if (kind == "offensive") != (t != "DefensiveProc"):
			continue
		if randf() * 100.0 >= float(e.spell.get("frequency", 0)) / 100.0:
			continue
		var sp := ClassDb.spell(int(float(e.spell.get("value", 0))))
		if sp.is_empty():
			continue
		sp = sp.merged({"_as": int(e.spell.spellid)})
		if String(sp.get("target", "")) == "Enemy":
			if st and st.alive:
				_apply_hostile(sp, st)
		else:
			_apply_friendly(sp)


## The player's stats with items and active buffs (STR CON DEX QUI INT PIE EMP CHA) - PlayerData has the caps.
func effective_stats() -> Array:
	return PlayerData.effective_stats()


## A buff's or debuff's strength from the caster's spec (SingleStatBuff.CalculateBuffDebuffEffectiveness):
## 0.75 + (spec - 1) x 0.5 / spell level, between 0.75 and 1.25; others 1.
func buff_effectiveness(spell: Dictionary) -> float:
	return buff_eff(spell, PlayerData.class_id(), PlayerData.level, PlayerData.specs)


## The same for any caster (a gamebot's / companion's buffs - BotCaster).
static func buff_eff(spell: Dictionary, class_id: int, level: int, specs: Dictionary) -> float:
	var kind := String(spell.get("type", ""))
	# SingleStatBuff.CalculateBuffDebuffEffectiveness: stat / armour buffs, damage add / shield, and every debuff
	# (stat, armour, absorb, melee damage, attack speed and resist debuffs all derive from SingleStatDebuff)
	if not (STAT_BUFFS.has(kind) or kind in ["BaseArmorFactorBuff", "SpecArmorFactorBuff", "DamageAdd", "DamageShield"]
			or DEBUFFS.has(kind) or RESIST_DEBUFFS.has(kind)):
		return 1.0
	var lvl := ClassDb.spell_level(int(spell.get("_as", spell.spellid)))
	var line := line_of(spell, class_id, level, specs)
	if lvl <= 0 or line.is_empty():
		return 1.0
	var spec := int(specs.get(String(line.spec), 1))
	return clampf(0.75 + (spec - 1.0) * 0.5 / lvl, 0.75, 1.25)


## Sum the player's buffs into PlayerData.buffs (the old server's bonus categories): single-stat buffs in "base",
## dual-stat in "spec", acuity, base / spec armour factor, absorb %, haste %, regeneration per tick, speed %, and the
## damage adds / shields as [damage per second, effectiveness, damage type].
func _update_buffs() -> void:
	var b := sum_buffs(effects.filter(func(e): return e.on is String and e.kind == "buff"))
	_player_debuffs(b)
	PlayerData.buffs = b
	PlayerData.recalc_max()


## Buffs summed into a CharacterState's `buffs` (the old server's bonus categories) - the player's, and a gamebot's or
## companion's (BotCaster): one rule for both. Each entry: {type, spell, eff}.
static func sum_buffs(list: Array) -> Dictionary:
	var b := {"base": [0, 0, 0, 0, 0, 0, 0, 0], "spec": [0, 0, 0, 0, 0, 0, 0, 0], "acuity": 0, "af_base": 0, "af_spec": 0,
			"absorb": 0.0, "haste": 0.0, "regen_hp": 0, "regen_power": 0, "regen_end": 0, "speed": 0.0, "da": [], "ds": [],
			"debuff_base": [0, 0, 0, 0, 0, 0, 0, 0], "debuff_spec": [0, 0, 0, 0, 0, 0, 0, 0], "resist": {}, "resist_debuff": {}}
	for e in list:
		var kind := String(e.get("type", ""))
		var v := int(float(e.spell.get("value", 0)) * float(e.get("eff", 1.0)))
		match kind:
			"StrengthBuff": b.base[0] = maxi(b.base[0], v)
			"ConstitutionBuff": b.base[1] = maxi(b.base[1], v)
			"DexterityBuff": b.base[2] = maxi(b.base[2], v)
			"QuicknessBuff": b.base[3] = maxi(b.base[3], v)
			"StrengthConstitutionBuff":
				b.spec[0] = maxi(b.spec[0], v)
				b.spec[1] = maxi(b.spec[1], v)
			"DexterityQuicknessBuff":
				b.spec[2] = maxi(b.spec[2], v)
				b.spec[3] = maxi(b.spec[3], v)
			"AcuityBuff": b.acuity = maxi(b.acuity, v)
			"BaseArmorFactorBuff": b.af_base = maxi(b.af_base, v)
			"SpecArmorFactorBuff": b.af_spec = maxi(b.af_spec, v)
			"PaladinArmorFactorBuff": b["af_other"] = maxi(int(b.get("af_other", 0)), v)      # OtherBuff: uncapped
			"MeleeDamageBuff", "SavageDPSBuff": b["melee_damage"] = maxf(float(b.get("melee_damage", 0.0)), float(e.spell.get("value", 0)))
			"SavageCombatSpeedBuff": b.haste = maxf(b.haste, float(e.spell.get("value", 0)))
			"SavageCrushResistanceBuff": b.resist[1] = maxi(int(b.resist.get(1, 0)), v)
			"SavageSlashResistanceBuff": b.resist[2] = maxi(int(b.resist.get(2, 0)), v)
			"SavageThrustResistanceBuff": b.resist[3] = maxi(int(b.resist.get(3, 0)), v)
			"FatigueConsumptionBuff": b["fatigue"] = maxf(float(b.get("fatigue", 0.0)), float(e.spell.get("value", 0)))
			"MesmerizeDurationBuff": b["mez_duration"] = maxf(float(b.get("mez_duration", 0.0)), float(e.spell.get("value", 0)))
			"ArmorAbsorptionBuff": b.absorb = maxf(b.absorb, float(e.spell.get("value", 0)))
			"CombatSpeedBuff": b.haste = maxf(b.haste, float(e.spell.get("value", 0)))
			"HealthRegenBuff": b.regen_hp = maxi(b.regen_hp, int(e.spell.get("value", 0)))
			"PowerRegenBuff": b.regen_power = maxi(b.regen_power, int(e.spell.get("value", 0)))
			"EnduranceRegenBuff": b.regen_end = maxi(b.regen_end, int(e.spell.get("value", 0)))
			"SpeedEnhancement": b.speed = maxf(b.speed, float(e.spell.get("value", 0)))
			"BodyResistBuff", "ColdResistBuff", "EnergyResistBuff", "HeatResistBuff", "MatterResistBuff", "SpiritResistBuff", \
			"CrushResistBuff", "SlashResistBuff", "ThrustResistBuff", "HeatColdMatterBuff", "BodySpiritEnergyBuff":
				var dts: Array = {"BodyResistBuff": [10], "ColdResistBuff": [11], "EnergyResistBuff": [12], "HeatResistBuff": [13],
						"MatterResistBuff": [14], "SpiritResistBuff": [15], "CrushResistBuff": [1], "SlashResistBuff": [2],
						"ThrustResistBuff": [3], "HeatColdMatterBuff": [13, 11, 14], "BodySpiritEnergyBuff": [10, 15, 12]}[kind]
				for dt in dts:
					b.resist[dt] = maxi(int(b.resist.get(dt, 0)), v)
			"DamageAdd": b.da.append([float(e.spell.get("damage", 0)), float(e.get("eff", 1.0)), int(e.spell.get("damagetype", 0))])
			"DamageShield": b.ds.append([float(e.spell.get("damage", 0)), float(e.get("eff", 1.0)), int(e.spell.get("damagetype", 0))])
	return b


func _player_debuffs(b: Dictionary) -> void:
	for e in effects:                                      # monster debuffs on the player
		if not (e.on is String) or float(e.until) <= 0.0:
			continue
		var dv := absi(int(e.get("value", 0)))
		match String(e.get("type", "")):
			"StrengthDebuff": b.debuff_base[0] = maxi(b.debuff_base[0], dv)
			"DexterityDebuff": b.debuff_base[2] = maxi(b.debuff_base[2], dv)
			"ConstitutionDebuff": b.debuff_base[1] = maxi(b.debuff_base[1], dv)
			"StrengthConstitutionDebuff":
				b.debuff_base[0] = maxi(b.debuff_base[0], dv)
				b.debuff_base[1] = maxi(b.debuff_base[1], dv)
			"DexterityQuicknessDebuff":
				b.debuff_base[2] = maxi(b.debuff_base[2], dv)
				b.debuff_base[3] = maxi(b.debuff_base[3], dv)
			"CombatSpeedDebuff": b["slow"] = maxf(float(b.get("slow", 0.0)), float(dv))
		var rt := String(e.get("type", ""))
		if RESIST_DEBUFFS.has(rt):
			b.resist_debuff[RESIST_DEBUFFS[rt]] = maxi(int(b.resist_debuff.get(RESIST_DEBUFFS[rt], 0)), dv)
		if String(e.kind) == "p_disease":
			b["diseased"] = true


# --- timed effects ---------------------------------------------------------------------------------------------------

func _add_effect(on: Variant, spell: Dictionary, kind: String, seconds: float, extra: Dictionary) -> void:
	# the same spell group doesn't stack: a new cast replaces the old one on that target
	for e in effects:
		if is_same(e.on, on) and ((int(e.spell.get("spellgroup", 0)) == int(spell.get("spellgroup", -1)) and int(spell.get("spellgroup", 0)) != 0)
				or int(e.spell.get("spellid", -1)) == int(spell.get("spellid", -2))):
			e.until = 0.0
	var e := {"on": on, "spell": spell, "kind": kind, "until": seconds, "icon": int(spell.get("icon_base", 0)),
			"border": int(spell.get("icon_border", -1)), "conc": int(spell.get("concentration", 0))}
	e.merge(extra, true)
	effects.append(e)
	if on is NpcState:
		_apply_hindrance(on)
	else:
		_update_buffs()
	PlayerData.effects_changed.emit()


func _effects_tick(delta: float) -> void:
	var changed := false
	for i in range(effects.size() - 1, -1, -1):
		var e: Dictionary = effects[i]
		e.until = float(e.until) - delta
		if e.on is NpcState and not (e.on as NpcState).alive:
			e.until = 0.0
		if e.kind == "hot" and float(e.until) > 0.0:
			e.next = float(e.next) - delta
			if float(e.next) <= 0.0:
				e.next = float(e.every)
				if PlayerData.hp < PlayerData.max_hp:
					var h := int(float(e.spell.get("value", 0)))
					PlayerData.set_hp(mini(PlayerData.max_hp, PlayerData.hp + h))
					PlayerData.message.emit("You are healed by %s for %d hit points." % [PlayerData.display_name(), h], "spells")
				else:
					PlayerData.message.emit("You are full health.", "spells")
		if e.kind == "p_dot" and float(e.until) > 0.0:
			e.next = float(e.next) - delta
			if float(e.next) <= 0.0:
				e.next = float(e.every)
				PlayerData.message.emit("%s hits you for %d damage!" % [String(e.get("from", "Your enemy")), int(e.tick)], "damage_taken")
				PlayerData.set_hp(PlayerData.hp - int(e.tick))
				if bool(e.get("bleed", false)) and int(e.tick) > 1:
					e.tick = int(e.tick) - 1
				break_player_mez()
				if PlayerData.hp <= 0 and not combat.player.dead:
					combat._player_died()
		if e.kind == "bleed" and float(e.until) > 0.0:
			e.next = float(e.next) - delta
			if float(e.next) <= 0.0:
				e.next = float(e.every)
				var bst: NpcState = e.on
				PlayerData.message.emit("You hit %s for %d damage!" % [combat._the(bst), int(e.tick)], "spells")
				_hurt(bst, int(e.tick))
				if int(e.tick) > 1:
					e.tick = int(e.tick) - 1
		if e.kind == "dot" and float(e.until) > 0.0:
			e.next = float(e.next) - delta
			if float(e.next) <= 0.0:
				e.next = float(e.every)
				var st: NpcState = e.on
				var nc: Dictionary = e.get("npc", {})
				var res := st.resist(int(e.spell.get("damagetype", 0)))
				if nc.is_empty():
					var d := SpellRules.damage(e.spell, int(e.stat), int(e.spec), PlayerData.level, st.level, res, float(e.get("falloff", 0.0)))
					PlayerData.message.emit("You hit %s for %d damage!" % [combat._the(st), d], "spells")
					_hurt(st, d)
				else:                                              # a pet's DoT on a monster / a monster's on your pet
					var d := SpellRules.npc_damage(e.spell, int(nc.intel), int(nc.level), st.level, res, float(e.get("falloff", 0.0)))
					if bool(nc.get("foe", false)):
						PlayerData.message.emit("%s hits your %s for %d damage." % [combat._cap(_the_name(String(nc.name))), String(st.spawn.name), d], "damage_taken")
					else:
						PlayerData.message.emit("Your %s hits %s for %d damage!" % [String(nc.name), combat._the(st), d], "spells")
					_hurt(st, d, null)
		if float(e.until) <= 0.0:
			effects.remove_at(i)
			changed = true
			if e.on is NpcState:
				_apply_hindrance(e.on)
			elif bool(e.get("savage", false)) and PlayerData.hp > 1:
				PlayerData.set_hp(PlayerData.hp - mini(maxi(1, _savage_cost(e.spell)), PlayerData.hp - 1))
			if not (e.on is NpcState):
				if String(e.kind) in ["p_stun", "p_mez"]:
					_player_immune[String(e.kind).trim_prefix("p_")] = 60.0   # ImmunityEffect: 60 s for players
				if SpellRules.msg(e.spell, "message3") != "":
					PlayerData.message.emit(SpellRules.msg(e.spell, "message3"), "spells")
	for k in _player_immune.keys():
		_player_immune[k] = float(_player_immune[k]) - delta
	if changed:
		_update_buffs()
		PlayerData.effects_changed.emit()
	_apply_player_cc()


## A monster's movement / action limits from its effects: mesmerized and stunned can't act, rooted can't move,
## snared moves at (100 - value)%.
## Debuff spells on monsters: stat [indices] and category, or what they lower. Dual-stat debuffs are in the same Debuff
## category as single-stat ones (DualStatDebuff.BonusCategory1/2; the spec debuff category is Champion-only).
const DEBUFFS := {"StrengthDebuff": [[0], "base"], "ConstitutionDebuff": [[1], "base"], "DexterityDebuff": [[2], "base"],
		"QuicknessDebuff": [[3], "base"], "StrengthConstitutionDebuff": [[0, 1], "base"], "DexterityQuicknessDebuff": [[2, 3], "base"],
		"ArmorFactorDebuff": [[], "af"], "ArmorAbsorptionDebuff": [[], "absorb"], "CombatSpeedDebuff": [[], "slow"],
		"MeleeDamageDebuff": [[], "melee"]}
const RESIST_DEBUFFS := {"BodyResistDebuff": 10, "ColdResistDebuff": 11, "EnergyResistDebuff": 12, "HeatResistDebuff": 13,
		"MatterResistDebuff": 14, "SpiritResistDebuff": 15, "CrushResistDebuff": 1, "SlashResistDebuff": 2, "ThrustResistDebuff": 3}


func _apply_hindrance(st: NpcState) -> void:
	st.mezzed = false
	st.stunned = false
	st.speed_factor = 1.0
	st.swing_mult = 1.0
	st.debuff_base = [0, 0, 0, 0]
	st.debuff_spec = [0, 0, 0, 0]
	st.af_debuff = 0
	st.absorb_debuff = 0
	st.melee_debuff = 0
	st.resist_debuff = {}
	st.diseased = false
	st.bleeding = false
	st.nearsight = 0.0
	for e in effects:
		if not is_same(e.on, st) or float(e.until) <= 0.0:
			continue
		match String(e.kind):
			"mez": st.mezzed = true
			"stun": st.stunned = true
			"snare": st.speed_factor = minf(st.speed_factor, maxf(0.0, 1.0 - float(e.get("value", 0)) / 100.0))
			"slow": st.swing_mult = maxf(st.swing_mult, 1.0 + float(e.get("value", 0)) / 100.0)   # MeleeSpeed 100 + debuff
			"str_debuff": st.debuff_base[0] = maxi(int(st.debuff_base[0]), int(e.get("value", 0)))
			"nearsight": st.nearsight = maxf(st.nearsight, float(e.get("value", 0)))
			"disease":
				st.diseased = true
				st.speed_factor = minf(st.speed_factor, 0.85)
			"debuff":
				var t := String(e.get("type", ""))
				var v := int(e.get("value", 0))
				if RESIST_DEBUFFS.has(t):
					var dt: int = RESIST_DEBUFFS[t]
					st.resist_debuff[dt] = maxi(int(st.resist_debuff.get(dt, 0)), v)
				elif DEBUFFS.has(t):
					var what: String = DEBUFFS[t][1]
					for i in DEBUFFS[t][0]:
						if what == "base":
							st.debuff_base[i] = maxi(int(st.debuff_base[i]), v)
						else:
							st.debuff_spec[i] = maxi(int(st.debuff_spec[i]), v)
					match what:
						"af": st.af_debuff = maxi(st.af_debuff, v)
						"absorb": st.absorb_debuff = maxi(st.absorb_debuff, v)
						"slow": st.swing_mult = maxf(st.swing_mult, 1.0 + v / 100.0)
						"melee": st.melee_debuff = maxi(st.melee_debuff, v)
			"bleed": st.bleeding = true


## The player's effects for the effects bar: [{icon, border, name, seconds}].
func player_effects() -> Array:
	var out := []
	for e in effects:
		if e.on is String:
			out.append({"icon": e.icon, "border": e.border, "name": String(e.spell.get("name", "")), "seconds": float(e.until)})
	return out


# --- concentration (period: the pool grows with level and the casting stat - Warcry grab bag 2004; up to 20
# concentration spells at once - patch notes Feb 2002, "the previous limit was 16"; a concentration buff stays until
# its caster or target cancels it, dies, or crosses a major zone boundary - Warcry interface guide 2004). The pool:
# the old server's MaxConcentrationCalculator, (level x 4 x 2.2 + (casting stat - 50) x 2.8) / 2. ---------------------
const MAX_CONC_SPELLS := 20


func max_conc() -> int:
	var i := SpellRules.mana_stat(PlayerData.class_id())
	if i < 0:
		return 0
	var stat := int(effective_stats()[i])
	return maxi(0, (int(PlayerData.level * 4 * 2.2) + int((stat - 50) * 2.8)) / 2)


## Your concentration spells in effect, in the order cast.
func conc_effects() -> Array:
	return effects.filter(func(e): return int(e.get("conc", 0)) > 0 and float(e.until) > 0.0)


func conc_used() -> int:
	var n := 0
	for e in conc_effects():
		n += int(e.conc)
	return n


## A recast of a concentration spell already up replaces it - its points come back first.
func _recasting_conc(spell: Dictionary) -> bool:
	for e in conc_effects():
		if int(e.spell.get("spellid", -1)) == int(spell.get("spellid", -2)) or (int(spell.get("spellgroup", 0)) != 0
				and int(e.spell.get("spellgroup", 0)) == int(spell.get("spellgroup", 0))):
			return true
	return false


## The concentration window's shift + right-click: the buff ends, its points return.
func cancel_conc(index: int) -> void:
	var list := conc_effects()
	if index < 0 or index >= list.size():
		return
	var e: Dictionary = list[index]
	e.until = 0.0
	PlayerData.message.emit("You cancel your %s spell." % String(e.spell.get("name", "")), "spells")


## Death ends every effect on you (and the concentration spells you keep up).
func clear_on_death() -> void:
	for e in effects:
		if e.on is String or int(e.get("conc", 0)) > 0:
			e.until = 0.0


## The timed effects on your pet (the pet window's buff strip).
func pet_effects() -> Array:
	var out := []
	var pet = combat.pets.pet if combat and combat.pets else null
	if pet == null:
		return out
	for e in effects:
		if e.on is NpcState and e.on == pet and float(e.until) > 0.0:
			out.append({"icon": e.icon, "border": e.border, "name": String(e.spell.get("name", "")), "seconds": float(e.until)})
	return out


# --- spec / level of a spell ------------------------------------------------------------------------------------------

func _spell_line_of(spell: Dictionary) -> Dictionary:
	return line_of(spell, PlayerData.class_id(), PlayerData.level, PlayerData.specs)


static func line_of(spell: Dictionary, class_id: int, level: int, specs: Dictionary) -> Dictionary:
	var sid := int(spell.get("_as", spell.spellid))
	for line in ClassDb.spell_lines(class_id, level, specs):
		if (line.spells as Array).has(sid):
			return line
	return {}


func _spec_level_for(spell: Dictionary) -> int:
	var line := _spell_line_of(spell)
	if line.is_empty():
		return PlayerData.level
	return PlayerData.level if bool(line.baseline) else int(PlayerData.specs.get(String(line.spec), 1))


func _spell_level(spell: Dictionary) -> int:
	return ClassDb.spell_level(int(spell.get("_as", spell.spellid)))
