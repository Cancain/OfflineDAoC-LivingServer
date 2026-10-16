class_name Pets
extends Node
## Summoned pets, written for this engine from the old server's rules (SummonSpellHandler, GameSummonedPet,
## ControlledMobBrain, the class summon handlers - read for the numbers only):
## - a summon spell names its NPC template (Spell.LifeDrainReturn, pipeline/build_pets.py -> content/classes/pets.json);
##   level = Damage when positive, else the caster's level x -Damage %, no more than Value, at least 1 (SetPetLevel);
##   stats = 30 + (level - 1) each, times the template's % where it gives one; health 17 x (L + 1) + 0.535 x L^2 +
##   (CON - 25) x 3; armour (1 + L / 175) x L x 12.5; template spells scaled by level / floor(50 x |Damage| / 100)
##   (all but Animist turrets);
## - one controlled pet (Druid, Enchanter, Hunter, Spiritmaster, Necromancer, Bonedancer commander, Animist main
##   turret, ...): "You already have a charmed creature, release it first!"; a Bonedancer commander leads up to two
##   minions (their levels together at most 75); Theurgist elementals and Animist fire-and-forget turrets are extra,
##   uncontrolled and timed;
## - the pet window commands: aggressive (attacks what comes within 512 units), defensive (the default: fights what
##   attacks you or it, and your target on ATTACK), passive (no fighting), follow (2 m behind you, 30% faster than you
##   out of combat), stay, attack (your target), release;
## - monsters it hits take it on: its damage is its threat, and you get 30% on top (StandardMobBrain); the monster
##   fights whoever has the most;
## - it heals you and itself under 50% (pet_heal_threshold), keeps its buffs on you and itself, and casts its harmful
##   spells at its target; turrets don't move;
## - its kills give you the experience; it dies ("The X dies!") or goes with you when you die.
## - the Necromancer (ClassDisciple / NecromancerPet / PetSpellHandler): while the servant lives you are a shade - no
##   melee ("You cannot enter combat while in shade form!"), monsters on you turn to the servant, monsters don't notice
##   you; your PetSpell spells are instant for you and the servant casts their sub-spell (its own cast time, your spec
##   and INT for the numbers); the servant's stats follow necro_pet_* (greater necroservant its own), health 32.5 x L +
##   your item CON x 3; when it goes your health is cut to its last health share (at least 10%).

signal changed

const PETS := "res://content/classes/pets.json"
const CONTROLLED := ["SummonDruidPet", "SummonUnderhill", "SummonHunterPet", "SummonSpiritFighter", "SummonSimulacrum",
		"SummonNecroPet", "SummonCommander", "SummonAnimistPet"]
const STATIONARY := ["SummonAnimistPet", "SummonAnimistFnF"]
const NO_SCALE := ["SummonAnimistPet", "SummonAnimistFnF"]
const FOLLOW_DIST := 80 * 0.025               # MIN_OWNER_FOLLOW_DIST
const AGGRO_RANGE := 512 * 0.025              # MAX_PET_AGGRO_DISTANCE
const THINK := 0.6                            # pet_think_interval
const HEAL_BELOW := 0.5                       # pet_heal_threshold
const REACH := 2.2
# CommanderPet: minion slots by the commander's rank (returned / decayed 0, skeletal 1, bone 2, dread 3)
const COMMANDER_SLOTS := {"returned commander": 0, "decayed commander": 0, "skeletal commander": 1, "bone commander": 2,
		"dread commander": 3}
# BdPetBrain.CheckFormation: minions keep places around the commander - 50 units x the spacing (1) per step; /formation
const FORMATION_STEP := 50 * 0.025
var formation := "line"                       # line (default) / triangle / protect

static var _templates := {}
static var _style_rows := {}


## The pets' combat styles (pets.json 'styles': StyleID -> row with procs).
static func style_rows() -> Dictionary:
	if _style_rows.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PETS))
		var rows: Dictionary = parsed.get("styles", {}) if parsed is Dictionary else {}
		_style_rows = rows if not rows.is_empty() else {"": {}}
	return _style_rows

var combat: Combat
var casting: Casting
var npcs: NpcManager
var player: Player
var pet: NpcState                             # the controlled pet
var minions: Array = []                       # a commander's
var fnf: Array = []                           # theurgist elementals, animist fire-and-forget turrets
var _b := {}                                  # NpcState -> its brain state
var _pending: Array = []                      # [seconds, pet, target] pet blows waiting for the swing's impact
var _n := 0


static func template(id: int) -> Dictionary:
	if _templates.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PETS)) if FileAccess.file_exists(PETS) else null
		_templates = parsed.get("templates", {}) if parsed is Dictionary else {"": {}}
	return _templates.get(str(id), {})


func setup(c: Combat) -> void:
	combat = c
	casting = c.casting
	npcs = c.npcs
	player = c.player
	PlayerData.pet_order.connect(order)
	PlayerData.pet = {}
	PlayerData.pet_changed.emit()


func all() -> Array:
	var out := []
	if pet:
		out.append(pet)
	out.append_array(minions)
	out.append_array(fnf)
	return out


func is_pet(st: NpcState) -> bool:
	return _b.has(st)


## Every living pet of yours (controlled, turrets, bombers ...).
func all_pets() -> Array:
	return _b.keys().filter(func(p): return (p as NpcState).alive)


# --- summoning -------------------------------------------------------------------------------------------------------

## Why a summon can't be cast now ("" when it can) - SummonSpellHandler / SummonMinionHandler.CheckBeginCast.
func cannot_summon(spell: Dictionary) -> String:
	var kind := String(spell.get("type", ""))
	if kind in CONTROLLED and pet != null:
		return "You already have a charmed creature, release it first!"
	if kind == "SummonMinion":
		if pet == null or String(_b[pet].kind) != "SummonCommander":
			return "You must have a controlled leader monster to summon into a group!"
		if minions.size() >= int(COMMANDER_SLOTS.get(String(pet.spawn.name).to_lower(), 2)):
			return "Your general already has as many followers as he can command!"
		var total := 0
		for m in minions:
			total += (m as NpcState).level
		if total + _level_for(spell) > 75:
			return "Your commander is not powerful enough to control a minion of this level."
	if kind == "Bomber" and int(spell.get("subspellid", 0)) == 0:
		return "SPELL NOT IMPLEMENTED: CONTACT GM"
	if kind == "SummonAnimistFnF" and casting.ground_target != null:
		# SummonAnimistFnF.CheckBeginCast with the old server's caps (turret_area_cap_count 10 within 1000 units,
		# turret_player_cap_count 12 pets); Theurgist elementals have no cap in 1.65 (theurgist_pet_cap 0)
		var near := 0
		for f in fnf:
			if String(_b[f].kind) == "SummonAnimistFnF" and (f as NpcState).pos.distance_to(casting.ground_target) <= 1000 * 0.025:
				near += 1
		if near >= 10:
			return "You can't summon any more turrets in this area!"
		if all().size() >= 12:
			return "You cannot control any more turrets!"
	if kind in STATIONARY and (casting.ground_target == null or (casting.ground_target as Vector3).distance_to(player.global_position) > float(spell.get("range", 1000)) * 0.025):
		return "Your area target is out of range. Select a closer target."
	return ""


## GameSummonedPet.SetPetLevel.
func _level_for(spell: Dictionary) -> int:
	var d := float(spell.get("damage", 0))
	var lvl := int(d) if d >= 0.0 else int(PlayerData.level * d * -0.01)
	var cap := int(float(spell.get("value", 0)))
	if cap > 0 and lvl > cap:
		lvl = cap
	return maxi(1, lvl)


## The summon lands: the pet comes in front of you facing you (stationary ones at your ground target).
func summon(spell: Dictionary, target: NpcState) -> void:
	var kind := String(spell.get("type", ""))
	var t := template(int(spell.get("lifedrainreturn", 0)))
	if t.is_empty():
		PlayerData.message.emit("NPC template %d not found!" % int(spell.get("lifedrainreturn", 0)), "system")
		return
	var lvl := _level_for(spell)
	var at: Vector3
	if kind in STATIONARY and casting.ground_target != null:
		at = casting.ground_target
	else:
		var fwd := -player.global_transform.basis.z
		fwd.y = 0.0
		at = player.global_position + fwd.normalized() * 1.6
		at.y = npcs.ground_at(at)
	if kind == "Bomber":                                   # BomberSpellHandler: at your level, its name the spell's
		lvl = PlayerData.level
	var st := _make(t, lvl, at, spell)
	if kind == "Bomber":
		st.spawn["name"] = String(spell.get("name", "spirit"))
		st.run_speed = 350 * 0.025
	var b := {"kind": kind, "spell": spell, "mode": "defensive", "walk": "follow", "stay": at, "target": null,
			"aggro": {}, "think": 0.0, "swing": 0.6, "cast": {}, "cast_left": 0.0, "recast": {},
			"until": INF if int(spell.get("duration", 0)) >= 65535 else float(spell.get("duration", 0))}
	_b[st] = b
	if kind == "Bomber":
		b.until = 60.0                                     # BomberBrain: gone after 60 s
		b.mode = "bomber"
		b.target = target if target and String(spell.get("target", "")) == "Enemy" else pet
		fnf.append(st)
		changed.emit()
		return
	if kind in CONTROLLED:
		pet = st
		PlayerData.pet = {"name": String(st.spawn.name), "health": 1.0, "mode": "defensive"}
		PlayerData.pet_changed.emit()
	if kind == "SummonNecroPet":
		_necro_stats(st, t, lvl)
		player.shade = true                                # ClassDisciple.Shade(true)
		for s in npcs.states:                              # whatever fought you turns to the servant
			var m: NpcState = s
			if m.alive and m.fighting and m.target_pet == null:
				combat.add_aggro(m, st, int(m.aggro.get("player", 1)) + 1)
	elif kind == "SummonMinion":
		minions.append(st)
	else:
		fnf.append(st)
		b.mode = "aggressive"
		if target and target.alive:                     # SummonTheurgistPet: on the caster's target at once
			b.target = target
			b.aggro[target] = 1
	var m1 := SpellRules.msg(spell, "message1")
	PlayerData.message.emit(m1 if m1 != "" else "The %s is now under your control." % String(st.spawn.name), "spells")
	changed.emit()


func _make(t: Dictionary, lvl: int, at: Vector3, spell: Dictionary) -> NpcState:
	_n += 1
	var models: Array = t.get("models", [0])
	var sizes: Array = t.get("size", [50])
	var model := str(int(models[randi() % models.size()])) if not models.is_empty() else "0"   # JSON numbers are floats: "952", not "952.0" (no model, no view)
	var eq_key := ""
	var eq: Dictionary = t.get("equipment", {})
	var rows: Array = []
	if not (eq.get("variants", []) as Array).is_empty():
		var v: Array = eq.variants[randi() % (eq.variants as Array).size()]
		for r in v:
			rows.append({"slot": int(r.slot), "model": int((r.models as Array)[0]), "color": int(r.get("color", 0)),
					"effect": int(r.get("effect", 0)), "extension": int(r.get("extension", 0))})
	for r in eq.get("inline", []):
		var ms: Array = r.models
		rows.append({"slot": int(r.slot), "model": int(ms[randi() % ms.size()]), "color": 0, "effect": 0, "extension": 0})
	if not rows.is_empty():
		eq_key = "pet_%d" % _n
		var all_eq: Dictionary = npcs.data.get("equipment", {})
		all_eq[eq_key] = rows
		npcs.data["equipment"] = all_eq
	var factor := 1.0
	if String(spell.get("type", "")) not in NO_SCALE:
		var top := floorf(50.0 * absf(float(spell.get("damage", 0))) / 100.0)
		factor = lvl / top if top > 0.0 else 1.0
	var spells: Array = []
	for sid in t.get("spells", []):
		spells.append(int(sid))
	var s := {"id": "pet_%d" % _n, "name": String(t.get("name", "pet")), "guild": "", "level": lvl,
			"realm": int(PlayerData.realm_id()), "role": "pet", "trains": null, "class_type": "pet", "model": model,
			"size": int(sizes[randi() % sizes.size()]), "gender": 0,
			"pos": [at.x, at.y, at.z], "heading": 0, "aggro_level": 0, "aggro_range": 0, "roam": 0, "flags": 0,
			"speed": int(t.get("speed", 200)), "items": "", "equipment": eq_key, "faction": 0,
			"body_type": int(t.get("body_type", 0)), "template": 0, "stats": [0, 0, 0, 0],
			"damage_type": int(t.get("damage_type", 0)), "race": int(t.get("race", 0)), "respawn": 0,
			"defense": t.get("defense", [0, 0, 0, 0]), "spells": spells, "spell_scale": factor, "martial": 1.0,
			"abilities": t.get("abilities", []), "levels": [lvl], "models": [model], "sizes": [t.get("size", [50])[0]],
			"tether": 0, "styles": t.get("styles", [])}
	var st := npcs.add_spawn(s)
	# GameSummonedPet.SetStats: 30 + (L - 1) x 1 each, x the template's % where it has one
	var pct: Array = t.get("stat_pct", [0, 0, 0, 0, 0])
	var stats := []
	for i in 4:
		var v := 30 + (maxi(1, lvl - 1) if lvl > 1 else 0)
		if int(pct[i]) > 0:
			v = maxi(1, int(v * int(pct[i]) / 100.0))
		stats.append(v)
	st.stats = stats
	var intel := 30 + (maxi(1, lvl - 1) if lvl > 1 else 0)
	if int(pct[4]) > 0:
		intel = maxi(1, int(intel * int(pct[4]) / 100.0))
	st.spawn["intel"] = intel
	st.max_hp = maxi(1, int(17 * (lvl + 1) + 0.535 * lvl * lvl + (int(stats[1]) - 25) * 3))
	st.hp = st.max_hp
	st.health = 1.0
	st.home = at
	st.pos = at
	st.yaw = atan2(player.global_position.x - at.x, player.global_position.z - at.z)
	return st


## Release (the pet window, a new zone, the owner's death): it vanishes.
func release(st: NpcState, _quiet := false) -> void:
	if st == null or not _b.has(st):
		return
	if String(_b[st].kind) == "SummonNecroPet" and player.shade:
		_end_shade(st)
	if String(_b[st].kind) == "Charm":
		_break_charm(st)
		return
	_b.erase(st)
	npcs.remove_spawn(st)
	if st.view:
		(st.view as Node3D).visible = false
	if st == pet:
		pet = null
		for m in minions.duplicate():
			release(m, true)                              # a commander's minions go with it
		PlayerData.pet = {}
		PlayerData.pet_changed.emit()
	minions.erase(st)
	fnf.erase(st)
	for s in npcs.states:                                 # monsters forget it
		var m: NpcState = s
		if m.aggro.has(st):
			m.aggro.erase(st)
			if m.target_pet == st:
				m.target_pet = null
	changed.emit()


func release_all() -> void:
	for p in all():
		release(p, true)


## The pet window's commands (ControlledMobBrain).
func order(command: String) -> void:
	if command.begins_with("formation:"):
		set_formation(command.trim_prefix("formation:"))
		return
	if pet == null:
		return
	var b: Dictionary = _b[pet]
	match command:
		"aggressive", "defensive", "passive":
			b.mode = command
			if command == "passive":                       # Disengage
				b.target = null
				b.aggro = {}
			for m in minions:                              # minions take the commander's stance
				_b[m].mode = command
				if command == "passive":
					_b[m].target = null
					_b[m].aggro = {}
		"follow":
			b.walk = "follow"
		"stay":
			b.walk = "stay"
			b.stay = pet.pos
		"attack":
			var n: Npc = npcs.target
			if n == null or not is_instance_valid(n) or not n.state.alive or n.is_friendly():
				return
			if n.state.pos.distance_to(player.global_position) > 2000 * 0.025:   # GamePlayer.CommandNpcAttack: from you
				PlayerData.message.emit("Your target is too far away to attack with your pet!", "system")
				return
			if b.mode == "passive":
				b.mode = "defensive"
			b.target = n.state
			b.aggro[n.state] = int(b.aggro.get(n.state, 0)) + 1
			for m in minions:                               # the commander's minions join in
				_b[m].target = n.state
		"release":
			release(pet)
			return
	PlayerData.pet["mode"] = String(b.mode)


## A monster swings at you: defensive / aggressive pets take it on (ControlledMobBrain.OnOwnerAttacked); Theurgist
## elementals don't defend their caster.
func owner_attacked(st: NpcState) -> void:
	for p in all():
		var b: Dictionary = _b[p]
		if b.mode == "passive" or String(b.kind) == "SummonTheurgistPet":
			continue
		b.aggro[st] = int(b.aggro.get(st, 0)) + 1


# --- the brains ------------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_physics_step(delta)
	Perf.phys_add("pets", Time.get_ticks_usec() - t0)        # (Perf's live log: the physics tick by part)


func _physics_step(delta: float) -> void:
	if combat == null:
		return
	for i in range(_pending.size() - 1, -1, -1):
		_pending[i][0] -= delta
		if _pending[i][0] <= 0.0:
			var p: Array = _pending[i]
			_pending.remove_at(i)
			if _b.has(p[1]) and (p[1] as NpcState).alive:
				_pet_blow(p[1], p[2])
	for p in all():
		var st: NpcState = p
		var b: Dictionary = _b[st]
		if not st.alive:
			_died(st)
			continue
		b.until = float(b.until) - delta
		if float(b.until) <= 0.0:                         # a timed pet's spell ran out
			release(st, true)
			continue
		if st == pet:
			PlayerData.pet["health"] = st.health
		_think(st, b, delta)


func _think(st: NpcState, b: Dictionary, delta: float) -> void:
	if b.mode == "bomber":
		_bomber(st, b, delta)
		return
	if st.mezzed or st.stunned:
		st.mode = NpcState.Mode.IDLE
		b.cast = {}
		return
	var stationary := String(b.kind) in STATIONARY
	var t: NpcState = b.target
	if t and (not t.alive or int(t.spawn.realm) != 0):
		b.aggro.erase(t)
		t = null
		b.target = null
	if minions.has(st) and pet != null and b.mode != "passive":
		var ct: NpcState = _b[pet].target
		if ct != null and ct.alive and ct != t:
			t = ct
			b.target = ct
	b.think = float(b.think) - delta
	if float(b.think) <= 0.0:
		b.think = THINK
		if t == null and b.mode != "passive":
			t = _pick_target(st, b, stationary)
			b.target = t
		if _spells(st, b, t):
			return
	if not (b.cast as Dictionary).is_empty():             # casting: it stands still
		b.cast_left = float(b.cast_left) - delta
		st.mode = NpcState.Mode.IDLE
		if float(b.cast_left) <= 0.0:
			var sp: Dictionary = b.cast
			b.cast = {}
			_land(st, b, sp, t)
		return
	if t == null or b.mode == "passive":
		_walk(st, b, delta, stationary)
		return
	if stationary:                                         # turrets only cast
		st.yaw = lerp_angle(st.yaw, atan2(t.pos.x - st.pos.x, t.pos.z - st.pos.z), minf(1.0, delta * 8.0))
		st.mode = NpcState.Mode.IDLE
		return
	var to := t.pos - st.pos
	to.y = 0.0
	var dist := to.length()
	st.yaw = lerp_angle(st.yaw, atan2(to.x, to.z), minf(1.0, delta * 8.0))
	if dist > REACH * 0.8:
		st.pos += to / dist * minf(dist - REACH * 0.7, st.run_speed * st.speed_mult() * delta)
		st.pos.y = npcs.ground_at(st.pos)
		st.mode = NpcState.Mode.WALK
		return
	st.mode = NpcState.Mode.FIGHT
	b.swing = float(b.swing) - delta
	if float(b.swing) <= 0.0:
		b.swing = CombatRules.npc_swing_seconds(st.eff(3), combat._npc_weapon(st)) * st.swing_mult
		var at := 0.3
		if st.view:
			at = (st.view as Npc).play_attack() * Combat.HIT_AT
		_pending.append([at, st, t])


## NecromancerPet.SetStats: necro_pet_* (greater necroservant: necro_greater_pet_*) base 60 + (L - 1) x multiplier,
## x the template's %; MaxHealthCalculator: 32.5 x L + your item CON x 3 + your item hit points (capped).
const NECRO := {"str": [60, 1.0], "con": [60, 0.5], "dex": [60, 0.0], "qui": [60, 0.3333], "int": [60, 0.3333]}
const NECRO_GREATER := {"str": [60, 0.0], "con": [60, 0.3333], "dex": [60, 0.5], "qui": [60, 1.0], "int": [60, 0.3333]}


func _necro_stats(st: NpcState, t: Dictionary, lvl: int) -> void:
	var tbl: Dictionary = NECRO_GREATER if String(t.get("name", "")).to_lower() == "greater necroservant" else NECRO
	var pct: Array = t.get("stat_pct", [0, 0, 0, 0, 0])
	var out := []
	var keys := ["str", "con", "dex", "qui", "int"]
	for i in 5:
		var base: Array = tbl[keys[i]]
		var v := int(base[0])
		if lvl > 1:
			v += maxi(1, int((lvl - 1) * float(base[1])))
		if int(pct[i]) > 0:
			v = maxi(1, int(v * int(pct[i]) / 100.0))
		out.append(v)
	st.stats = out.slice(0, 4)
	st.spawn["intel"] = out[4]
	st.max_hp = int(32.5 * lvl + PlayerData.item_bonus(3) * 3 + mini(PlayerData.item_bonus(10), PlayerData.level * 4))
	st.hp = st.max_hp
	st.health = 1.0


## The servant is gone: you are flesh again, your health no more than its last share (at least 10%).
func _end_shade(st: NpcState) -> void:
	player.shade = false
	var share := maxf(10.0, st.health * 100.0)
	PlayerData.set_hp(ceili(minf(PlayerData.hp, PlayerData.max_hp * share * 0.01)))


## A Necromancer's PetSpell (PetSpellHandler): instant for you; the servant queues its sub-spell (its own cast time).
func necro_cast(spell: Dictionary, target: NpcState) -> void:
	if pet == null or String(_b[pet].kind) != "SummonNecroPet":
		PlayerData.message.emit("You must have a pet summoned to cast this spell!", "spells")
		return
	var sub := ClassDb.spell(int(spell.get("subspellid", 0)))
	if sub.is_empty():
		return
	var b: Dictionary = _b[pet]
	if not (b.cast as Dictionary).is_empty():
		PlayerData.message.emit("Your %s is busy casting and will cast this spell after its current action." % String(pet.spawn.name), "spells")
	b.cast = sub.merged({"_on": target if String(sub.get("target", "")) == "Enemy" else pet, "_owner": true,
			"_as": int(spell.spellid)})
	b.cast_left = float(sub.get("casttime", 0))
	if float(b.cast_left) <= 0.0:
		var sp: Dictionary = b.cast
		b.cast = {}
		_land(pet, b, sp, sp._on)


## BomberBrain: it flies at its target (350 units / s); within 150 units it delivers its spell (the summon's sub-spell,
## cast as yours, if the target is within 350) and is gone.
func _bomber(st: NpcState, b: Dictionary, delta: float) -> void:
	var t: NpcState = b.target
	if t == null or not t.alive:
		release(st, true)
		return
	var to := t.pos - st.pos
	to.y = 0.0
	var dist := to.length()
	if dist <= 150 * 0.025:
		var sub := ClassDb.spell(int((b.spell as Dictionary).get("subspellid", 0)))
		if not sub.is_empty() and dist <= 350 * 0.025:
			sub = sub.merged({"_as": int(b.spell.spellid)})
			if is_pet(t):
				_pet_friendly(t, sub)
			else:
				casting._apply_hostile(sub, t)
		release(st, true)
		return
	st.pos += to / dist * minf(dist, st.run_speed * delta)
	st.pos.y = npcs.ground_at(st.pos)
	st.yaw = atan2(to.x, to.z)
	st.mode = NpcState.Mode.WALK


## A spell you cast on your pet (eSpellTarget.PET): heals and buffs land on it; turret area spells go off around it;
## Release Clump unsummons your turrets; bombers fly to it.
func pet_spell(sp: Dictionary) -> void:
	if pet == null:
		return
	var kind := String(sp.get("type", ""))
	match kind:
		"Bomber":
			summon(sp, null)
		"TurretPBAoE":
			for hit in casting._area_targets(sp):
				casting._apply_hostile(sp, hit[0], hit[1])
		"TurretsRelease":
			for p in fnf.duplicate():
				if String(_b[p].kind) in STATIONARY and (p as NpcState).pos.distance_to(pet.pos) <= maxf(float(sp.get("radius", 0)), 1.0) * 0.025:
					release(p, true)
			if pet != null and _b.has(pet) and String(_b[pet].kind) in STATIONARY:   # (the loop may have released it)
				release(pet)
		_:
			_pet_friendly(pet, sp)


## A heal or buff on a pet: heals its health; buffs go on its own buff list (armour, stats, damage add / shield, haste,
## procs, PiercingMagic: its spells' hit chance + Value).
func _pet_friendly(st: NpcState, sp: Dictionary) -> void:
	var kind := String(sp.get("type", ""))
	if kind in Combat.NPC_HEALS:
		var amount := float(sp.get("value", 0))
		if amount < 0.0:
			amount = -amount / 100.0 * st.max_hp
		st.hp = mini(st.max_hp, st.hp + int(amount))
		st.health = float(st.hp) / st.max_hp
		PlayerData.message.emit("You heal your %s for %d hit points." % [String(st.spawn.name), int(amount)], "spells")
		return
	(st.npc_buffs as Array).append(sp)
	var v := int(float(sp.get("value", 0)) * casting.buff_effectiveness(sp))
	match kind:
		"BaseArmorFactorBuff", "SpecArmorFactorBuff", "PaladinArmorFactorBuff": st.af_bonus = maxi(st.af_bonus, v)
		"StrengthBuff": st.stat_buff[0] = maxi(int(st.stat_buff[0]), v)
		"ConstitutionBuff": st.stat_buff[1] = maxi(int(st.stat_buff[1]), v)
		"DexterityBuff": st.stat_buff[2] = maxi(int(st.stat_buff[2]), v)
		"QuicknessBuff": st.stat_buff[3] = maxi(int(st.stat_buff[3]), v)
		"StrengthConstitutionBuff":
			st.stat_buff[0] = maxi(int(st.stat_buff[0]), v)
			st.stat_buff[1] = maxi(int(st.stat_buff[1]), v)
		"DexterityQuicknessBuff":
			st.stat_buff[2] = maxi(int(st.stat_buff[2]), v)
			st.stat_buff[3] = maxi(int(st.stat_buff[3]), v)
	if SpellRules.msg(sp, "message2") != "":
		PlayerData.message.emit(SpellRules.msg(sp, "message2").format([combat._cap(combat._the(st))]), "spells")


# --- charm (CharmSpellHandler / CharmECSGameEffect) -------------------------------------------------------------


## A charm lands (and every pulse of a pulsing one): the checks of CheckEndCast, then the resist roll - pulsing charms
## (Minstrel / Mentalist): sweet spot = your level x 0.66 + spec x 0.33 - its level, resist 10 - 3 x spot (at least 1)
## or (10 + 1.5 x -spot) x 3 below it; permanent ones 100 - the hit chance. "X resists the charm! (N%)".
func charm(spell: Dictionary, st: NpcState, spec: int) -> void:
	var name := combat._cap(combat._the(st))
	var pulsing := int(spell.get("pulse", 0)) != 0
	var mine := _b.has(st) and String(_b[st].kind) == "Charm"
	if not mine:
		var why := _charm_check(spell, st, spec)
		if why != "":
			PlayerData.message.emit(why, "spells")
			casting.stop_pulse()
			return
	var resist := 0.0
	if pulsing:
		var spot := PlayerData.level * 0.66 + spec * 0.33 - st.level
		resist = maxf(10.0 - spot * 3.0, 1.0) if spot >= 0.0 else (10.0 + spot * -1.5) * 3.0
	else:
		resist = 100.0 - SpellRules.hit_chance(casting._spell_level(spell), PlayerData.level, st.level)
	if resist > 0.0 and randf() * 100.0 <= resist:
		PlayerData.message.emit("%s resists the charm! (%s%%)" % [name, str(snappedf(resist, 0.01))], "spells")
		if mine:
			_break_charm(st)
			casting.stop_pulse()
		return
	if mine:
		return                                            # control kept for this pulse
	if st.pos.distance_to(player.global_position) > 2000 * 0.025:
		return
	# under your control: your realm, its own stats, a pet brain
	st.spawn["realm"] = PlayerData.realm_id()
	st.fighting = false
	st.aggro = {}
	st.target_pet = null
	if combat.npc_casting:
		combat.npc_casting.interrupt(st)
	var b := {"kind": "Charm", "spell": spell, "mode": "defensive", "walk": "follow", "stay": st.pos, "target": null,
			"aggro": {}, "think": 0.0, "swing": 0.6, "cast": {}, "cast_left": 0.0, "recast": {}, "until": INF}
	_b[st] = b
	pet = st
	for s in npcs.states:                                 # monsters fighting it forget it
		var m: NpcState = s
		if m.aggro.has(st):
			m.aggro.erase(st)
	var m2 := SpellRules.msg(spell, "message2")
	PlayerData.message.emit(m2.format([name]) if m2 != "" else "%s is now under your control." % name, "spells")
	PlayerData.pet = {"name": String(st.spawn.name), "health": st.health, "mode": "defensive"}
	PlayerData.pet_changed.emit()
	changed.emit()


func _charm_check(spell: Dictionary, st: NpcState, spec: int) -> String:
	var name := combat._cap(combat._the(st))
	if pet != null:
		return "You already have a charmed creature, release it first!"
	if not st.alive or int(st.spawn.realm) != 0 or _b.has(st) or st.spawn.get("role") != null:
		return "You can't charm that target!"
	var body := int(st.spawn.get("body_type", 0))
	if body < 1 or body > 11:
		return "%s can't be charmed!" % name
	var n := String(st.spawn.name)
	if n.length() > 0 and n[0] == n[0].to_upper() and n[0] != n[0].to_lower():   # spell_charm_named_check 1
		return "%s can't be charmed!" % name
	# eCharmType (AmnesiaChance) -> eBodyType (Animal 1, Elemental 4, Humanoid 6, Insect 7, Magical 8, Reptile 9, Plant 10,
	# Undead 11), the old switch's fall-throughs; 0 = all
	var allowed := {1: [6], 2: [1], 3: [7], 4: [6, 1], 5: [6, 1, 7, 9], 6: [6, 1, 7, 9, 8, 10, 4],
			7: [6, 1, 7, 9, 8, 10, 4, 11], 8: [9]}
	var ct := int(spell.get("amnesiachance", 0))
	if allowed.has(ct) and body not in allowed[ct]:
		return "This spell does not charm that type of monster!"
	var cls := String(ClassDb.cls(PlayerData.class_id()).get("name", ""))
	if cls in ["Minstrel", "Mentalist"]:
		if st.level > int(float(spell.get("value", 0))) or st.level > spec * 1.1:
			return "%s is too strong for you to charm!" % name
	if cls in ["Hunter", "Sorcerer"]:
		if st.level > PlayerData.level or st.level > int(float(spell.get("value", 0))):
			return "%s is too strong for you to charm!" % name
		if st.fighting:
			return "You can't charm %s while %s is in combat!" % [combat._the(st), "it"]
	return ""


## The charm ends (the pulse stops, it resists, RELEASE): back to its own realm; after a pulsing charm it turns on you
## (threat your level x 10) and so does whatever fought it; worth no experience for 60 s.
func _break_charm(st: NpcState) -> void:
	var spell: Dictionary = _b[st].spell
	_b.erase(st)
	if st == pet:
		pet = null
		PlayerData.pet = {}
		PlayerData.pet_changed.emit()
	st.spawn["realm"] = 0
	st.charmed_at = Time.get_ticks_msec() / 1000.0
	st.aggro = {}
	if int(spell.get("pulse", 0)) != 0 and st.alive and not player.dead:
		combat.add_aggro(st, "player", PlayerData.level * 10)
		for s in npcs.states:
			var m: NpcState = s
			if m.alive and m.target_pet == st:
				m.aggro.erase(st)
				combat.add_aggro(m, "player", PlayerData.level * 10)
	changed.emit()


## Who it fights: the monster with the most threat on its list; aggressive ones (and fire-and-forget pets) also take
## on hostile monsters within 512 units (turrets: within their spells' range).
func _pick_target(st: NpcState, b: Dictionary, stationary: bool) -> NpcState:
	var best: NpcState = null
	var bv := -1
	for k in (b.aggro as Dictionary).keys():
		var m: NpcState = k
		if not m.alive:
			b.aggro.erase(k)
			continue
		if int(b.aggro[k]) > bv:
			best = m
			bv = int(b.aggro[k])
	if best or b.mode != "aggressive":
		return best
	var reach := AGGRO_RANGE
	if stationary:
		for sid in st.spawn.get("spells", []):
			reach = maxf(reach, float(NpcCasting.spell(int(sid)).get("range", 0)) * 0.025)
	var near := INF
	for s in npcs.states:
		var m: NpcState = s
		if not m.alive or int(m.spawn.realm) != 0 or _b.has(m):
			continue
		if int(m.spawn.get("aggro_level", 0)) <= 0 and not m.fighting:
			continue                                      # leaves neutral creatures alone
		var d := m.pos.distance_to(st.pos)
		if d <= reach and d < near:
			best = m
			near = d
	return best


func _walk(st: NpcState, b: Dictionary, delta: float, stationary: bool) -> void:
	if stationary:
		st.mode = NpcState.Mode.IDLE
		return
	var goal: Vector3 = b.stay if b.walk == "stay" else player.global_position
	var keep := 0.1 if b.walk == "stay" else FOLLOW_DIST
	if st != pet and pet != null and minions.has(st):
		goal = _formation_spot(minions.find(st))          # minions keep their place around the commander
		keep = 0.25
	var to := goal - st.pos
	to.y = 0.0
	var dist := to.length()
	if dist <= keep:
		st.mode = NpcState.Mode.IDLE
		return
	# MaxSpeedCalculator: following its owner out of combat it matches the owner's speed, x 1.3
	var speed := st.run_speed
	if b.walk == "follow" and not combat.in_combat():
		speed = maxf(speed, Player.RUN_SPEED * player.buff_speed) * 1.3
	st.pos += to / dist * minf(dist - keep * 0.9, speed * st.speed_mult() * delta)
	st.pos.y = npcs.ground_at(st.pos)
	st.yaw = lerp_angle(st.yaw, atan2(to.x, to.z), minf(1.0, delta * 8.0))
	st.mode = NpcState.Mode.WALK


## BdPetBrain.CheckFormation: minion i's place by the commander's facing - line: 50 / 100 / 150 units behind;
## triangle: 50 behind for the first, 100 behind and 50 to each side for the others; protect: 100 ahead for the first,
## 50 ahead and 50 to each side for the others (the commander between them).
func _formation_spot(i: int) -> Vector3:
	var fwd := Vector3(sin(pet.yaw), 0.0, cos(pet.yaw))
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var back := 0.0
	var side := 0.0
	match formation:
		"triangle":
			back = 1.0 if i == 0 else 2.0
			side = 1.0
		"protect":
			back = -2.0 if i == 0 else -1.0
			side = 1.0
		_:
			back = float(i + 1)
	var at := pet.pos - fwd * back * FORMATION_STEP
	if i == 1:
		at -= right * side * FORMATION_STEP
	elif i == 2:
		at += right * side * FORMATION_STEP
	at.y = npcs.ground_at(at)
	return at


## /formation (Bonedancer): "Only Bonedancers can use this command!" etc. (the old Formation command's messages).
func set_formation(kind: String) -> void:
	if pet == null or String(_b[pet].kind) != "SummonCommander":
		PlayerData.message.emit("You don't have a commander!", "system")
		return
	if minions.is_empty():
		PlayerData.message.emit("You don't have any minions!", "system")
		return
	formation = kind


# --- melee ------------------------------------------------------------------------------------------------------------

## A pet's blow on a monster (AttackComponent, NPC attacker): miss 18% - 1.33% per level over the target; the target's
## template evade / parry / block; damage by level, STR and weapon speed against the monster's armour and resist.
func _pet_blow(st: NpcState, t: NpcState) -> void:
	if not t.alive:
		return
	var name := String(st.spawn.name)
	combat._engage(t)
	st.last_swing_on = t
	if randf() < CombatRules.miss_chance(st.level, t.level):
		st.swing_result = "miss"
		_threat(t, st, 0)
		return
	var d: Array = t.spawn.get("defense", [0, 0, 0, 0])
	if not (t.mezzed or t.stunned) and ((int(d[0]) > 0 and randf() < int(d[0]) * 0.01) or (int(d[1]) > 0 and randf() < int(d[1]) * 0.01)):
		st.swing_result = "evade" if int(d[0]) > 0 else "parry"
		_threat(t, st, 0)
		return
	# its blow and its combat style (the Bonedancer's commanders and bone fighters have styles - pets.json)
	var res := combat.npc_melee_on_npc(st, t, 200.0, style_rows())
	var dmg: int = res[0]
	var landed: Dictionary = res[1]
	if t.bladeturn:
		t.bladeturn = false
		return
	PlayerData.message.emit("Your %s attacks %s and hits for %d damage!" % [name, combat._the(t), dmg], "combat")
	# CriticalMeleeHitChanceCalculator: a Necromancer's servant crits 10% of its hits (other pets none), an extra
	# 10..100% against a monster (CalculateCriticalDamage)
	if String((_b.get(st, {}) as Dictionary).get("kind", "")) == "SummonNecroPet" and randf() < 0.1:
		var crit := int(dmg * randf_range(0.1, 1.0))
		if crit > 0:
			PlayerData.message.emit("Your %s critically hits %s for an additional %d damage!" % [name, combat._the(t), crit], "combat")
			dmg += crit
	t.damage(dmg)
	if combat.npc_casting:
		combat.npc_casting.interrupt(t)
	if t.view:
		(t.view as Npc).flinch()
	_threat(t, st, dmg)
	if t.alive and not landed.is_empty():
		combat._npc_style_procs(st, landed, t)
	if not t.alive:
		combat._killed(t)                                 # its kills are yours
	combat._update_target(t)


## Threat (StandardMobBrain.ConvertAttackToAggroAmount): the pet's damage on it, 30% of that on you as well.
func _threat(t: NpcState, st: NpcState, dmg: int) -> void:
	combat.add_aggro(t, st, maxi(dmg, 1))
	combat.add_aggro(t, "player", int(dmg * 0.3))


## A monster's blow on a pet (Combat calls this when the monster fights it): "The X hits your Y for N damage.".
func npc_hits_pet(m: NpcState, st: NpcState) -> void:
	if not m.alive or not st.alive or not _b.has(st):
		return
	var who := combat._cap(combat._the(m))
	var pn := String(st.spawn.name)
	var b: Dictionary = _b[st]
	if b.mode != "passive":
		b.aggro[m] = int(b.aggro.get(m, 0)) + 1          # it defends itself
	if pet != null and (minions.has(st) or (st == pet and not minions.is_empty())):
		for q in [pet] + minions:                         # the commander's whole troop answers
			var qb: Dictionary = _b[q]
			if qb.mode != "passive":
				qb.aggro[m] = int(qb.aggro.get(m, 0)) + 1
	m.last_swing_on = st
	if randf() < CombatRules.miss_chance(m.level, st.level):
		m.swing_result = "miss"
		PlayerData.message.emit("%s attacks your %s and misses!" % [who, pn], "damage_taken")
		return
	var d: Array = st.spawn.get("defense", [0, 0, 0, 0])
	if int(d[0]) > 0 and randf() < int(d[0]) * 0.01:
		m.swing_result = "evade"
		PlayerData.message.emit("%s attacks your %s and is evaded!" % [who, pn], "damage_taken")
		return
	if int(d[1]) > 0 and randf() < int(d[1]) * 0.01:
		m.swing_result = "parry"
		PlayerData.message.emit("%s attacks your %s and is parried!" % [who, pn], "damage_taken")
		return
	var res := combat.npc_melee_on_npc(m, st, 175.0)        # the monster's styles work on pets too
	var dmg: int = res[0]
	PlayerData.message.emit("%s hits your %s for %d damage." % [who, pn, dmg], "damage_taken")
	st.damage(dmg)
	b.cast = {}                                           # a blow breaks its spell
	if st.view:
		(st.view as Npc).flinch()
	if st.alive and not (res[1] as Dictionary).is_empty():
		combat._npc_style_procs(m, res[1], st)
	if not st.alive:
		_died(st)


func _died(st: NpcState) -> void:
	if not _b.has(st):
		return
	if String(_b[st].kind) == "Charm":
		_b.erase(st)
		st.spawn["realm"] = 0
		pet = null
		PlayerData.pet = {}
		PlayerData.pet_changed.emit()
		casting.stop_pulse()
		changed.emit()
		return
	PlayerData.message.emit("%s dies!" % combat._cap(combat._the(st)), "combat")
	if st.view:
		(st.view as Npc).play_death()
	release(st, true)


# --- spells (ControlledMobBrain.CheckSpells) ---------------------------------------------------------------------------

## Heals under 50% (you first, then itself), its buffs on you and itself, then a harmful spell at its target. True
## when it starts a cast.
func _spells(st: NpcState, b: Dictionary, t: NpcState) -> bool:
	var spells: Array = st.spawn.get("spells", [])
	if spells.is_empty() or not (b.cast as Dictionary).is_empty():
		return false
	for k in (b.recast as Dictionary).keys():
		b.recast[k] = float(b.recast[k]) - THINK
		if float(b.recast[k]) <= 0.0:
			b.recast.erase(k)
	var factor := float(st.spawn.get("spell_scale", 1.0))
	var pick := {}
	var on: Variant = null
	for sid in spells:
		var sp := NpcCasting.scaled(NpcCasting.spell(int(sid)), factor)
		if sp.is_empty() or (b.recast as Dictionary).has(int(sid)):
			continue
		var kind := String(sp.get("type", ""))
		if kind in Combat.NPC_HEALS:
			if PlayerData.hp < PlayerData.max_hp * HEAL_BELOW and st.pos.distance_to(player.global_position) <= float(sp.get("range", 2000)) * 0.025:
				pick = sp
				on = "player"
				break
			if st.health < HEAL_BELOW:
				pick = sp
				on = st
				break
	if pick.is_empty():
		for sid in spells:
			var sp := NpcCasting.scaled(NpcCasting.spell(int(sid)), factor)
			if sp.is_empty() or (b.recast as Dictionary).has(int(sid)):
				continue
			var tg := String(sp.get("target", "")).to_lower()
			var kind := String(sp.get("type", ""))
			if tg in ["self", "realm", "group", "pet"] and kind not in Combat.NPC_HEALS and not kind.begins_with("Summon"):
				if tg != "self" and not casting.player_has(sp) and st.pos.distance_to(player.global_position) <= maxf(float(sp.get("range", 0)), 1500.0) * 0.025:
					pick = sp
					on = "player"
					break
				if not _has_buff(st, sp):
					pick = sp
					on = st
					break
	if pick.is_empty() and t and t.alive:
		for sid in spells:
			var sp := NpcCasting.scaled(NpcCasting.spell(int(sid)), factor)
			if sp.is_empty() or (b.recast as Dictionary).has(int(sid)) or String(sp.get("target", "")).to_lower() != "enemy":
				continue
			var rng := float(sp.get("range", 1500)) * 0.025
			if int(sp.get("range", 0)) <= 0:
				rng = float(sp.get("radius", 0)) * 0.025
			if t.pos.distance_to(st.pos) > rng:
				continue
			pick = sp
			on = t
			break
	if pick.is_empty():
		return false
	var ct := float(pick.get("casttime", 0))
	if ct <= 0.0:
		_land(st, b, pick, on)
		return false
	b.cast = pick.merged({"_on": on})
	b.cast_left = ct
	return true


func _has_buff(st: NpcState, sp: Dictionary) -> bool:
	return (st.npc_buffs as Array).any(func(x): return int(x.get("spellid", -1)) == int(sp.get("spellid", -2)))


func _land(st: NpcState, b: Dictionary, sp: Dictionary, target: Variant) -> void:
	var on: Variant = sp.get("_on", target)
	if bool(sp.get("_owner", false)):                     # a Necromancer's spell through the servant
		var radius := float(sp.get("radius", 0)) * 0.025
		if String(sp.get("target", "")) == "Enemy" and int(sp.get("range", 0)) <= 0 and radius > 0.0:
			for s2 in npcs.states:                         # point blank around the servant
				var m: NpcState = s2
				if m.alive and int(m.spawn.realm) == 0 and not _b.has(m) and m.pos.distance_to(st.pos) <= radius:
					casting._apply_hostile(sp, m, m.pos.distance_to(st.pos) / radius)
		elif on is NpcState and (on as NpcState).alive and on != st:
			if (on as NpcState).pos.distance_to(st.pos) > float(sp.get("range", 1500)) * 0.025 + 1.0:
				PlayerData.message.emit("Your %s's target is too far away!" % String(st.spawn.name), "spells")
				return
			if radius > 0.0:                               # an area around its target
				for s2 in npcs.states:
					var m: NpcState = s2
					if m.alive and int(m.spawn.realm) == 0 and not _b.has(m) and m.pos.distance_to((on as NpcState).pos) <= radius:
						casting._apply_hostile(sp, m, m.pos.distance_to((on as NpcState).pos) / radius)
			else:
				casting._apply_hostile(sp, on)
		else:
			_pet_friendly(st, sp)
		return
	if int(sp.get("recastdelay", 0)) > 0:
		b.recast[int(sp.spellid)] = float(sp.recastdelay)
	var kind := String(sp.get("type", ""))
	var name := String(st.spawn.name)
	if kind in Combat.NPC_HEALS:
		var amount := int(float(sp.get("value", 0)))
		if on is String:
			PlayerData.set_hp(mini(PlayerData.max_hp, PlayerData.hp + amount))
			PlayerData.message.emit("You are healed by the %s for %d hit points." % [name, amount], "spells")
		elif on is NpcState:
			st.hp = mini(st.max_hp, st.hp + amount)
			st.health = float(st.hp) / st.max_hp
		return
	if on is String:                                        # a buff on you
		casting._apply_friendly(sp)
		return
	if on == st:                                            # its own buff
		(st.npc_buffs as Array).append(sp)
		var v := int(float(sp.get("value", 0)))
		match kind:
			"BaseArmorFactorBuff", "SpecArmorFactorBuff", "PaladinArmorFactorBuff": st.af_bonus = maxi(st.af_bonus, v)
			"StrengthBuff": st.stat_buff[0] = maxi(int(st.stat_buff[0]), v)
			"DexterityBuff": st.stat_buff[2] = maxi(int(st.stat_buff[2]), v)
			"StrengthConstitutionBuff":
				st.stat_buff[0] = int(st.stat_buff[0]) + v
				st.stat_buff[1] = int(st.stat_buff[1]) + v
			"DexterityQuicknessBuff":
				st.stat_buff[2] = int(st.stat_buff[2]) + v
				st.stat_buff[3] = int(st.stat_buff[3]) + v
		return
	if on is NpcState and (on as NpcState).alive:
		var t: NpcState = on
		var pierce := 0.0
		for x in st.npc_buffs:
			if String(x.get("type", "")) == "PiercingMagic":
				pierce = maxf(pierce, float(x.get("value", 0)))
		casting._apply_hostile(sp.merged({"_npc_caster": {"level": st.level, "intel": int(st.spawn.get("intel", 30)), "name": name,
				"hit_bonus": pierce, "who": st}}), t)
		_threat(t, st, 1)
