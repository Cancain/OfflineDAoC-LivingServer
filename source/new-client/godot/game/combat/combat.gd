class_name Combat
extends Node
## Melee between the player and the zone's monsters (CombatRules for the numbers). The client's way:
## - the Combat Mode key draws the active weapon (attack mode) and puts it away again; swapping weapon sets (Right
##   Hand / Two Handed / Ranged keys) leaves attack mode, as the server's SwitchWeapon did; a bow can't enter melee
## - in attack mode with a monster targeted, in reach and in front, the player swings every weapon-speed seconds
## - a monster hit by the player (or an aggressive one that sees the player within its aggro range) fights back: it
##   chases, faces and swings every 3 s (its quickness changes that)
## - kills give experience (base classes stop at 5); the body lies a while, the spawn comes back after its respawn
## Chat lines are the old server's (en language files): "You attack the rat boy with your sword and hit for 7
## damage!", "You miss!", "The rat boy hits you for 3 damage!", "The rat boy attacks you and misses!", "You just
## killed the rat boy!", "You get 40 experience points.", "The rat boy is too far away to attack!", "The rat boy is not
## in view!", "You need to select a target to attack!", "You cannot enter combat mode without a weapon!".

signal attack_mode_changed(on: bool)
signal player_died
signal monster_killed(st: NpcState)                  # QuestEngine: kill steps, kill-task drops
signal killed_by(killer: String)                     # QuestEngine: die_to steps
signal player_released

const REACH := 3.2                          # metres: the 128-unit melee range, plus the two bodies
const FRONT := 0.5                          # cos(60 deg): the target must be inside the 120-degree front arc
const HIT_AT := 0.45
const WEAPONLESS := 19                      # cc_weapons.csv row for a creature's bare attacks                        # fraction of the swing animation where the blow lands

var player: Player
var npcs: NpcManager
var attack_mode := false
var _swing_left := 0.0
var _pending: Array = []                    # [[time left, Npc state, kind]] blows waiting for the swing's impact
var _warned := ""                           # the last range / view warning (said once, not every frame)
var _regen := 0.0
var _end_tick := 0.0
var _last_attack := -100.0                  # seconds of the player's last swing / hit taken: "in combat" for 10 s
var next_style := {}                        # the style queued for the next swing (and a backup)
var backup_style := {}
var last_target: NpcState                    # what the player's last swing was at (monsters' defensive styles)
var last_style := {}                         # ...that style (its BonusToDefense against the next monster swing)
var last_style_id := 0                      # the style that just landed (follow-up chains)
var last_result := ""                       # "hit" / "miss" / "style" - the player's last swing
var target_last_result := ""                # the monster's last swing at the player: "hit" / "miss" / ...
var bind_point := Vector3.ZERO              # where /release sends the player (the zone entry spot for now)
var casting: Casting                         # the player's spellcasting (blows interrupt it)
var _death_loss := 0                        # the experience the death took (release takes the same again)
var _death_pos := Vector3.ZERO
var _death_yaw := 0.0
var _grave: Node3D
var _praying := 0.0
var _dead_for := 0.0                        # seconds since death (the release timer)
var _auto_release := false                  # /release inside the first 10 s: release when they are up
var _release_warned := 0
const RELEASE_MINIMUM_WAIT := 10.0          # old server GamePlayer: /release can't happen sooner
const RELEASE_TIME := 900.0                 # ...and happens by itself after 15 minutes
const PRAY_RANGE := 2000 * 0.025            # IsWithinRadius(gravestone, 2000) in metres
const PRAY_SECONDS := 5.0
var abilities: Abilities
const NPC_HEALS := ["Heal", "CombatHeal", "HealOverTime", "OmniHeal", "SpreadHeal", "PBAoEHeal", "MercHeal"]
var npc_casting: NpcCasting
var pets: Pets
var last_damage := 0
var _npc_arrows: Array = []                   # [seconds to impact, archer] monster arrows in flight
var _ranged_blow := false                     # the blow being resolved is an arrow                         # the player's last blow (style taunts scale with it)
const CRIT_CHANCE := 10.0                   # a player's melee / archery critical chance (the old calculators: 10, cap 50)                    # Sprint (sitting and dying stop it)


## Seamless zones: you crossed a border and the scene moved by -d (the grave is a scene node - the viewer moves it).
func rebase(d: Vector3) -> void:
	bind_point -= d
	_death_pos -= d
	spawns_changed()


## The spawns changed (a zone loaded or left, or the scene moved): the gamebots' monster aggro grid is built again.
func spawns_changed() -> void:
	_aggro_grid.clear()
	_prey_grid.clear()
	_prey_wide.clear()


func setup(p: Player, n: NpcManager) -> void:
	player = p
	npcs = n
	player.landed.connect(_landed)
	PlayerData.hook(self, PlayerData.weapon_switched, func():
			if attack_mode:
				set_attack_mode(false)
			player.refresh_gear())
	PlayerData.hook(self, PlayerData.inventory_changed, func(): player.refresh_gear())
	PlayerData.release_requested.connect(release)
	PlayerData.pray_requested.connect(pray)
	PlayerData.leveled_up.connect(func(_lv): SpellFx.emote(8007, player, player.sounds))   # emote LvlUp
	PlayerData.sit_requested.connect(sit)
	PlayerData.emote_requested.connect(emote)
	PlayerData.bind_requested.connect(bind_here)
	PlayerData.track_requested.connect(func(mode: String):     # /follow /stick /face your target
		var t: Npc = npcs.target if npcs and npcs.target and is_instance_valid(npcs.target) else null
		player.start_track(mode, t, (t.display_name(true) if t else "")))
	PlayerData.invite_requested.connect(_invite)
	show_grave.call_deferred()
	PlayerData.use_skill.connect(_use_skill)
	bind_point = p.global_position
	player.refresh_gear()                                  # the character's weapons, now its inventory is loaded
	_add_caster()


## /bind (GamePlayer.Bind): not dead, once a minute; "Last Bind Point: in <zone>." and, standing inside a bind point's
## circle (BindPoint: 750 units; realm 0 or your realm - NormalServerRules), "You are now bound to this location.",
## else "You can't bind here!". /release brings you back to it, in its own zone.
var _bind_at := -1000.0


func bind_here() -> void:
	if player.dead or PlayerData.hp <= 0:
		PlayerData.message.emit("You cannot bind while dead!", "system")
		return
	var now := Time.get_ticks_msec() / 1000.0
	var every := float(CombatRules.r().get("bind_interval_s", 60))
	if now - _bind_at < every:
		PlayerData.message.emit("You must wait %d seconds to bind again!" % (1 + int(every - (now - _bind_at))), "system")
		return
	var bind: Dictionary = PlayerData.character.get("bind", {}) if PlayerData.character.get("bind") is Dictionary else {}
	var zname := String(npcs.zone.info.name)
	if not bind.is_empty():
		var bz = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zones_index.json"))
		zname = String((bz as Dictionary).get(str(int(bind.zone)), {}).get("name", zname)) if bz is Dictionary else zname
	PlayerData.message.emit("Last Bind Point: in %s." % zname, "system")
	var idx = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zones_index.json"))
	var me: Dictionary = (idx as Dictionary).get(str(int(npcs.zone.info.id)), {}) if idx is Dictionary else {}
	var rx := float(me.get("x", 0)) * 8192.0 + player.global_position.x / 0.025
	var ry := float(me.get("y", 0)) * 8192.0 + player.global_position.z / 0.025
	var inside := false
	for bp in CombatRules.r().get("bind_points", []):
		if int(bp[0]) == int(me.get("region", -1)) and (int(bp[5]) == 0 or int(bp[5]) == PlayerData.realm_id()) 				and Vector2(rx - float(bp[1]), ry - float(bp[2])).length() <= float(bp[4]):
			inside = true
			break
	if not inside:
		PlayerData.message.emit("You can't bind here!", "system")
		return
	_bind_at = now
	PlayerData.character["bind"] = {"zone": int(npcs.zone.info.id), "pos": [player.global_position.x,
			player.global_position.y, player.global_position.z], "face": fposmod(-rad_to_deg(player.facing()), 360.0)}
	bind_point = player.global_position
	PlayerData.save_character()
	PlayerData.message.emit("You are now bound to this location.", "system")
	SpellFx.emote(int({"alb": 8010, "mid": 8006, "hib": 8009}.get(String(PlayerData.character.get("realm", "hib")), 8009)),
			player, player.sounds)                         # the realm's bind emote (Albion / Midgard / Hibernian Bind)


## /release: back to the bind point with full health ("Your surroundings suddenly change!", old server).
func release() -> void:
	if not player.dead:
		PlayerData.message.emit("You are not dead!", "error")
		return
	var wait := ceili(RELEASE_MINIMUM_WAIT - _dead_for)
	if wait >= 1:                                          # GamePlayer.Release: too early - toggles auto release
		_auto_release = not _auto_release
		if _auto_release:
			PlayerData.message.emit("You will now release automatically in %d more seconds!" % wait, "system")
		else:
			PlayerData.message.emit("You will no longer release automatically. (%d more seconds)" % wait, "system")
		return
	_do_release()


func _do_release() -> void:
	_auto_release = false
	PlayerData.release_timer.emit(-1.0)
	player.revive()
	PlayerData.message.emit("You release your corpse unto death.", "system")
	# old server GamePlayer.Release (level 6+): the death's experience is taken again into a gravestone where you
	# fell (pray at it to win it back); constitution 1-3 by deaths this level (a healer restores it)
	var grave_before: Variant = PlayerData.grave
	PlayerData.release_losses(_death_loss, _death_pos, _death_yaw, int(npcs.zone.info.id) if npcs and npcs.zone else -1)
	if not is_same(PlayerData.grave, grave_before):
		show_grave()
	_death_loss = 0
	var bind: Dictionary = PlayerData.character.get("bind", {}) if PlayerData.character.get("bind") is Dictionary else {}
	var here := int(npcs.zone.info.id) if npcs and npcs.zone else -1
	if not bind.is_empty() and int(bind.zone) != here and FileAccess.file_exists("res://content/zones/zone%03d/zone.json" % int(bind.zone)):
		PlayerData.restore_full()                          # GamePlayer.Release: to the bind spot, in its own zone
		PlayerData.message.emit("Your surroundings suddenly change!", "system")
		get_tree().current_scene.travel_to(int(bind.zone), bind.pos, float(bind.get("face", 0.0)))
		return
	if not bind.is_empty() and int(bind.zone) == here:
		bind_point = Vector3(float(bind.pos[0]), float(bind.pos[1]), float(bind.pos[2]))
	player.global_position = bind_point
	player.velocity = Vector3.ZERO
	PlayerData.restore_full()
	PlayerData.message.emit("Your surroundings suddenly change!", "system")
	player_released.emit()


func toggle() -> void:
	if PlayerData.active_weapon == "ranged":
		ranged_attack()                                    # bows: draw, then fire (old archery)
		return
	set_attack_mode(not attack_mode)


func set_attack_mode(on: bool) -> void:
	if on and player.shade:
		PlayerData.message.emit("You cannot enter combat while in shade form!", "combat")
		return
	if abilities and abilities.engaged != null:
		abilities.end_engage(not on)                        # attacking (or leaving combat mode) ends Engage
	if on:
		if PlayerData.active_weapon == "ranged":
			PlayerData.message.emit("You can't enter melee combat mode with a ranged weapon!", "combat")
			return
		if _weapon().is_empty():
			PlayerData.message.emit("You cannot enter combat mode without a weapon!", "combat")
			return
	if on == attack_mode:
		return
	if on and player.sitting:
		sit(false)
	attack_mode = on
	_swing_left = 0.0 if on else _swing_left
	_weapon_sound(player.sounds, "activate" if on else "deactivate")   # the client's draw / sheathe sounds
	_warned = ""
	player.set_combat(on, WeaponModels.stance(int(_weapon().get("model", 0))))
	attack_mode_changed.emit(on)


## The active melee weapon's item, or {}.
func _weapon() -> Dictionary:
	return MeleeMath.weapon(PlayerData)


var prof_phys_us := 0                        # debug timing (the world host's status line)


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_physics_step(delta)
	Perf.phys_add("combat", Time.get_ticks_usec() - t0)        # (Perf's live log: the physics tick by part)


func _physics_step(delta: float) -> void:
	var tq := Time.get_ticks_usec()
	_physics_body(delta)
	prof_phys_us += Time.get_ticks_usec() - tq


func _physics_body(delta: float) -> void:
	if npcs == null:
		return
	if player == null:                                     # a world host zone: monsters and gamebots only
		_bots_tick(delta)
		_monsters(delta)
		_impacts(delta)
		_npc_arrows_tick(delta)
		return
	_bots_tick(delta)
	_player_swings(delta)
	_monsters(delta)
	_impacts(delta)
	_regen_ticks(delta)
	_npc_arrows_tick(delta)
	_ranged_tick(delta)
	_pray_tick(delta)
	var spd := float(PlayerData.buffs.get("speed", 0.0))
	player.buff_speed = spd / 100.0 if spd > 0.0 else 1.0   # SpeedEnhancement: Value % of normal speed
	_release_tick(delta)
	if player.sitting and player.velocity.length() > 0.2:
		sit(false)                                         # GamePlayer.OnPlayerMove: moving stands you up


# --- the player's swings -------------------------------------------------------------------------------------------

var _target_alive: Npc = null                 # the target last seen alive while in attack mode


func _player_swings(delta: float) -> void:
	_swing_left -= delta
	# owner 2026-10-10 (tested on the old client): attack mode drops by itself when your target dies - by your blow,
	# a pet's, a spell, anyone's
	var tgt: Npc = npcs.target
	if attack_mode and tgt != null and is_instance_valid(tgt):
		if tgt.state.alive:
			_target_alive = tgt
		elif _target_alive == tgt:
			_target_alive = null
			set_attack_mode(false)
			return
	if not attack_mode or PlayerData.hp <= 0 or player.cc in ["stun", "mez"]:
		return
	if abilities and abilities.engaged != null:
		return                                              # engaging: blocking, not swinging
	var t: Npc = npcs.target
	if t == null or not is_instance_valid(t) or not t.state.alive:
		return
	if t.is_friendly() or int(t.spawn.realm) != 0:
		return
	var to := t.global_position - player.global_position
	to.y = 0.0
	if to.length() > REACH + t.height * 0.15:
		_warn("%s is too far away to attack!" % _cap(t.display_name(true)))
		return
	var fwd := Vector3(-sin(player.facing()), 0.0, -cos(player.facing()))
	if to.length() > 0.3 and fwd.dot(to.normalized()) < FRONT:
		_warn("%s is not in view!" % _cap(t.display_name(true)))
		return
	_warned = ""
	if _swing_left > 0.0:
		return
	var w := _weapon()
	_swing_left = _player_swing_seconds(w)
	if casting:
		casting.on_own_swing()                             # SelfInterruptDurationOnMeleeAttack: 3 s
	var style := _style_to_use(t.state)
	next_style = {}
	backup_style = {}
	var clip := ""
	var styled := not style.is_empty() and _style_ok(style, t.state)
	if styled:
		var two := PlayerData.active_weapon == "twohand"
		clip = player.play_style(int(style.get("animation_2h" if two else "animation", 0)))
		# the style's colour flash: styles.csv's coloured afterimages of the weapon over the swing (StyleTrail)
		StyleTrail.play(player.get_parent(), StyleTrail.held(player._model), StyleTrail.trail_of(style, two))
	if clip == "":
		clip = player.swing(WeaponModels.stance(int(w.get("model", 0))))
	# cc_weapons 'use' at the moment of attack - a style's own swing sound ('style_use', s_StyleAttack_Use) when one
	# goes off (owner 2026-10-10: "the styles have sound effects when they land in the original client")
	_weapon_sound(player.sounds, "style_use" if styled else "use")
	_pending.append([player.clip_seconds(clip) * HIT_AT, t.state, "player", style])
	_last_attack = Time.get_ticks_msec() / 1000.0
	_engage(t.state)


## The active weapon's cc_weapons event (objects.csv sound set) on a character's sound node.
func _weapon_sound(on: CharacterSounds, key: String) -> void:
	if on == null:
		return
	var set_id := int(WeaponModels.info(int(_weapon().get("model", 0))).get("sound_set", 0))
	if set_id > 0:
		on.weapon(set_id, key)


func _warn(text: String) -> void:
	if _warned != text:
		_warned = text
		PlayerData.message.emit(text, "combat")


## The player's blow lands (or misses) on a monster.
func _player_blow(st: NpcState, style: Dictionary) -> void:
	if not st.alive:
		return
	last_target = st
	var who := _the(st)
	var w := _weapon()
	if w.is_empty():
		return
	# the style's opening is judged on the state before this swing (owner 2026-10-10 combos): this blow resets
	# last_result to "hit" further down, and a follow-up re-checked after that always failed ("You fail to execute")
	var style_ok := not style.is_empty() and _style_ok(style, st)
	# the old server's order: evade, parry, block, then hit or miss (a defended blow uses up the style, no endurance)
	var defended := _npc_defends(st, w)
	if defended != "":
		last_result = defended
		PlayerData.message.emit("%s %s your attack!" % [_cap(who), {"evade": "evades", "parry": "parries", "block": "blocks"}[defended]], "combat")
		if st.view:
			(st.view as Npc).play_defend(defended)
			if defended != "evade":
				_weapon_sound((st.view as Npc).sounds, "parried" if defended == "parry" else "blocked")
			elif (st.view as Npc).sounds:
				(st.view as Npc).sounds.event("evade")
		_update_target(st)
		return
	# the numbers (miss, bladeturn, damage, style, critical) are MeleeMath's - the gamebots swing by the same rules
	var berserk := abilities != null and abilities.berserk_left > 0.0
	var r := MeleeMath.character_blow(PlayerData, st, w, style, {"style_ok": style_ok,
			"melee_mult": casting.player_melee_mult() if casting else 1.0,          # melee damage debuffs on the player
			"crit_chance": 100.0 if berserk else CRIT_CHANCE,                       # Berserk: every hit
			"crit_top": minf(1.0, _ability_level("Berserk") * 0.25) if berserk else 1.0})   # Berserk 1 = 10-25%
	if r.result == "miss":
		PlayerData.message.emit("You miss!", "combat")
		last_result = "miss"
		return
	if r.result == "bladeturn":                            # its bladeturn takes the blow
		PlayerData.message.emit("Your strike was absorbed by a magical barrier!", "combat")
		if npc_casting:
			npc_casting.interrupt(st)
		return
	last_result = "hit"
	if not style.is_empty():
		# old server ExecuteStyle: the endurance is spent either way; a style whose opening fails still swings, but
		# "You fail to execute your <style> perfectly!" and adds nothing
		_spend_endurance(maxi(1, int(CombatRules.style_endurance(style, int(w.get("spd_abs", 30))) * (1.0 - float(PlayerData.buffs.get("fatigue", 0.0)) * 0.01))))
		if r.result == "style":
			last_result = "style"
			last_style_id = int(style.id)                     # chains name the in-game style id
			last_style = style
			PlayerData.message.emit("You perform your %s perfectly! (+%d)" % [String(style.name), int(r.shown)], "combat")
		else:
			PlayerData.message.emit("You fail to execute your %s perfectly!" % String(style.name), "combat")
	var short := String(w.get("name", "weapon")).split(" ")[-1]
	var dmg: int = r.dmg
	var mod: int = r.modifier
	PlayerData.message.emit("You attack %s with your %s and hit for %d%s damage!" % [who, short, dmg,
			(" (+%d)" % mod) if mod > 0 else ((" (%d)" % mod) if mod < 0 else "")], "combat")
	if int(r.crit) > 0:
		PlayerData.message.emit("You critical hit %s for an additional %d damage! (%d%%)" % [who, int(r.crit), int(100.0 if berserk else CRIT_CHANCE)], "combat")
		dmg += int(r.crit)
	PlayerData.wear_item({"standard": 10, "twohand": 12}.get(PlayerData.active_weapon, 10))   # weapon condition
	var heavy := dmg >= st.max_hp * 0.1                    # the sheets: light < 10% of the defender's hit points
	st.damage(dmg)
	last_damage = dmg
	add_aggro(st, "player", dmg)
	if npc_casting:
		npc_casting.interrupt(st)                          # a blow breaks its spell
		_npc_damage_shields(st)
	if last_result == "style" and st.alive:
		_style_procs(style, st)                            # after the damage, as the old server starts them
	if st.alive:
		_damage_adds(st, w, r.cap)
	if st.alive and casting:
		casting.player_procs("offensive", st)
	if abilities:
		abilities.break_stealth()
	if st.view:
		var v := st.view as Npc
		v.flinch()
		if last_result == "style":                        # a landed style: the sheet's heavy style hit and cry
			_weapon_sound(v.sounds, "style_hit")
			if v.sounds and st.alive:
				v.sounds.event("pain_heavy")
		else:
			_weapon_sound(v.sounds, "hit_medium" if heavy else "hit_light")
			if v.sounds and st.alive:
				v.sounds.event("pain_medium" if heavy else "pain_light")
	if not st.alive:
		_killed(st)
	_update_target(st)


func _killed(st: NpcState) -> void:
	npcs.ambient(st, "dying", PlayerData.display_name(), true)
	PlayerData.message.emit("You just killed %s!" % _the(st), "combat")
	if st.view:
		(st.view as Npc).play_death()
		if (st.view as Npc).sounds:
			(st.view as Npc).sounds.event("die")
	var con := npcs.con_level(PlayerData.level, st.level)
	if Time.get_ticks_msec() / 1000.0 - st.charmed_at < 60.0:   # GameNPC.CHARMED_NOEXP_TIMEOUT
		PlayerData.message.emit("This monster has been charmed recently and is worth no experience.", "system")
	elif not (group_xp.is_valid() and group_xp.call(st)):  # companions with you: the kill is shared (Companions)
		PlayerData.gain_xp(CombatRules.kill_xp(st.level, PlayerData.level, con <= -3))
	PlayerData.faction_killed(int(st.spawn.get("faction", 0)))   # AbstractServerRules: Faction.OnMemberKilled
	monster_killed.emit(st)


## How far from you monsters look around for other monsters to fight (the part of the world that is simulated).
const SIM_RADIUS := 160.0


## StandardMobBrain.CheckNpcAggro: an idle aggressive monster notices, within its aggro range, your pets (judged as you:
## not grey to you, your faction standing, in sight) and monsters of its faction's enemies (FactionMgr.CanLivingAttack;
## not when it is grey to them; no sight check between monsters, as the old server).
func _scan_npc_foes(st: NpcState) -> void:
	var r := mini(int(st.spawn.aggro_range), 3600) * 0.025          # MAX_AGGRO_DISTANCE
	if pets and PlayerData.hp > 0 and npcs.con_level(PlayerData.level, st.level) > -3 and _faction_aggressive(st):
		for p in pets.all_pets():
			var pet: NpcState = p
			if pet.pos.distance_to(st.pos) <= r and _sees(st, pet.pos):
				add_aggro(st, pet, 0)
				return
	var fid := int(st.spawn.get("faction", 0))
	if fid == 0:
		return
	var enemies: Array = CombatRules.r().get("factions", {}).get(str(fid), {}).get("enemies", [])
	if enemies.is_empty():
		return
	for e in enemies:
		for o in _faction_members().get(int(e), []):
			var other: NpcState = o
			if other.alive and other != st and other.pos.distance_to(st.pos) <= r and npcs.con_level(other.level, st.level) > -3 \
					and (int(other.spawn.get("flags", 0)) & 16) == 0:
				add_aggro(st, other, 0)
				return


var _by_faction := {}                                    # faction id -> its monsters in this zone


func _faction_members() -> Dictionary:
	if _by_faction.is_empty():
		_by_faction[-1] = []
		for s in npcs.states:
			var st: NpcState = s
			var f := int(st.spawn.get("faction", 0))
			if f != 0 and int(st.spawn.realm) == 0:
				if not _by_faction.has(f):
					_by_faction[f] = []
				_by_faction[f].append(st)
	return _by_faction


## GuardBrain.CheckNpcAggro: a guard attacks any monster within 750 units (its AggroRange) it may attack - realm 0,
## not flying, not peaceful; no level or sight check. (Enemy-realm players: with the RvR work.)
func _guard_scan(st: NpcState) -> void:
	for s in npcs.states:
		var o: NpcState = s
		if o.alive and int(o.spawn.realm) == 0 and (int(o.spawn.get("flags", 0)) & (16 | 32)) == 0 \
				and o.pos.distance_to(st.pos) <= 750.0 * 0.025:
			add_aggro(st, o, 0)
			return


## The highest threat still alive on a monster's list (pets, other monsters, gamebots).
func _next_foe(st: NpcState) -> Variant:
	var best: Variant = null
	var bv := -1
	for k in st.aggro.keys():
		if ((k is NpcState and (k as NpcState).alive) or (k is BotFoe and (k as BotFoe).alive)) and int(st.aggro[k]) > bv:
			best = k
			bv = int(st.aggro[k])
	return best


## The pet, monster or gamebot it fights, if still alive (the dead come off its list); null when it's you.
func _foe_of(st: NpcState) -> Variant:
	if st.target_pet != null and not st.target_pet.alive:
		st.aggro.erase(st.target_pet)
		st.target_pet = null
	if st.target_bot != null and not st.target_bot.alive:
		st.aggro.erase(st.target_bot)
		st.target_bot = null
	return st.target_pet if st.target_pet != null else st.target_bot


## Sight from a monster's eyes to a point 1.5 m up (walls, fixtures, terrain).
func _sees(st: NpcState, at: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(st.pos + Vector3(0, 1.5, 0), at + Vector3(0, 1.5, 0), ZoneLoader.LAYER_WALL | ZoneLoader.LAYER_FLOOR)
	return npcs.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## A monster's blow on another monster (enemy factions): the monster formula both ways (its level, STR, weapon against
## the other's level, AF and absorb, divisor 200, x its resist), the other's evade / parry / block; it fights back.
## An NPC's landed blow on another NPC (a monster on a monster or a pet, a pet on a monster): the monster formula
## (AF divisor 200 monsters / 175 pets), its melee damage debuff, the target's resist, the 3 x base cap, and its style
## (NpcStyleComponent against that target; growth rate x its level) on top. Returns [damage, the style landed or {}].
func npc_melee_on_npc(att: NpcState, t: NpcState, divisor: float, rows: Dictionary = {}) -> Array:
	var style := _npc_style_to_use(att, t, rows)
	var p := CombatRules.npc_vs_npc_parts(att.level, att.eff(0), _npc_weapon(att), t.level, t.af_bonus - t.af_debuff,
			t.absorb(), divisor)
	var rm := 1.0 - t.resist(int(att.spawn.get("damage_type", 2))) * 0.01
	var d := minf(float(p[0]) * (1.0 - att.melee_debuff * 0.01) * rm, float(p[1]))
	var style_ok := not style.is_empty() and _npc_style_ok(att, style, t)   # before this swing resets its last result
	att.last_swing_on = t
	att.swing_style = {}
	att.swing_result = "hit"
	if style_ok:
		if att.view and is_instance_valid(att.view):
			StyleTrail.play_from_impact(player.get_parent(), (att.view as Npc).model, style)
		var secs := CombatRules.npc_swing_seconds(att.eff(3), _npc_weapon(att)) * att.swing_mult * _npc_haste(att)
		var sp := CombatRules.style_damage_parts(style, att.level, secs, float(p[0]), float(p[1]))
		d += minf(float(sp[0]) * rm, float(sp[1]))
		att.swing_result = "style"
		att.swing_style = style
	return [maxi(1, int(d)), att.swing_style]


func _npc_hits_npc(m: NpcState, t: NpcState) -> void:
	if not m.alive or not t.alive:
		return
	m.last_swing_on = t
	if randf() < CombatRules.miss_chance(m.level, t.level):
		m.swing_result = "miss"
		add_aggro(t, m, 1)
		return
	var d: Array = t.spawn.get("defense", [0, 0, 0, 0])
	if not (t.mezzed or t.stunned):
		if (int(d[0]) > 0 and randf() < int(d[0]) * 0.01) or (int(d[1]) > 0 and randf() < int(d[1]) * 0.01):
			m.swing_result = "evade" if int(d[0]) > 0 else "parry"
			add_aggro(t, m, 1)
			if t.view:
				(t.view as Npc).play_defend("evade" if int(d[0]) > 0 else "parry")
			return
		var g := _npc_gear(t)
		if int(d[2]) > 0 and int(d[3]) <= 0 and g.has(11) and not g.has(12) and randf() < int(d[2]) * 0.01:
			m.swing_result = "block"
			add_aggro(t, m, 1)
			if t.view:
				(t.view as Npc).play_defend("block")
			return
	if t.bladeturn:
		t.bladeturn = false
		add_aggro(t, m, 1)
		return
	var r := npc_melee_on_npc(m, t, 200.0)
	npc_hurts_npc(t, m, int(r[0]))
	if t.alive and not (r[1] as Dictionary).is_empty():
		_npc_style_procs(m, r[1], t)


## Damage from a monster on a monster (blows, spells): it turns on the attacker; a death is your kill only if you or
## your pet hurt it (the old XPGainers credit only players' side), otherwise it just dies.
func npc_hurts_npc(t: NpcState, m: NpcState, dmg: int) -> void:
	t.damage(dmg)
	if npc_casting:
		npc_casting.interrupt(t)
	if t.alive:
		add_aggro(t, m, maxi(dmg, 1))
		if t.view:
			(t.view as Npc).flinch()
	elif t.player_hit:
		_killed(t)
	else:
		npcs.ambient(t, "dying", String(m.spawn.name))
		if t.view:
			(t.view as Npc).play_death()
			if (t.view as Npc).sounds:
				(t.view as Npc).sounds.event("die")
	_update_target(t)


## StandardMobBrain.CanAggroTarget: a monster with a faction aggroes on you only while your standing with it is
## aggressive (hostility over 75 - most factions start at 100; a few, mostly Albion / Midgard townsfolk, lower).
func _faction_aggressive(st: NpcState) -> bool:
	var fs := PlayerData.faction_standing(int(st.spawn.get("faction", 0)))
	return fs == "" or fs == "aggressive"


## check_los_before_aggro (on in the old server): it must see you - nothing solid between its eyes and yours.
func _sees_player(st: NpcState) -> bool:
	var space := player.get_world_3d().direct_space_state
	var from := st.pos + Vector3(0, 1.5, 0)
	var to := player.global_position + Vector3(0, 1.5, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, ZoneLoader.LAYER_WALL | ZoneLoader.LAYER_FLOOR)
	return space.intersect_ray(q).is_empty()


## /wave, /bow ... (EmoteCommandHandler): not dead, not fighting / mezzed / stunned, a target within 2048 units, one
## emote every 3 s; the animation and the lines - no target: "You wave at everyone."; a target: "You wave to the X."
static var _emotes := {}


static func emotes() -> Dictionary:
	if _emotes.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://content/rules/emotes.json"))
		_emotes = parsed if parsed is Dictionary else {"emotes": {}}
	return _emotes.get("emotes", {})


var _emote_at := -100.0


func emote(cmd: String) -> void:
	var e: Dictionary = emotes().get(cmd, {})
	if e.is_empty():
		return
	if player.dead or PlayerData.hp <= 0:
		PlayerData.message.emit("You can't do that, you're dead!", "system")
		return
	if attack_mode or player.cc in ["stun", "mez"]:
		PlayerData.message.emit("You can't do that, you're busy!", "system")
		return
	var t: Npc = npcs.target if npcs.target and is_instance_valid(npcs.target) else null
	if t and t.global_position.distance_to(player.global_position) > 2048 * 0.025:
		PlayerData.message.emit("You don't see your target around here.", "system")
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _emote_at < float(_emotes.get("delay_seconds", 3.0)):
		var lines: Array = _emotes.get("too_fast", [])
		if not lines.is_empty():
			PlayerData.message.emit(String(lines[randi() % lines.size()]), "system")
		return
	_emote_at = now
	player.play_emote(int(e.emote))
	var m: Array = e.get("messages", [])
	if m.size() >= 4:
		PlayerData.message.emit(String(m[2]).replace("{0}", _the(t.state)) if t else String(m[0]), "emote")


## /sit and /stand (old server GamePlayer.Sit). Sitting stops sprint and attack mode, and makes the rest ticks
## come faster; moving, attacking or casting stands you up again.
func sit(on: bool, quiet := false) -> void:
	if abilities and abilities.sprinting:
		abilities.toggle_sprint()
	if player.sitting == on:
		if not quiet:
			PlayerData.message.emit("You are already sitting!" if on else "You are not sitting!", "system")
		return
	if player.dead:
		PlayerData.message.emit("You can't sit down now, you're dead!", "system")
		return
	if on and player.velocity.length() > 0.2:
		PlayerData.message.emit("You must be standing still to sit down.", "system")
		return
	PlayerData.message.emit("You sit down.  Type '/stand' or move to stand up." if on else "You stand up.", "system")
	if on and attack_mode:
		set_attack_mode(false)
	if on and casting and not casting.casting.is_empty():
		PlayerData.message.emit("You move and interrupt your spellcast!", "spells")   # SpellHandler.CasterMoves
		casting.interrupt()
	if not on:
		_praying = 0.0
	player.sit(on)


## The release timer (GamePlayer.ReleaseTimerCallback): released automatically after RELEASE_TIME, or as soon as
## the minimum wait is over if /release was typed early; "You will autorelease in 30 / 10 seconds."
func _release_tick(delta: float) -> void:
	if not player.dead:
		return
	_dead_for += delta
	if _auto_release and _dead_for > RELEASE_MINIMUM_WAIT:
		_do_release()
		return
	var left := RELEASE_TIME - _dead_for
	PlayerData.release_timer.emit(left)
	if left <= 0.0:
		_do_release()
	elif left <= 10.0 and _release_warned < 2:
		_release_warned = 2
		PlayerData.message.emit("You will autorelease in 10 seconds.", "system")
	elif left <= 30.0 and _release_warned < 1:
		_release_warned = 1
		PlayerData.message.emit("You will autorelease in 30 seconds.", "system")


## The player's gravestone (objects.csv 637 Hibernia / 636 Midgard / 145 Albion), "<name>'s Grave".
func show_grave() -> void:
	if _grave and is_instance_valid(_grave):
		_grave.queue_free()
	_grave = null
	if PlayerData.grave.is_empty() or not _grave_here():
		return
	var model := int({"hib": 637, "mid": 636, "alb": 145}.get(String(PlayerData.character.get("realm", "hib")), 637))
	_grave = WeaponModels.make_world(model)
	if _grave == null:
		return
	var p: Array = PlayerData.grave.pos
	_grave.position = Vector3(p[0], p[1], p[2])
	_grave.rotation.y = float(PlayerData.grave.get("yaw", 0.0)) + PI   # GameGravestone: the player's heading (models face +Z)
	get_parent().add_child(_grave)


func _grave_here() -> bool:
	var z := int(PlayerData.grave.get("zone", -1))
	return z < 0 or (npcs and npcs.zone and z == int(npcs.zone.info.id))


## /invite: there is no grouping with other people here. An autonomous gamebot turns you down and points you to the
## roadside inn, where companions are found (owner 2026-10-10); anything else isn't a player.
func _invite(_who: String) -> void:
	var t: Npc = npcs.target if npcs and npcs.target and is_instance_valid(npcs.target) else null
	if t and bool(t.spawn.get("gamebot", false)):
		PlayerData.message.emit("%s is not interested in joining you. Seek out the roadside inn to find like minded travelers." % t.display_name(true), "system")
		return
	PlayerData.message.emit("You have not selected a valid player as your target.", "system")


## /pray at your gravestone (old server GamePlayer.Pray): stand still at it for a few seconds and the release
## experience comes back ("You pray at your grave and gain back experience!").
func pray() -> void:
	if PlayerData.grave.is_empty():
		PlayerData.message.emit("You need to target a grave at which to pray!", "system")
		return
	var p: Array = PlayerData.grave.pos
	if not _grave_here():
		PlayerData.message.emit("You must get closer to your grave and sit to pray!", "system")
		return
	if player.dead:
		PlayerData.message.emit("You can't pray now!", "system")
		return
	if player.global_position.distance_to(Vector3(p[0], p[1], p[2])) > PRAY_RANGE:
		PlayerData.message.emit("You must get closer to your grave and sit to pray!", "system")
		return
	if player.velocity.length() > 0.2:
		PlayerData.message.emit("You must be standing still to pray.", "system")
		return
	if _praying > 0.0:
		PlayerData.message.emit("You are already praying!", "system")
		return
	_praying = PRAY_SECONDS
	if not player.sitting:
		sit(true)
	PlayerData.message.emit("You begin your prayers!", "system")
	SpellFx.emote(8005, player, player.sounds)              # emote Pray (GamePlayer.Pray)


func _pray_tick(delta: float) -> void:
	if _praying <= 0.0:
		return
	if not player.sitting:
		_praying = 0.0                                     # standing up stops the prayer (GamePlayer.Sit)
		return
	_praying -= delta
	if _praying <= 0.0:
		PlayerData.message.emit("You pray at your grave and gain back experience!", "system")
		var back := int(PlayerData.grave.get("xp", 0))
		PlayerData.grave = {}
		show_grave()
		PlayerData.gain_xp(back, false)


func _update_target(st: NpcState) -> void:
	if npcs.target and is_instance_valid(npcs.target) and npcs.target.state == st:
		PlayerData.target["health"] = st.health
		PlayerData.target_changed.emit()


# --- monsters fighting the player ----------------------------------------------------------------------------------

## Threat on a monster (StandardMobBrain.AddToAggroList): it fights whoever has the most - you ("player") or a pet.
func add_aggro(st: NpcState, who: Variant, amount: int) -> void:
	if who is BotFoe and (not (who as BotFoe).alive or int(st.spawn.realm) != 0):
		return                                              # (realm NPCs and gamebots: with the RvR work)
	if not st.alive or ((who is String or (who is NpcState and pets and pets.is_pet(who))) and st.view and (st.view as Npc).is_friendly()):
		return                                              # you and your pets don't fight your realm's NPCs
	st.aggro[who] = maxi(0, int(st.aggro.get(who, 0)) + amount)
	if amount > 0 and (who is String or (who is NpcState and pets and pets.is_pet(who))):
		st.player_hit = true
	if amount > 0 and st.run_speed > 0.0 and _npc_gear(st).has(13):
		st.melee_forced = true                              # an archer hit while aiming switches to melee
	_pick_target(st)
	_engage(st)


## StandardMobBrain.CleanUpAggroListAndGetHighestModifiedThreat: the dead leave its list; anyone over 6000 units away
## is ignored (kept, in case they come back); threat counts in full to 250 units, then fades (a third at 1500 units);
## the highest wins, and on a tie it keeps its current target.
const THREAT_FADE := -0.000878890                        # ln(1/3) / (1500 - 250) per unit


func _pick_target(st: NpcState) -> void:
	var cur: Variant = st.target_pet if st.target_pet else (st.target_bot if st.target_bot else ("player" if st.aggro.has("player") else null))
	var best: Variant = null
	var bv := -1.0
	var cur_v := -1.0
	for k in st.aggro.keys():
		var at: Vector3
		if k is NpcState:
			if not (k as NpcState).alive:
				st.aggro.erase(k)
				continue
			at = (k as NpcState).pos
		elif k is BotFoe:
			if not (k as BotFoe).alive:
				st.aggro.erase(k)
				continue
			at = (k as BotFoe).pos
		else:
			if player == null or PlayerData.hp <= 0:
				continue
			at = player.global_position
		var d := at.distance_to(st.pos) / 0.025
		if d > 6000.0:
			continue
		var v := float(st.aggro[k])
		if d > 250.0:
			v = ceilf(v * exp(THREAT_FADE * (d - 250.0)))
		if is_same(k, cur):
			cur_v = v
		if v > bv:
			bv = v
			best = k
	if best != null and cur != null and not is_same(best, cur) and cur_v >= bv:
		best = cur
	st.target_pet = best if best is NpcState else null
	st.target_bot = best if best is BotFoe else null
	st.no_target = best == null


func _engage(st: NpcState) -> void:
	st.last_combat = Time.get_ticks_msec() / 1000.0          # attacked (hit, missed or resisted) / taking up a fight
	if st.alive and not st.fighting:
		st.melee_forced = false
	if st.alive and player != null and not st.aggro.has("player") and st.target_pet == null and st.target_bot == null:
		st.aggro["player"] = 0
	if st.alive and not st.fighting:
		st.fighting = true
		_fighting[st] = true
		st.stealthed = false                               # StandardMobState_AGGRO.Enter: out of hiding
		st.mode = NpcState.Mode.FIGHT
		st.swing_left = 0.6
		var tn := String(st.target_pet.spawn.name) if st.target_pet else (st.target_bot.name if st.target_bot else PlayerData.display_name())
		var at_you := st.target_pet == null and st.target_bot == null
		npcs.ambient(st, "aggroing", tn, at_you)          # AttackMostWanted with no target yet
		npcs.ambient(st, "fighting", tn, at_you)          # NpcStartAttack


func _monsters(delta: float) -> void:
	var pp := player.global_position if player else Vector3.ZERO
	# a world host zone has no player: only the monsters in a fight have anything to do here (bots' aggro: _bots_tick)
	for s in (npcs.states if player else _fighting.keys()):
		var st: NpcState = s
		if player == null and not st.fighting:
			_fighting.erase(st)
			continue
		if not st.fighting and player != null:
			# nothing below reaches past SIM_RADIUS for a monster not in a fight (aggro reaches 90 m at most, the guard
			# and faction scans SIM_RADIUS): the rest of the region's spawns are passed over before any dictionary read
			# (seamless zones put two to four zones' spawns here - 2,500+ looked up every tick cost ~11 ms)
			var fx := st.pos.x - pp.x
			var fz := st.pos.z - pp.z
			if fx * fx + fz * fz > SIM_RADIUS * SIM_RADIUS:
				continue
		var guard: bool = st.spawn.get("role") == "guard"
		if not st.alive or (int(st.spawn.realm) != 0 and not guard):
			continue
		if not st.fighting and st.returning:
			continue                                        # walking home: it notices nothing on the way
		if not st.fighting and guard:
			st.scan_left -= delta
			if st.scan_left <= 0.0:
				st.scan_left = 2.0                              # GuardBrain.ThinkInterval
				if Vector2(st.pos.x - pp.x, st.pos.z - pp.z).length() < SIM_RADIUS:
					_guard_scan(st)
			continue
		if not st.fighting and player == null:
			continue
		if not st.fighting:
			# an aggressive monster notices the player inside its aggro range (grey cons leave the player alone)
			if int(st.spawn.aggro_level) > 0 and int(st.spawn.aggro_range) > 0 and PlayerData.hp > 0 \
					and not (abilities and abilities.stealthed) and not player.shade and not player.riding:   # hidden / a shade / on a steed
				var d := Vector2(st.pos.x - pp.x, st.pos.z - pp.z).length()
				if d <= mini(int(st.spawn.aggro_range), 3600) * 0.025 and npcs.con_level(PlayerData.level, st.level) > -3 \
						and _faction_aggressive(st) and _sees_player(st):
					_engage(st)
			if not st.fighting and int(st.spawn.aggro_level) > 0 and int(st.spawn.aggro_range) > 0:
				st.scan_left -= delta
				if st.scan_left <= 0.0:
					st.scan_left = 1.5 + randf() * 0.5
					if Vector2(st.pos.x - pp.x, st.pos.z - pp.z).length() < SIM_RADIUS:
						_scan_npc_foes(st)
			continue
		var foe: Variant = _foe_of(st)                     # a pet, another monster or a gamebot; null: you
		if foe == null and not st.aggro.has("player"):
			foe = _next_foe(st)                            # StandardMobBrain: the next on its aggro list ...
			st.target_pet = foe if foe is NpcState else null
			st.target_bot = foe if foe is BotFoe else null
			if foe == null:                                # ... or, with none left, back home
				st.go_home()
				continue
		if foe == null and (player == null or PlayerData.hp <= 0):
			st.go_home()
			continue
		# StandardMobState_AGGRO: 25 s without attacking or being attacked and it leaves the fight (not while it is
		# mezzed, stunned or rooted); its list is looked over again every think
		var now := Time.get_ticks_msec() / 1000.0
		if st.mezzed or st.stunned or st.speed_factor <= 0.01:
			st.last_combat = now
		elif now - st.last_combat > 25.0:
			st.go_home()
			continue
		st.scan_left -= delta
		if st.scan_left <= 0.0:
			st.scan_left = 1.5
			_pick_target(st)
			foe = _foe_of(st)
		if foe == null and st.no_target:
			st.mode = NpcState.Mode.IDLE                   # nobody near enough to count: it waits
			continue
		if st.mezzed or st.stunned:                        # spell effects: no moving, no swinging, no casting
			st.mode = NpcState.Mode.IDLE
			if npc_casting:
				npc_casting.interrupt(st)
			continue
		var foe_at: Vector3 = foe.pos if foe != null else pp
		var to := foe_at - st.pos
		to.y = 0.0
		var dist := to.length()
		if npc_casting and not (foe is BotFoe) and not (st.spawn.get("spells", []) as Array).is_empty():
			npc_casting.ensure_buffs(st)
			if npc_casting.think(st, delta, dist):           # casting (or about to): it stands still, facing you
				st.last_combat = Time.get_ticks_msec() / 1000.0
				st.yaw = lerp_angle(st.yaw, atan2(to.x, to.z), minf(1.0, delta * 8.0))
				st.mode = NpcState.Mode.IDLE
				continue
		var tether := int(st.spawn.get("tether", 0)) * 0.025
		if tether > 0.0 and Vector2(st.pos.x - st.home.x, st.pos.z - st.home.z).length() > tether:
			st.go_home()                                   # beyond its TetherRange from the spawn point: goes home
			continue
		st.yaw = lerp_angle(st.yaw, atan2(to.x, to.z), minf(1.0, delta * 8.0))
		# NpcAttackAction: a monster with a ranged weapon shoots while you are beyond melee range + half a second of its
		# run (and within 2000 units); hit while shooting, it fights in melee
		if (foe == null or foe is BotFoe) and not st.melee_forced and _npc_gear(st).has(13) and dist > REACH + 0.5 * st.run_speed \
				and dist <= 2000.0 * 0.025:
			st.mode = NpcState.Mode.FIGHT
			st.swing_left -= delta
			if st.swing_left <= 0.0:
				st.swing_left = CombatRules.npc_swing_seconds(st.eff(3), "ranged") * st.swing_mult * _npc_haste(st)
				st.last_combat = Time.get_ticks_msec() / 1000.0
				if st.view:
					(st.view as Npc).play_attack()
				_npc_arrows.append([dist / 0.025 / PROJECTILE_UNITS + 0.3, st, foe])
			continue
		var reach := REACH
		if dist > reach * 0.8:
			st.pos += to / dist * minf(dist - reach * 0.7, st.run_speed * st.speed_mult() * delta)
			st.pos.y = npcs.ground_at(st.pos)
			st.mode = NpcState.Mode.WALK
			continue
		st.mode = NpcState.Mode.FIGHT
		st.swing_left -= delta
		if st.swing_left <= 0.0:
			st.swing_left = CombatRules.npc_swing_seconds(st.eff(3), _npc_weapon(st)) * st.swing_mult * _npc_haste(st)
			st.last_combat = Time.get_ticks_msec() / 1000.0
			var t := 0.3
			if st.view:
				t = (st.view as Npc).play_attack() * HIT_AT
				if (st.view as Npc).sounds:
					(st.view as Npc).sounds.event("attack")    # cc_creatures 'attack vocal' (no weapon)
			_pending.append([t, st, "npc_bot" if foe is BotFoe else ("npc_pet" if foe else "npc"), foe])


## WeaponAction / CalculateLeftHandSwingCount: a monster whose template has a LeftHandSwingChance, holding a
## one-hander in its right hand and a weapon in its left, follows a swing with a full off-hand attack (no style) that
## % of the time. (Such monsters never block - their left item is a weapon.)
func _npc_offhand(st: NpcState) -> bool:
	if not st.alive or not st.fighting:
		return false
	var chance := int((st.spawn.get("defense", [0, 0, 0, 0]) as Array)[3])
	if chance <= 0:
		return false
	var g := _npc_gear(st)
	if not (g.has(10) and g.has(11)) or _npc_weapon(st) != "one_hand":
		return false
	return randf() * 100.0 < chance


## A monster's swing time (s): AttackComponent passes it as the interrupt timer's length.
func _npc_interval(st: NpcState) -> float:
	return CombatRules.npc_swing_seconds(st.eff(3), _npc_weapon(st)) * st.swing_mult * _npc_haste(st)


func _npc_blow(st: NpcState, offhand := false) -> void:
	if not st.alive or not st.fighting or PlayerData.hp <= 0:
		return
	var who := _cap(_the(st))
	_last_attack = Time.get_ticks_msec() / 1000.0
	if _ranged != "":
		PlayerData.message.emit("%s is attacking you and your shot is interrupted!" % who, "damage_taken")
		_stop_ranged()
	if pets:
		pets.owner_attacked(st)
	if abilities:
		abilities.break_stealth()
	var style := {} if offhand else _npc_style_to_use(st)
	var style_ok := not style.is_empty() and _npc_style_ok(st, style)    # judged before this swing resets its result
	st.swing_style = {}
	st.last_swing_on = "player"
	var defended := _player_defends(st)
	if defended != "":
		target_last_result = defended
		st.swing_result = defended
		PlayerData.message.emit("%s attacks you and you %s the blow!" % [who, defended], "damage_taken")
		player.defend(defended)
		if casting:
			casting.on_attacked(who, st.level, _npc_interval(st))   # StartInterruptTimer runs for every result
		if player.sounds:
			if defended == "evade":
				player.sounds.event("evade")
			else:
				player.sounds.weapon(WEAPONLESS, "parried" if defended == "parry" else "blocked")
		return
	var slot := _hit_location()                            # set before the miss roll (CalculateArmorHitLocation)
	if MeleeMath.npc_misses(st, {"sheet": PlayerData, "sitting": player.sitting, "last_result": last_result,
			"last_style": last_style}, style, slot):
		PlayerData.message.emit("%s attacks you and misses!" % who, "damage_taken")
		target_last_result = "miss"
		st.swing_result = "miss"
		if casting:
			casting.on_attacked(who, st.level, _npc_interval(st))   # a swing interrupts a spell, hit or miss
		return
	if casting and casting.player_bladeturn(st.level):
		target_last_result = "hit"
		st.swing_result = "hit"
		casting.on_attacked(who, st.level, _npc_interval(st))
		return
	target_last_result = "hit"
	st.swing_result = "hit"
	PlayerData.wear_item(slot)                             # the piece struck loses condition (old server)
	# AttackComponent (MeleeMath, shared with the gamebots): base x skill / armour; the style works on that; its melee
	# damage debuff, then resists (the difference shows as "(-N)"), then the 3 x base cap; the style's damage on top
	var r := MeleeMath.npc_damage(st, PlayerData, slot, style, style_ok, _npc_weapon(st), _npc_interval(st))
	var where: String = r.where
	var dmg: int = r.dmg
	if style_ok:
		if st.view and is_instance_valid(st.view):
			StyleTrail.play_from_impact(player.get_parent(), (st.view as Npc).model, style)
		st.swing_result = "style"
		st.swing_style = style
	if casting:
		dmg = casting.player_ablative(dmg)
	var mod: int = r.modifier
	PlayerData.message.emit("%s hits your %s for %d%s damage!" % [who, where, dmg,
			(" (+%d)" % mod) if mod > 0 else ((" (%d)" % mod) if mod < 0 else "")], "damage_taken")
	var heavy := dmg >= PlayerData.max_hp * 0.1
	PlayerData.set_hp(PlayerData.hp - dmg)
	if casting:
		casting.break_player_mez()                         # damage wakes a mesmerized player
	if PlayerData.hp > 0 and st.swing_result == "style":
		_npc_style_procs(st, st.swing_style)
	if PlayerData.hp > 0:
		_damage_shields(st)
		_npc_hit_extras(st)
		if casting:
			casting.player_procs("defensive", st)
	player.flinch()
	if casting:
		casting.on_attacked(who, st.level, _npc_interval(st))
	if player.sounds:
		var styled_hit := st.swing_result == "style"         # a monster's style lands: the heavy style hit and cry
		player.sounds.weapon(WEAPONLESS, "style_hit" if styled_hit else ("hit_medium" if heavy else "hit_light"))
		if PlayerData.hp > 0:
			player.sounds.event("pain_heavy" if styled_hit else ("pain_medium" if heavy else "pain_light"))
	if PlayerData.hp <= 0:
		_player_died()
		npcs.ambient(st, "killing", PlayerData.display_name(), true)   # GamePlayer.Die: the killer's line
		killed_by.emit(String(st.spawn.name))


## Where a blow lands and what is worn there, the old server's way (GamePlayer.CalculateArmorHitLocation /
## GetArmorAF / GetArmorAbsorb): torso 40%, legs 25%, arms 15%, head 10%, hands 5%, feet 5%; the piece's AF capped at
## the level (cloth) or twice the level (other armour), times quality and condition; absorb = the piece's ABS %.
func _hit_location() -> int:
	return MeleeMath.hit_location()


func _worn_armor(slot := -1) -> Array:
	if slot < 0:
		slot = _hit_location()
	PlayerData.wear_item(slot)                             # the piece struck loses condition (old server)
	return MeleeMath.armor(PlayerData, slot)


func _player_died() -> void:
	set_attack_mode(false)
	if pets:
		pets.release_all()
	PlayerData.message.emit("You have died.  Type /release to return to your last bindpoint.", "system")
	if player.sounds:
		player.sounds.event("die")
	_death_loss = PlayerData.death_xp_loss()
	_death_pos = player.global_position
	_death_yaw = player.facing()
	_dead_for = 0.0
	_auto_release = false
	_release_warned = 0
	_praying = 0.0
	if abilities and abilities.sprinting:
		abilities.toggle_sprint()
	player.die()
	if casting:
		casting.clear_on_death()                           # every effect ends at death
	player_died.emit()
	for s in npcs.states:
		if (s as NpcState).fighting and not (pets and pets.is_pet(s)):
			(s as NpcState).go_home()


func _impacts(delta: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		_pending[i][0] -= delta
		if _pending[i][0] <= 0.0:
			var p: Array = _pending[i]
			_pending.remove_at(i)
			if p[2] == "player":
				_player_blow(p[1], p[3] if p.size() > 3 else {})
			elif p[2] == "npc_bot":
				var hits := 2 if _npc_offhand(p[1]) else 1
				for _h in hits:
					_npc_hits_bot(p[1], p[3])
			elif p[2] == "npc_pet":
				var hits := 2 if _npc_offhand(p[1]) else 1
				for _h in hits:
					if pets and pets.is_pet(p[3]):
						pets.npc_hits_pet(p[1], p[3])
					elif p[3] is NpcState:
						_npc_hits_npc(p[1], p[3])
			else:
				_npc_blow(p[1])
				if _npc_offhand(p[1]):
					var keep := [p[1].swing_result, p[1].swing_style, target_last_result]
					_npc_blow(p[1], true)                     # only the main hand's attack is its "last attack"
					p[1].swing_result = keep[0]
					p[1].swing_style = keep[1]
					target_last_result = keep[2]


func in_combat() -> bool:
	if Time.get_ticks_msec() / 1000.0 - _last_attack < 10.0:
		return true
	for s in npcs.states:
		if (s as NpcState).fighting:
			return true
	return false


## The old server's regeneration (ClassicRestRegeneration / HealthRegenerationAmountCalculator): hit points
## 2.5 + level x 0.25 a tick, a tick every 6 s standing, 14 s in combat; endurance 1 a second standing still out of
## combat, none while moving or fighting (sitting comes with /sit).
func _regen_ticks(delta: float) -> void:
	if PlayerData.hp <= 0:
		return
	var fighting := in_combat()
	_regen += delta
	if _regen >= PlayerData.regen_interval(player.sitting, fighting):     # CharacterState: the shared rules
		_regen = 0.0
		PlayerData.regen_tick()
	_end_tick += delta
	if _end_tick >= 1.0:
		_end_tick = 0.0
		PlayerData.endurance_tick(player.velocity.length() > 0.2, player.sitting, fighting)


func _spend_endurance(n: int) -> void:
	PlayerData.spend_endurance(n)
	PlayerData.changed.emit()


# --- combat styles (old server StyleProcessor) ----------------------------------------------------------------------

## A quickbar / list style: queued for the next swing ("You prepare to perform a <style>!"), a second one as its
## backup; the same style again is already being prepared. Attack mode starts if it isn't on.
func _use_skill(e: Dictionary) -> void:
	if String(e.get("kind", "")) != "style":
		return
	var style := ClassDb.style(int(e.get("id", 0)))
	if style.is_empty() or PlayerData.hp <= 0:
		return
	if PlayerData.active_weapon == "ranged":
		PlayerData.message.emit("You can't enter melee combat mode with a fired weapon!", "combat")
		return
	if npcs.target == null:
		PlayerData.message.emit("You must have a target for your next attack style!", "combat")
		return
	if not attack_mode:
		set_attack_mode(true)
	var w := _weapon()
	if not _weapon_fits(style, w):
		PlayerData.message.emit("This style requires a %s weapon!" % String(ClassDb.spec(String(style.speckeyname)).get("name", "")).to_lower(), "combat")
		return
	if PlayerData.end_pts < CombatRules.style_endurance(style, int(w.get("spd_abs", 30))):
		PlayerData.message.emit("You are too fatigued to use this style!", "combat")
		return
	var chain := int(style.get("openingrequirementtype", 0)) == 0 and int(style.get("openingrequirementvalue", 0)) != 0
	if chain and (last_result != "style" or last_style_id != int(style.openingrequirementvalue)):
		var pre := ClassDb.style_by_game_id(int(style.openingrequirementvalue), PlayerData.class_id())
		PlayerData.message.emit("You must perform the %s style before this one!" % String(pre.get("name", "")), "combat")
		return
	if next_style.is_empty():
		next_style = style
		PlayerData.message.emit("You prepare to perform a %s!" % String(style.name), "combat")
		if abilities and not bool(style.get("stealthrequirement", false)):
			abilities.break_stealth()                           # a primary style that isn't an opener brings you out
	elif int(next_style.styleid) == int(style.styleid):
		PlayerData.message.emit("You are already preparing to use this style! Type '/cancelstyle' to enable style cancelling.", "combat")
	elif backup_style.is_empty():
		backup_style = style
		PlayerData.message.emit("You are now preparing to perform a %s style as a backup for %s!" % [String(style.name), String(next_style.name)], "combat")
	else:
		PlayerData.message.emit("You have already selected your styles for this round!", "combat")


func _weapon_fits(style: Dictionary, w: Dictionary) -> bool:
	var req := int(style.get("weapontyperequirement", 0))
	if w.is_empty():
		return false
	if req == 1001 or req == 0:                            # any weapon
		return true
	if req == 1000:                                        # dual wield: a weapon in each hand
		var left := PlayerData.item_at(11)
		return not left.is_empty() and int(left.get("object_type", 0)) != ItemDb.SHIELD_TYPE
	if req == ItemDb.SHIELD_TYPE:
		return int(PlayerData.item_at(11).get("object_type", 0)) == ItemDb.SHIELD_TYPE
	return req == int(w.get("object_type", 0))


## The style's opening (CanUseStyle) at the moment the blow lands: a follow-up needs its style to have just landed;
## a reactive style needs the monster's last swing at you to have had that result; a positional one needs you at
## the monster's back (150-210 deg), side (45-150 / 210-315) or front (< 45 / > 315).
## Seconds between the player's swings: weapon speed x (1 - (QUI - 60) x 0.002) x melee speed (haste buffs).
func _player_swing_seconds(w: Dictionary) -> float:
	return MeleeMath.swing_seconds(PlayerData, w)


## Damage adds on a landed hit (DamageAddSpellHandler): damage per second x the swing's seconds x 0.75..1.25 x the
## buff's effectiveness, no more than the swing's unstyled cap. "You hit X for N extra damage!"
func _damage_adds(st: NpcState, w: Dictionary, cap: float) -> void:
	for da in PlayerData.buffs.get("da", []):
		var d := int(minf(float(da[0]) * _player_swing_seconds(w) * randf_range(0.75, 1.25) * float(da[1]), cap))
		if d <= 0 or not st.alive:
			continue
		PlayerData.message.emit("You hit %s for %d extra damage!" % [_the(st), d], "combat")
		st.damage(d)
		if not st.alive:
			_killed(st)


## Damage shields when a monster's blow lands (DamageShieldSpellHandler): damage per second x the monster's swing
## seconds x 0.75..1.25 x effectiveness, no more than its unstyled cap. "You hit X for N damage!"
func _damage_shields(st: NpcState) -> void:
	for ds in PlayerData.buffs.get("ds", []):
		var secs := CombatRules.npc_swing_seconds(st.eff(3), _npc_weapon(st)) * st.swing_mult
		var d := int(minf(float(ds[0]) * secs * randf_range(0.75, 1.25) * float(ds[1]), CombatRules.npc_damage_cap(st.level)))
		if d <= 0 or not st.alive:
			continue
		PlayerData.message.emit("You hit %s for %d damage!" % [_the(st), d], "combat")
		st.damage(d)
		if not st.alive:
			_killed(st)
		_update_target(st)


## A monster's haste buffs (CombatSpeedBuff): its swings come faster.
func _npc_haste(st: NpcState) -> float:
	var h := 1.0
	for sp in st.npc_buffs:
		if String(sp.get("type", "")) == "CombatSpeedBuff":
			h = minf(h, 1.0 - float(sp.get("value", 0)) / 100.0)
	return maxf(0.1, h)


## After a monster's blow lands on the player: its damage adds and its offensive procs (Frequency / 100 % chance to
## cast the proc spell, OffensiveProcSpellHandler).
func _npc_hit_extras(st: NpcState) -> void:
	for sp in st.npc_buffs:
		match String(sp.get("type", "")):
			"DamageAdd":
				var secs := CombatRules.npc_swing_seconds(st.eff(3), _npc_weapon(st)) * st.swing_mult
				var d := int(float(sp.get("damage", 0)) * secs * randf_range(0.75, 1.25))
				if d > 0:
					PlayerData.message.emit("%s does %d extra damage to you!" % [_cap(_the(st)), d], "damage_taken")
					PlayerData.set_hp(PlayerData.hp - d)
			"OffensiveProc":
				if randf() * 100.0 < float(sp.get("frequency", 0)) / 100.0 and casting:
					# BaseProcSpellHandler: a monster's proc spell is scaled by its level / 50
					var proc := NpcCasting.scaled(NpcCasting.spell(int(sp.get("value", 0))), st.level / 50.0)
					if not proc.is_empty():
						casting.apply_to_player(proc, st, 30 + st.level - 1)
	if PlayerData.hp <= 0 and not player.dead:
		_player_died()
		killed_by.emit(String(st.spawn.name))


## The player's blow on a monster with a damage shield: it hurts back (DamageShieldSpellHandler, the player's swing).
func _npc_damage_shields(st: NpcState) -> void:
	for sp in st.npc_buffs:
		if String(sp.get("type", "")) == "DamageShield":
			var d := int(float(sp.get("damage", 0)) * _player_swing_seconds(_weapon()) * randf_range(0.75, 1.25))
			if d > 0:
				PlayerData.message.emit("%s does %d extra damage to you!" % [_cap(_the(st)), d], "damage_taken")
				PlayerData.set_hp(PlayerData.hp - d)
				if PlayerData.hp <= 0 and not player.dead:
					_player_died()
					killed_by.emit(String(st.spawn.name))


## A landed style's procs (StyleXSpell): the player's own class proc if the style has one, else the procs for the
## style's class or any class, each at its chance; a random-proc style fires one of them at random.
func _style_procs(style: Dictionary, st: NpcState) -> void:
	var procs: Array = style.get("procs", [])
	if procs.is_empty() or casting == null:
		return
	var fire := []
	if int(style.get("randomproc", 0)) != 0:
		fire = [procs[randi() % procs.size()]]
		fire[0] = fire[0].merged({"chance": 100}, true)
	else:
		var mine := procs.filter(func(p): return int(p["class"]) == PlayerData.class_id())
		fire = mine if not mine.is_empty() else procs.filter(func(p): return int(p["class"]) == int(style.get("classid", 0)) or int(p["class"]) == 0)
	for p in fire:
		if randf() * 100.0 < float(p.get("chance", 100)):
			casting.apply_proc(ClassDb.spell(int(p.spell)), st)


# --- ranged: old archery (AttackComponent / RangeAttackComponent, ALLOW_OLD_ARCHERY) -------------------------------
## The attack key with the bow (ranged weapon set) out: the first press draws ("You prepare your shot (2.3s to fire,
## target is in range)"), the draw takes the bow's speed x (1 - (QUI - 60) x 0.002) - never under 1.5 s - then "You are
## ready to fire!"; the next press fires an arrow from the backpack (5 endurance) at the target. Moving or being
## attacked interrupts the draw; holding it past 15 s: "You are too tired to hold your shot any longer!". The arrow
## flies at 1800 units a second; its head sets the damage (blunt 0.85 / bodkin 1 / broadhead 1.25), its fletching the
## range (clout -15% / flight +25%) and its shaft the accuracy (rough: misses +15%, footed -25%).

const PROJECTILE_UNITS := 1800.0
const MAX_DRAW := 15.0
const BOW_RANGE := {9: 1760, 18: 1680, 15: 1600}         # longbow / recurve / composite (units)
var _ranged := ""                                        # "", "drawing", "ready"
var _draw_left := 0.0
var _draw_held := 0.0
var _arrows: Array = []                                  # in flight: [seconds left, NpcState, bow, ammo]


func _arrow_slot() -> int:
	for s in range(PlayerData.BACKPACK, PlayerData.BACKPACK_END + 1):
		var it := PlayerData.item_at(s)
		if not it.is_empty() and int(it.get("object_type", 0)) == 43:
			return s
	return -1


## The bow's reach in metres (AttackComponent.AttackRange): its type, the arrow's fletching, height over the target.
func _bow_range(bow: Dictionary, ammo: Dictionary, st: NpcState) -> float:
	var r := float(BOW_RANGE.get(int(bow.get("object_type", 0)), 1200)) * (casting.nearsight_mult() if casting else 1.0)
	match (int(ammo.get("spd_abs", 0)) >> 2) & 3:
		0: r *= 0.85
		3: r *= 1.25
	if st:
		r += (player.global_position.y - st.pos.y) / 0.025 / 2.0
	return maxf(32.0, r) * 0.025


var shot_type := ""                           # "critical" for the next shot (Critical Shot)
var rapid_fire_on := false
var _draw_normal := 0.0                       # the draw time without Rapid Fire (its damage share)
var _draw_total := 0.0


func ranged_attack() -> void:
	if player.dead or PlayerData.hp <= 0:
		return
	if _ranged == "ready":
		_fire()
		return
	if _ranged == "drawing":
		return
	var bow := PlayerData.item_at(13)
	if bow.is_empty():
		PlayerData.message.emit("You cannot enter combat mode without a weapon!", "combat")
		return
	var slot := _arrow_slot()
	if slot < 0:
		PlayerData.message.emit("You must select a quiver slot to draw from!", "combat")
		return
	if shot_type == "critical" and PlayerData.end_pts < 10:
		PlayerData.message.emit("You're too tired to perform a critical shot!", "combat")
		shot_type = ""
		return
	if PlayerData.end_pts < 5:
		PlayerData.message.emit("You're too tired to use your %s!" % String(bow.get("name", "bow")), "combat")
		return
	if player.sitting:
		sit(false)
	var t := CombatRules.player_swing_seconds(bow, int(PlayerData.effective_stats()[3]))
	_draw_normal = t
	if shot_type == "critical":
		t = t * 2.0 - (_ability_level("Critical Shot") - 1) * t / 10.0
	elif rapid_fire_on:
		t = maxf(0.9, t * 0.5)
	_draw_total = t
	# nocking an arrow hidden: you stay hidden with chance stealth spec x 100 / level (-20 for a critical shot)
	if abilities and abilities.stealthed:
		var stay := int(PlayerData.specs.get("Stealth", 1)) * 100 / maxi(1, PlayerData.level) - (20 if shot_type == "critical" else 0)
		if randi() % 100 >= stay:
			abilities.break_stealth()
	var target_msg := ""
	var tv: Npc = npcs.target
	if tv and is_instance_valid(tv):
		var in_range: bool = tv.global_position.distance_to(player.global_position) <= _bow_range(bow, PlayerData.item_at(slot), tv.state)
		target_msg = ", target is in range" if in_range else ", target is out of range"
	var tenths := int(t * 10.0)
	PlayerData.message.emit("You prepare your shot (%d.%ds to fire%s)" % [tenths / 10, tenths % 10, target_msg], "combat")
	_ranged = "drawing"
	_draw_left = t
	_draw_held = 0.0
	player.set_combat(true, WeaponModels.ranged_kind(int(bow.get("model", 0))))   # bow / crossbow / thrown clips
	player.bow_draw()


func _stop_ranged() -> void:
	_ranged = ""
	player.bow_release(false)


func _ranged_tick(delta: float) -> void:
	for i in range(_arrows.size() - 1, -1, -1):
		_arrows[i][0] -= delta
		if _arrows[i][0] <= 0.0:
			var a: Array = _arrows[i]
			_arrows.remove_at(i)
			_arrow_lands(a[1], a[2], a[3], float(a[4]) if a.size() > 4 else 1.0, bool(a[5]) if a.size() > 5 else false)
	if _ranged == "":
		return
	if player.dead:
		_stop_ranged()
		return
	if player.velocity.length() > 0.2:
		PlayerData.message.emit("You move and interrupt your shot!", "combat")
		_stop_ranged()
		return
	_draw_held += delta
	if _draw_held > MAX_DRAW:
		PlayerData.message.emit("You are too tired to hold your shot any longer!", "combat")
		_stop_ranged()
		return
	if _ranged == "drawing":
		_draw_left -= delta
		if _draw_left <= 0.0:
			_ranged = "ready"
			PlayerData.message.emit("You are ready to fire!", "combat")


func _fire() -> void:
	if abilities:
		abilities.break_stealth()
	var tv: Npc = npcs.target
	if tv == null or not is_instance_valid(tv) or not tv.state.alive:
		PlayerData.message.emit("You must select a target for this ability!", "combat")
		return
	var st := tv.state
	var bow := PlayerData.item_at(13)
	var slot := _arrow_slot()
	if slot < 0:
		PlayerData.message.emit("You must select a quiver slot to draw from!", "combat")
		_stop_ranged()
		return
	var ammo := PlayerData.item_at(slot)
	var to := st.pos - player.global_position
	if to.length() > _bow_range(bow, ammo, st):
		PlayerData.message.emit("%s is too far away to attack!" % _cap(_the(st)), "combat")
		return
	var flat := Vector2(to.x, to.z)
	var fwd := Vector2(-sin(player.facing()), -cos(player.facing()))
	if flat.length() > 0.3 and rad_to_deg(absf(fwd.angle_to(flat))) > 45.0:   # IsObjectInFront(target, 90)
		PlayerData.message.emit("%s is not in view!" % _cap(_the(st)), "combat")
		return
	var q := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 1.6, 0), st.pos + Vector3(0, 1.0, 0), ZoneLoader.LAYER_WALL)
	if not player.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
		PlayerData.message.emit("You can't see your target!", "combat")
		return
	PlayerData.take_one(slot)
	var eff := 1.0
	var crit_shot := shot_type == "critical"
	if crit_shot:
		_spend_endurance(10)
		eff = clampf(2.0 + (PlayerData.level - st.level) * 0.075, 1.1, 2.0)
		shot_type = ""
	elif rapid_fire_on:
		_spend_endurance(3 if _ability_level("Rapid Fire") >= 2 else 5)
		var used := _draw_held                              # seconds since the draw began
		eff = minf(1.0, used / maxf(0.01, _draw_normal))
	else:
		_spend_endurance(5)
	_ranged = ""
	player.bow_release(true)
	_weapon_sound(player.sounds, "use")
	_last_attack = Time.get_ticks_msec() / 1000.0
	_arrows.append([to.length() / 0.025 / PROJECTILE_UNITS, st, bow, ammo, eff, crit_shot])


func _arrow_lands(st: NpcState, bow: Dictionary, ammo: Dictionary, eff := 1.0, crit_shot := false) -> void:
	if not st.alive:
		return
	var who := _the(st)
	_engage(st)
	var miss := CombatRules.miss_chance(PlayerData.level, st.level, _style_miss_adjust({}, st.swing_result, st.swing_style),
			-mini(int(bow.get("bonus", 0)), CombatRules.bonus_cap(PlayerData.level)))
	match (int(ammo.get("spd_abs", 0)) >> 4) & 3:
		0: miss += miss * 0.15                             # rough shafts
		3: miss -= miss * 0.25                             # footed
	# monsters' defences against arrows: evade a fifth as often, block +25% (GameLiving.TryEvade / CalculateBaseBlockChance)
	var d: Array = st.spawn.get("defense", [0, 0, 0, 0])
	if not (st.mezzed or st.stunned):
		if int(d[0]) > 0 and _in_front_of_npc(st, 180.0) and randf() < int(d[0]) * 10 * 0.001 / 5.0:
			PlayerData.message.emit("%s evades your attack!" % _cap(who), "combat")
			return
		var gear := _npc_gear(st)
		if gear.has(11) and not gear.has(12) and int(d[3]) <= 0 and _in_front_of_npc(st, 120.0) and randf() < int(d[2]) * 10 / 1000.0 + 0.25:
			PlayerData.message.emit("%s blocks your attack!" % _cap(who), "combat")
			return
	if randf() < miss:
		PlayerData.message.emit("You miss!", "combat")
		return
	var spec := int(PlayerData.specs.get(CombatRules.weapon_spec_key(bow), 1))
	var ammo_mod: float = [0.85, 1.0, 1.15, 1.25][int(ammo.get("spd_abs", 0)) & 3]
	var parts := CombatRules.player_damage_parts(bow, PlayerData.level, PlayerData.class_id(), PlayerData.effective_stats(), spec, st.level, ammo_mod, st.af_bonus - st.af_debuff, st.absorb())
	parts[0] *= eff                                         # Critical Shot / Rapid Fire effectiveness
	parts[1] *= eff
	var adt := int(ammo.get("type_damage", 0))                # the arrow's damage type, else the bow's
	var rmod := 1.0 - st.resist(adt if adt > 0 else int(bow.get("type_damage", 3))) * 0.01
	var dmg := maxi(1, int(minf(parts[0] * rmod, parts[1])))
	var mod := floori(parts[0] * rmod - parts[0])
	PlayerData.message.emit("You shoot %s with your %s and hit for %d%s damage!" % [who, String(bow.get("name", "bow")).split(" ")[-1], dmg,
			(" (+%d)" % mod) if mod > 0 else ((" (%d)" % mod) if mod < 0 else "")], "combat")
	if not crit_shot and randf() * 100.0 < CRIT_CHANCE:       # CriticalArcheryHitChance 10 (none on a critical shot)
		var crit := int(dmg * randf_range(0.1, 1.0))
		if crit > 0:
			PlayerData.message.emit("You critical hit %s for an additional %d damage! (%d%%)" % [who, crit, int(CRIT_CHANCE)], "combat")
			dmg += crit
	PlayerData.wear_item(13)
	st.damage(dmg)
	if st.view:
		(st.view as Npc).flinch()
		if (st.view as Npc).sounds and st.alive:
			(st.view as Npc).sounds.event("pain_light")
	if not st.alive:
		_killed(st)
	_update_target(st)


## Fall damage (PlayerPositionUpdateHandler / GamePlayer.CalcFallDamage): fall speed less 100 per Safe Fall level; over
## 500 units / s you take min(99, (speed - 501) / 15) % of your max health (less 1) and of your endurance.
func _landed(fall_speed: float) -> void:
	if player.dead or PlayerData.hp <= 0:
		return
	var safe := _ability_level("Safe Fall")
	var speed := fall_speed - 100.0 * safe
	if speed <= 500.0:
		return
	var pct := mini(99, int((speed - 501.0) / 15.0))
	if pct <= 0:
		return
	if safe > 0:
		PlayerData.message.emit("The damage was lessened by your Safe Fall ability!", "damage_taken")
	_spend_endurance(PlayerData.MAX_END * pct / 100)
	var dmg := int(0.01 * pct * (PlayerData.max_hp - 1))
	PlayerData.message.emit("You take falling damage!", "damage_taken")
	PlayerData.message.emit("You take %d%% of your max hits in damage." % pct, "damage_taken")
	PlayerData.message.emit("You lose endurance.", "damage_taken")
	PlayerData.set_hp(PlayerData.hp - dmg)
	if PlayerData.hp <= 0:
		_player_died()


## A known ability's level (ClassDb.abilities_known), 0 when not known.
func _ability_level(key: String) -> int:
	for a in ClassDb.abilities_known(PlayerData.class_id(), PlayerData.level, PlayerData.specs):
		if String(a.key) == key:
			return int(a.level)
	return 0


## Critical Shot (CriticalShotAbilityHandler): the next shot draws twice as long less (level - 1) tenths, costs 10
## endurance, can't crit normally but hits x clamp(2 + (your level - its level) x 0.075, 1.1, 2). Used while drawing it
## turns back into a regular shot. Starts the draw.
func critical_shot() -> void:
	if PlayerData.active_weapon != "ranged":
		PlayerData.message.emit("You must ready a ranged weapon in your hands!", "combat")
		return
	if player.sitting:
		PlayerData.message.emit("You must be standing to attempt a ranged attack!", "combat")
		return
	rapid_fire_on = false
	if _ranged != "":
		if shot_type == "critical":
			PlayerData.message.emit("You switch to a regular shot!", "combat")
			shot_type = ""
		else:
			PlayerData.message.emit("You are already firing this weapon!", "combat")
		return
	shot_type = "critical"
	ranged_attack()


## Rapid Fire (RapidFireAbilityHandler): toggled; draws take half as long (at least 0.9 s), a shot does the share of
## the normal draw it took; at ability level 2 half the endurance.
func rapid_fire() -> void:
	if rapid_fire_on:
		rapid_fire_on = false
		return
	if player.dead:
		PlayerData.message.emit("You can't switch to rapid fire when dead!", "combat")
		return
	rapid_fire_on = true
	PlayerData.message.emit("You switch to rapid fire mode!", "combat")


## The style this swing uses (PlayerStyleComponent.GetStyleToUse): the queued one if its opening holds, else the
## backup, else the queued one anyway (its opening then fails: "You fail to execute ... perfectly!").
func _style_to_use(st: NpcState) -> Dictionary:
	if next_style.is_empty():
		return {}
	if _style_ok(next_style, st):
		return next_style
	return backup_style if not backup_style.is_empty() else next_style


# --- defence ---------------------------------------------------------------------------------------------------------

## Whether a point is inside the player's frontal arc (GameObject.IsObjectInFront: arc degrees wide).
func _in_front_of_player(at: Vector3, arc: float) -> bool:
	var to := Vector2(at.x - player.global_position.x, at.z - player.global_position.z)
	if to.length() < 0.01:
		return true
	var fwd := Vector2(-sin(player.facing()), -cos(player.facing()))
	return rad_to_deg(absf(fwd.angle_to(to))) < arc / 2.0


## ...and inside a monster's.
func _npc_arrows_tick(delta: float) -> void:
	for i in range(_npc_arrows.size() - 1, -1, -1):
		_npc_arrows[i][0] -= delta
		if _npc_arrows[i][0] <= 0.0:
			var a: Array = _npc_arrows[i]
			_npc_arrows.remove_at(i)
			var archer: NpcState = a[1]
			if archer.alive and archer.fighting:
				_ranged_blow = true
				if a.size() > 2 and a[2] is BotFoe:
					_npc_hits_bot(archer, a[2])
				elif player != null:
					_npc_blow(archer)
				_ranged_blow = false


func _in_front_of_npc(st: NpcState, arc: float) -> bool:
	var to := Vector2(player.global_position.x - st.pos.x, player.global_position.z - st.pos.z)
	if to.length() < 0.01:
		return true
	var fwd := Vector2(sin(st.yaw), cos(st.yaw))
	return rad_to_deg(absf(fwd.angle_to(to))) < arc / 2.0


## Monsters fighting the player in melee (the old server's AttackerTracker.MeleeCount): parry is shared out among
## them, and a shield covers as many as its size.
func _melee_attackers() -> int:
	var n := 0
	for s in npcs.states:
		var st: NpcState = s
		if st.alive and st.fighting and st.pos.distance_to(player.global_position) < REACH + 3.0:
			n += 1
	return maxi(n, 1)


## The player's trained level in a spec the class has (0 when it hasn't).
func _spec_level(key: String) -> int:
	return MeleeMath.spec_level(PlayerData, key)


## A monster's swing at the player: "evade", "parry", "block" or "" (GameLiving.TryEvade / TryParry / TryBlock).
## Nothing while sitting or casting; evade needs the Evade ability (front 180 degrees), parry the Parry spec and a melee
## weapon (front 120, shared among the attackers, halved against a two-hander), block the Shield ability and a shield
## with a one-hand weapon set (front 120, times the shield's quality and condition, its size = attackers covered).
func _player_defends(st: NpcState) -> String:
	if player.sitting or player.dead or (casting and not casting.casting.is_empty()):
		return ""
	return MeleeMath.character_defends(st, {"sheet": PlayerData, "pos": player.global_position,
			"fwd": MeleeMath.char_fwd(player.facing()), "berserk": abilities != null and abilities.berserk_left > 0.0,
			"stats": casting.effective_stats() if casting else PlayerData.stats, "attackers": _melee_attackers(),
			"evade_buff": (casting.player_buff("SavageStyleEvadeBuff") + casting.player_buff("SavageEvadeBuff")) if casting else 0.0,
			"parry_buff": (casting.player_buff("SavageStyleParryBuff") + casting.player_buff("SavageParryBuff")) if casting else 0.0,
			"arrow": _ranged_blow, "engage": _engage_block.bind(st)}, _npc_gear(st).has(12))


## Engage on this monster (nobody hit it for 5 s): +65% base block chance, 5 endurance a block (too little ends it).
func _engage_block(st: NpcState) -> float:
	if abilities and abilities.engaged == st and Time.get_ticks_msec() / 1000.0 - st.hit_at >= 5.0:
		if PlayerData.end_pts < 5:
			abilities.end_engage()
			return 0.0
		_spend_endurance(5)
		PlayerData.message.emit("You concentrate on blocking the blow!", "combat")
		return 0.65
	return 0.0


## The player's swing at a monster: its template evade / parry / block (MeleeMath.npc_defends).
func _npc_defends(st: NpcState, w: Dictionary) -> String:
	return MeleeMath.npc_defends(st, PlayerData, w, player.global_position, _npc_gear(st))


## The kind of weapon a monster swings (its equipment): a two-hander only (slot 12, no right hand) is "two_hand".
## GameNPC.InitializeActiveWeaponFromInventory: a two-hander and a one-hander -> one of them, 50/50, per spawn.
func _npc_weapon(st: NpcState) -> String:
	if _ranged_blow:
		return "ranged"
	if st.weapon_pick == "":
		var g := _npc_gear(st)
		if g.has(12) and g.has(10):
			st.weapon_pick = "two_hand" if randf() < 0.5 else "one_hand"
		else:
			st.weapon_pick = "two_hand" if g.has(12) else "one_hand"
	return st.weapon_pick


## GetMissChance's style terms (percent): - the attacker's style BonusToHit + the defender's last landed style's
## BonusToDefense (negative in the data: a style that leaves you open).
func _style_miss_adjust(style: Dictionary, defender_result: String, defender_style: Dictionary) -> float:
	var a := 0.0
	if not style.is_empty():
		a -= float(style.get("bonustohit", 0))
	if defender_result == "style" and not defender_style.is_empty():
		a += float(defender_style.get("bonustodefense", 0))
	return a


## A monster's styles (its template's, build_npcs.py) - NpcStyleComponent.GetStyleToUse / GameNPC.SortStyles: a chain
## follow-up whose opener just landed, else a defensive style its opening allows (not a stun style while you are
## still stunned by it), else on 20% of swings (gamenpc_chances_to_style) one random back, side or front style if its
## position fits, else a random anytime style.
func _npc_style_to_use(st: NpcState, tgt: Variant = "player", rows: Dictionary = {}) -> Dictionary:
	var ids: Array = st.spawn.get("styles", [])
	if ids.is_empty():
		return {}
	var all: Dictionary = rows if not rows.is_empty() else npcs.data.get("styles", {})
	var chain := []
	var defensive := []
	var pos := {0: [], 1: [], 2: []}
	var anytime := []
	for i in ids:
		var s: Dictionary = all.get(str(int(i)), {})
		if s.is_empty():
			continue
		match int(s.get("openingrequirementtype", 0)):
			1: defensive.append(s)
			2:
				if pos.has(int(s.get("openingrequirementvalue", 0))):
					pos[int(s.openingrequirementvalue)].append(s)
			_:
				(chain if int(s.get("openingrequirementvalue", 0)) > 0 else anytime).append(s)
	for s in chain:
		if _npc_style_ok(st, s, tgt):
			return s
	for s in defensive:
		if _npc_style_ok(st, s, tgt) and not _stun_still_on(s, tgt):
			return s
	if randf() * 100.0 < float(CombatRules.melee().get("npc_style_chance", 20)):
		for k in [0, 1, 2]:                                 # back, side, front
			var l: Array = pos[k]
			if not l.is_empty():
				var s: Dictionary = l[randi() % l.size()]
				if _npc_style_ok(st, s, tgt):
					return s
		if not anytime.is_empty():
			return anytime[randi() % anytime.size()]
	return {}


## StyleProcessor.CanUseStyle for a monster against the player (any weapon; no stealth openers): a chain needs its
## opener to have just landed (and its own result requirement), a defensive style your last swing at it ending as
## required, a positional one you in its 120 degree front and it at your back (150-210 degrees) / side (45-150,
## 210-315) / front (315-45).
func _npc_style_ok(st: NpcState, style: Dictionary, tgt: Variant = "player") -> bool:
	if bool(style.get("stealthrequirement", false)):
		return false
	var val := int(style.get("openingrequirementvalue", 0))
	var need: String = ["any", "miss", "hit", "parry", "block", "evade", "fumble", "style"][clampi(int(style.get("attackresultrequirement", 0)), 0, 7)]
	match int(style.get("openingrequirementtype", 0)):
		0:
			if val != 0 and (st.swing_result != "style" or int(st.swing_style.get("id", -1)) != val):
				return false
			if need != "any" and need != st.swing_result:
				return false
		1:
			if tgt is NpcState:                             # its target's last swing at it
				if need != "any" and (not is_same((tgt as NpcState).last_swing_on, st) or (tgt as NpcState).swing_result != need):
					return false
			elif tgt is BotFoe:                             # a gamebot's last swing at it
				if need != "any" and ((tgt as BotFoe).last_target != st or (tgt as BotFoe).last_result != need):
					return false
			elif need != "any" and (last_target != st or last_result != need):
				return false
		2:
			if tgt is BotFoe:                               # a gamebot: in its front, at its back / side / front
				var b: BotFoe = tgt
				if not MeleeMath.in_front(st.pos, MeleeMath.npc_fwd(st), b.pos, 120.0):
					return false
				var a3 := fposmod(rad_to_deg(MeleeMath.char_fwd(b.yaw).angle_to(Vector2(st.pos.x - b.pos.x, st.pos.z - b.pos.z))), 360.0)
				match val:
					0: return a3 > 150.0 and a3 < 210.0
					1: return (a3 >= 45.0 and a3 <= 150.0) or (a3 >= 210.0 and a3 <= 315.0)
					2: return a3 > 315.0 or a3 < 45.0
				return true
			if tgt is NpcState:                             # another monster / a pet: by that one's facing
				var t: NpcState = tgt
				var to_att := Vector2(st.pos.x - t.pos.x, st.pos.z - t.pos.z)
				var a2 := fposmod(rad_to_deg(Vector2(sin(t.yaw), cos(t.yaw)).angle_to(to_att)), 360.0)
				match val:
					0: return a2 > 150.0 and a2 < 210.0
					1: return (a2 >= 45.0 and a2 <= 150.0) or (a2 >= 210.0 and a2 <= 315.0)
					2: return a2 > 315.0 or a2 < 45.0
				return true
			if not _in_front_of_npc(st, 120.0):
				return false
			var to_npc := Vector2(st.pos.x - player.global_position.x, st.pos.z - player.global_position.z)
			var fwd := Vector2(-sin(player.facing()), -cos(player.facing()))
			var angle := fposmod(rad_to_deg(fwd.angle_to(to_npc)), 360.0)
			match val:
				0: return angle > 150.0 and angle < 210.0
				1: return (angle >= 45.0 and angle <= 150.0) or (angle >= 210.0 and angle <= 315.0)
				2: return angle > 315.0 or angle < 45.0
	return true


## GameNPC.CheckStyleStun: a style with a stun proc isn't used while that stun is still on you.
func _stun_still_on(style: Dictionary, tgt: Variant = "player") -> bool:
	if casting == null or tgt is BotFoe:                   # (gamebots' effects: with their spells)
		return false
	for p in style.get("procs", []):
		var sp := NpcCasting.spell(int(p.spell))
		if String(sp.get("type", "")) != "StyleStun":
			continue
		if tgt is NpcState:
			if (tgt as NpcState).stunned:
				return true
		elif casting.player_has(sp):
			return true
	return false


## A monster's landed style's procs (StyleProcessor.ExecuteStyle): those for the style's class or any class, each
## at its chance (a random-proc style: one of them); scaled by its level / 50 (GameNPC.GetScaledSpell).
func _npc_style_procs(st: NpcState, style: Dictionary, tgt: Variant = "player") -> void:
	var procs: Array = style.get("procs", [])
	if procs.is_empty() or casting == null:
		return
	var fire := []
	if int(style.get("randomproc", 0)) != 0:
		fire = [(procs[randi() % procs.size()] as Dictionary).merged({"chance": 100}, true)]
	else:
		fire = procs.filter(func(p): return int(p["class"]) == int(style.get("classid", 0)) or int(p["class"]) == 0)
	for p in fire:
		if randf() * 100.0 < float(p.get("chance", 100)):
			# GameNPC.GetScaledSpell: a monster by level / 50, a pet by its summon factor
			var f: float = float(st.spawn.get("spell_scale", 1.0)) if st.spawn.get("role") == "pet" else st.level / 50.0
			var sp := NpcCasting.scaled(NpcCasting.spell(int(p.spell)), f)
			if sp.is_empty():
				continue
			if tgt is NpcState:
				casting.apply_proc(sp, tgt)
			else:
				casting.apply_to_player(sp, st, 30 + st.level - 1)


## A monster's equipment this spawn (NPCEquipment rows): {slot: model}.
func _npc_gear(st: NpcState) -> Dictionary:
	var out := {}
	for e in npcs.data.get("equipment", {}).get(String(st.spawn.get("equipment", "")), []):
		out[int(e.slot)] = int(e.model)
	return out


func _style_ok(style: Dictionary, st: NpcState) -> bool:
	if bool(style.get("stealthrequirement", false)) and not (abilities and abilities.stealthed):
		return false                                        # critical strike openers: only from stealth
	var kind := int(style.get("openingrequirementtype", 0))
	var val := int(style.get("openingrequirementvalue", 0))
	var need: String = ["any", "miss", "hit", "parry", "block", "evade", "fumble", "style"][clampi(int(style.get("attackresultrequirement", 0)), 0, 7)]
	match kind:
		0:
			if val != 0 and (last_result != "style" or last_style_id != val):
				return false
			if need != "any" and need != last_result:
				return false
		1:
			if need != "any" and st.swing_result != need:     # its last swing at you (targetsLastAD)
				return false
		2:
			if not _in_front_of_player(st.pos, 120.0):
				return false
			var to_player := Vector2(player.global_position.x - st.pos.x, player.global_position.z - st.pos.z)
			var facing := Vector2(sin(st.yaw), cos(st.yaw))
			var angle := fposmod(rad_to_deg(facing.angle_to(to_player)), 360.0)
			match val:
				0: return angle > 150.0 and angle < 210.0
				1: return (angle >= 45.0 and angle <= 150.0) or (angle >= 210.0 and angle <= 315.0)
				2: return angle > 315.0 or angle < 45.0
	return true


func _the(st: NpcState) -> String:
	var n := String(st.spawn.name)
	return ("the " + n) if n.length() > 0 and n[0] == n[0].to_lower() else n


func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1) if s != "" else s



# --- gamebots (bot plan phase 4: your zone's bots in the game, every other zone's in the world host) ----------------
# Owner 2026-10-11: bots and players share rules. A bot (BotFoe) is a character - its own CharacterState - fighting the
# zone's monsters by the player's rules (MeleeMath both ways); monsters put it on their threat lists like you or a pet.
# The bots' brain (C#, BotSim) moves it and chooses; it calls bot_swing when its blow lands and reads its events.

var bots: Array = []                                    # BotFoe in this zone
var group_xp := Callable()                              # Companions.group_xp: a kill shared across your group
var _fighting := {}                                     # monsters in a fight (a world host zone looks at these only)
var _aggro_grid := {}                                   # Vector2i cell -> aggressive spawns (by spawn point)
const AGGRO_CELL := 64.0
const BOT_AGGRO_EVERY := 0.5                            # seconds between a bot's looks for monsters that notice it
var _bot_scan_i := 0
var _bot_scan_left := 0.0


## A world host zone: no player, no UI - the zone's monsters fight its gamebots.
func setup_host(n: NpcManager) -> void:
	npcs = n
	_add_caster()


var caster: BotCaster                                    # gamebots' and companions' spells and bows


func _add_caster() -> void:
	caster = BotCaster.new()
	caster.name = "BotCaster"
	caster.combat = self
	add_child(caster)


func bot_add(b: BotFoe) -> void:
	if not bots.has(b):
		bots.append(b)


func bot_remove(b: BotFoe) -> void:
	bots.erase(b)
	if caster:
		caster.forget(b)
	for s in npcs.states:
		var st: NpcState = s
		if st.aggro.has(b):
			st.aggro.erase(b)
		if st.target_bot == b:
			st.target_bot = null


## A monster for a bot to fight: the nearest within `radius` m of `at` whose level is in lo..hi - alive, of no realm,
## not peaceful, targetable and seen (not hiding), not busy with someone else (its own fight with this bot is fine).
## lo / hi: the cons it hunts (-2 green .. 0 yellow - old server NaturalMaximumTargetCon solo; a death lowers hi).
func bot_prey(b: BotFoe, at: Vector3, radius: float, lo: int, hi: int) -> NpcState:
	# the monsters near it from a grid by spawn point (every spawn of the zone looked over on every call cost the world
	# host ~4.7 ms a tick at 1,500 bots); wanderers - patrols, wide roamers - are always looked over
	if _prey_grid.is_empty():
		_build_prey_grid()
	var best: NpcState = null
	var bd := radius * radius
	var r := radius + PREY_MARGIN
	var x0 := floori((at.x - r) / PREY_CELL)
	var x1 := floori((at.x + r) / PREY_CELL)
	var z0 := floori((at.z - r) / PREY_CELL)
	var z1 := floori((at.z + r) / PREY_CELL)
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			for s in _prey_grid.get(Vector2i(cx, cz), []):
				var st: NpcState = s
				if _prey_ok(st, b, lo, hi):
					var d := st.pos.distance_squared_to(at)
					if d < bd:
						bd = d
						best = st
	for s in _prey_wide:
		var st: NpcState = s
		if _prey_ok(st, b, lo, hi):
			var d := st.pos.distance_squared_to(at)
			if d < bd:
				bd = d
				best = st
	return best


func _prey_ok(st: NpcState, b: BotFoe, lo: int, hi: int) -> bool:
	if not st.alive or st.stealthed or st.returning or int(st.spawn.realm) != 0:
		return false
	var con := npcs.con_of(b.sheet.level, st.level)
	if con < lo or con > hi:
		return false                                       # (owner 2026-10-11: bots took on orange monsters)
	if b.skipping(st):
		return false                                       # (a pull on it that never landed - BotSim's pull watch)
	return not (st.fighting and st.target_bot != b)


var _prey_grid := {}                                     # Vector2i cell -> targetable monsters (by spawn point)
var _prey_wide: Array = []                               # ...and the ones that wander far from it (patrols, roamers)
const PREY_CELL := 32.0
const PREY_MARGIN := 32.0                                # how far a grid monster may be from its spawn point


func _build_prey_grid() -> void:
	_prey_grid.clear()
	_prey_wide.clear()
	_prey_grid[Vector2i(-99999, -99999)] = []                # (built)
	for s in npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) != 0 or int(st.spawn.get("flags", 0)) & (Npc.FLAG_PEACE | Npc.FLAG_CANTTARGET):
			continue
		if st.spawn.get("path") is Dictionary or st.roam > PREY_MARGIN * 0.5:
			_prey_wide.append(st)
			continue
		var c := Vector2i(floori(st.home.x / PREY_CELL), floori(st.home.z / PREY_CELL))
		if not _prey_grid.has(c):
			_prey_grid[c] = []
		_prey_grid[c].append(st)


## The monsters fighting a bot right now.
func bot_attackers(b: BotFoe) -> Array:
	var out := []
	for s in _fighting.keys():
		var st: NpcState = s
		if st.alive and st.fighting and st.target_bot == b:
			out.append(st)
	return out


func _bot_attackers_near(b: BotFoe) -> int:
	var n := 0
	for s in _fighting.keys():
		var st: NpcState = s
		if st.alive and st.fighting and st.target_bot == b and st.pos.distance_to(b.pos) < REACH + 3.0:
			n += 1
	return maxi(n, 1)


## Bots' upkeep: their regeneration, and - a few bots each tick, every bot twice a second - an aggressive monster
## that sees a bot inside its aggro range comes for it (the player's rule: not grey to it, its faction standing
## aggressive, in sight; not while it sits on a steed - with the stables work).
func _bots_tick(delta: float) -> void:
	if bots.is_empty():
		return
	if _aggro_grid.is_empty():
		_build_aggro_grid()
	_bot_scan_left += delta * bots.size() / BOT_AGGRO_EVERY
	while _bot_scan_left >= 1.0:
		_bot_scan_left -= 1.0
		_bot_scan_i = (_bot_scan_i + 1) % bots.size()
		var b: BotFoe = bots[_bot_scan_i]
		b.regen(BOT_AGGRO_EVERY)                           # its regeneration in half-second steps
		_bot_aggro(b)


func _build_aggro_grid() -> void:
	_aggro_grid[Vector2i(-99999, -99999)] = []               # (built)
	for s in npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and int(st.spawn.get("aggro_level", 0)) > 0 and int(st.spawn.get("aggro_range", 0)) > 0:
			var c := Vector2i(floori(st.home.x / AGGRO_CELL), floori(st.home.z / AGGRO_CELL))
			if not _aggro_grid.has(c):
				_aggro_grid[c] = []
			_aggro_grid[c].append(st)


## Route awareness for a travelling gamebot (old server: 55-71% of solo deaths came on the way to the camp, walking
## into aggressive monsters): the first aggressive monster whose aggro range crosses the next stretch of its path.
## {st, act, side}: act "pull" - an even fight alone, take it on its own terms; "avoid" - too strong or with company,
## step around it (side: a point beside it outside its range, on the side of the path); "abandon" - avoided twice and
## still in the way and too strong: give up this destination. {} when the way is clear. Greys never count.
func bot_route_threat(b: BotFoe, points: PackedVector3Array, avoided: int) -> Dictionary:
	if _aggro_grid.is_empty():
		_build_aggro_grid()
	for p in points:
		var c := Vector2i(floori(p.x / AGGRO_CELL), floori(p.z / AGGRO_CELL))
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				for s in _aggro_grid.get(c + Vector2i(dx, dz), []):
					var st: NpcState = s
					if not st.alive or st.fighting or st.returning:
						continue
					var r := mini(int(st.spawn.aggro_range), 3600) * 0.025 + 2.0
					var flat := Vector2(st.pos.x - p.x, st.pos.z - p.z)
					if flat.length() > r:
						continue
					var con := npcs.con_level(b.level(), st.level)
					if con <= -3:
						continue
					var fs := b.sheet.faction_standing(int(st.spawn.get("faction", 0)))
					if fs != "" and fs != "aggressive":
						continue
					var pack := 0
					for s2 in _aggro_grid.get(Vector2i(floori(st.pos.x / AGGRO_CELL), floori(st.pos.z / AGGRO_CELL)), []):
						var o: NpcState = s2
						if o != st and o.alive and not o.fighting and o.pos.distance_to(st.pos) < 10.0 and npcs.con_level(b.level(), o.level) > -3:
							pack += 1
					if con <= 0 and pack == 0:
						return {"st": st, "act": "pull"}
					if avoided >= 2:
						return {"st": st, "act": "pull" if con <= 1 and pack <= 1 else "abandon"}
					# a step around it: beside it, square to the path, outside its range (on the bot's side of it)
					var dir := Vector2(p.x - b.pos.x, p.z - b.pos.z).normalized()
					var perp := Vector2(-dir.y, dir.x)
					if perp.dot(Vector2(b.pos.x - st.pos.x, b.pos.z - st.pos.z)) < 0.0:
						perp = -perp
					var side := Vector3(st.pos.x + perp.x * (r + 4.0), st.pos.y, st.pos.z + perp.y * (r + 4.0))
					return {"st": st, "act": "avoid", "side": side}
	return {}


func _bot_aggro(b: BotFoe) -> void:
	if not b.alive or b.riding:                            # monsters leave riders alone (as the player on a steed)
		return
	var c := Vector2i(floori(b.pos.x / AGGRO_CELL), floori(b.pos.z / AGGRO_CELL))
	for dz in range(-2, 3):                                # aggro ranges reach 90 m (3600 units, MAX_AGGRO_DISTANCE)
		for dx in range(-2, 3):
			for s in _aggro_grid.get(c + Vector2i(dx, dz), []):
				var st: NpcState = s
				if not st.alive or st.fighting or st.returning:
					continue
				var r := mini(int(st.spawn.aggro_range), 3600) * 0.025
				if Vector2(st.pos.x - b.pos.x, st.pos.z - b.pos.z).length() > r:
					continue
				if npcs.con_level(b.level(), st.level) <= -3:
					continue                                   # grey cons leave it alone
				var fs := b.sheet.faction_standing(int(st.spawn.get("faction", 0)))
				if fs != "" and fs != "aggressive":
					continue
				if not _sees(st, b.pos):
					continue
				add_aggro(st, b, 0)
				b.note("aggro", {"by": String(st.spawn.name), "level": st.level})


## A bot's blow lands (or misses) on a monster - the player's rules (MeleeMath): its defence, the miss roll, damage,
## the critical hit; threat; a kill's experience. Returns what happened ({result, dmg, crit, killed}).
func bot_swing(b: BotFoe, st: NpcState, style: Dictionary = {}) -> Dictionary:
	if not b.alive or not st.alive:
		return {"result": "gone"}
	b.last_target = st
	b.last_hit_at = Time.get_ticks_msec() / 1000.0
	var w := MeleeMath.weapon(b.sheet)
	if st.target_bot != b and not st.aggro.has(b):
		add_aggro(st, b, 0)                                # swinging at it starts the fight (Combat._engage)
	_engage(st)
	var defended := MeleeMath.npc_defends(st, b.sheet, w, b.pos, _npc_gear(st))
	if defended != "":
		b.last_result = defended
		if st.view:
			(st.view as Npc).play_defend(defended)
		return {"result": defended}
	if style.is_empty() and not b.tactics.is_empty():
		style = _bot_style(b, st, w)                       # a companion's TACTICS bar
	elif style.is_empty() and not b.has_meta("companion"):
		style = BotProgress.auto_style(self, b, st, w)     # a gamebot picks its own (old server: gamebots used styles)                       # a companion's TACTICS bar: the first style that fits
	var style_ok := not style.is_empty() and _bot_style_ok(b, style, st, w)
	var r := MeleeMath.character_blow(b.sheet, st, w, style, {"style_ok": style_ok})
	if r.result == "miss":
		b.last_result = "miss"
		return {"result": "miss"}
	if r.result == "bladeturn":
		if npc_casting:
			npc_casting.interrupt(st)
		return {"result": "bladeturn"}
	b.last_result = String(r.result)
	if not style.is_empty():
		b.sheet.spend_endurance(maxi(1, int(CombatRules.style_endurance(style, int(w.get("spd_abs", 30))))))
		if r.result == "style":
			b.last_style = style
			b.note("style", {"name": String(style.get("name", ""))})
	var dmg := int(r.dmg) + int(r.crit)
	st.damage(dmg)
	_update_target(st)                                     # (your target bar, when it's the one the bot hit)
	add_aggro(st, b, dmg)
	if npc_casting:
		npc_casting.interrupt(st)
	if st.view:
		var v := st.view as Npc
		v.flinch()
		var heavy := dmg >= maxi(1, st.max_hp) * 0.1
		var ws := int(WeaponModels.info(int(w.get("model", 0))).get("sound_set", 0))
		if v.sounds:
			v.sounds.weapon(ws if ws > 0 else WEAPONLESS, "style_hit" if r.result == "style" else ("hit_medium" if heavy else "hit_light"))
			if st.alive:
				v.sounds.event("pain_heavy" if r.result == "style" else ("pain_medium" if heavy else "pain_light"))
	var out := {"result": r.result, "dmg": dmg, "crit": int(r.crit), "killed": not st.alive}
	if not st.alive:
		_bot_killed(b, st)
	return out


## A gamebot's next errand (BotProgress.errand): promote / train / sell / arrows, at a real NPC of its realm in this
## zone or another outdoor zone of the region. {} when none.
func bot_errand(b: BotFoe, zone_id: int) -> Dictionary:
	return BotProgress.errand(b, zone_id)


## At the errand's NPC: what it did ("" nothing could be done there).
func bot_errand_do(b: BotFoe, kind: String, want: int) -> String:
	return BotProgress.do_errand(npcs, b, kind, want)


## The region zone under a point beyond this zone's edge, and the point in that zone ({} outside the region's zones).
func bot_zone_at(zone_id: int, local: Vector3) -> Dictionary:
	return BotProgress.zone_at(zone_id, local)


## A bot's arrow landing (BotCaster): the player's rule (_arrow_lands) from the bot's sheet - the miss chance with the
## bow's bonus and the fletching, the monster's evade (a fifth as often) and block (+25%), the bow's damage with its spec
## and the arrow's head, the resist, the 10% archery crit; its kill as its blow's.
func bot_arrow(b: BotFoe, st: NpcState, bow: Dictionary, ammo: Dictionary) -> void:
	if not st.alive or not b.alive:
		return
	b.last_target = st
	b.last_hit_at = Time.get_ticks_msec() / 1000.0
	if st.target_bot != b and not st.aggro.has(b):
		add_aggro(st, b, 0)
	_engage(st)
	var lvl := b.level()
	var miss := CombatRules.miss_chance(lvl, st.level, _style_miss_adjust({}, st.swing_result, st.swing_style),
			-mini(int(bow.get("bonus", 0)), CombatRules.bonus_cap(lvl)))
	match (int(ammo.get("spd_abs", 0)) >> 4) & 3:
		0: miss += miss * 0.15
		3: miss -= miss * 0.25
	var d: Array = st.spawn.get("defense", [0, 0, 0, 0])
	if not (st.mezzed or st.stunned):
		var to_bot := Vector2(b.pos.x - st.pos.x, b.pos.z - st.pos.z)
		var ang := rad_to_deg(absf(MeleeMath.npc_fwd(st).angle_to(to_bot))) if to_bot.length() > 0.01 else 0.0
		if int(d[0]) > 0 and ang <= 90.0 and randf() < int(d[0]) * 10 * 0.001 / 5.0:
			b.last_result = "evade"
			return
		var gear := _npc_gear(st)
		if gear.has(11) and not gear.has(12) and int(d[3]) <= 0 and ang <= 60.0 and randf() < int(d[2]) * 10 / 1000.0 + 0.25:
			b.last_result = "block"
			return
	if randf() < miss:
		b.last_result = "miss"
		return
	var sheet := b.sheet
	var spec := int(sheet.specs.get(CombatRules.weapon_spec_key(bow), 1))
	var ammo_mod: float = [0.85, 1.0, 1.15, 1.25][int(ammo.get("spd_abs", 0)) & 3]
	var parts := CombatRules.player_damage_parts(bow, lvl, sheet.class_id(), sheet.effective_stats(), spec, st.level, ammo_mod, st.af_bonus - st.af_debuff, st.absorb())
	var adt := int(ammo.get("type_damage", 0))
	var rmod := 1.0 - st.resist(adt if adt > 0 else int(bow.get("type_damage", 3))) * 0.01
	var dmg := maxi(1, int(minf(parts[0] * rmod, parts[1])))
	if randf() * 100.0 < CRIT_CHANCE:
		dmg += int(dmg * randf_range(0.1, 1.0))
	b.last_result = "hit"
	st.damage(dmg)
	add_aggro(st, b, dmg)
	if npc_casting:
		npc_casting.interrupt(st)
	if st.view:
		(st.view as Npc).flinch()
		if (st.view as Npc).sounds and st.alive:
			(st.view as Npc).sounds.event("pain_light")
	_update_target(st)
	if b.has_meta("companion"):
		PlayerData.message.emit("%s shoots %s for %d damage!" % [b.name, _the(st), dmg], "combat")
	if not st.alive:
		_bot_killed(b, st)


## The first style on a bot's TACTICS bar it may use now: its opening holds, its weapon fits, the endurance is there.
func _bot_style(b: BotFoe, st: NpcState, w: Dictionary) -> Dictionary:
	for t in b.tactics:
		if not (t is Dictionary) or String(t.get("kind", "")) != "style":
			continue
		var style := ClassDb.style_by_game_id(int(t.get("id", 0)), b.sheet.class_id())   # tactics keep the in-game id
		if style.is_empty():
			continue
		var cost := maxi(1, int(CombatRules.style_endurance(style, int(w.get("spd_abs", 30)))))
		if b.sheet.end_pts >= cost and _bot_style_ok(b, style, st, w):
			return style
	return {}


## StyleProcessor.CanUseStyle for a bot (the player's _style_ok, from the bot's side): no stealth openers yet; the
## weapon the style wants; a chain needs its opener to have just landed; a reactive style the monster's last swing at
## the bot ending as required; a positional one the bot at its back / side / front.
func _bot_style_ok(b: BotFoe, style: Dictionary, st: NpcState, w: Dictionary) -> bool:
	if bool(style.get("stealthrequirement", false)):
		return false
	var req := int(style.get("weapontyperequirement", 0))
	if req == 1000:
		var left := b.sheet.item_at(11)
		if left.is_empty() or int(left.get("object_type", 0)) == ItemDb.SHIELD_TYPE:
			return false
	elif req == ItemDb.SHIELD_TYPE:
		if int(b.sheet.item_at(11).get("object_type", 0)) != ItemDb.SHIELD_TYPE:
			return false
	elif req != 0 and req != 1001 and req != int(w.get("object_type", 0)):
		return false
	var kind := int(style.get("openingrequirementtype", 0))
	var val := int(style.get("openingrequirementvalue", 0))
	var need: String = ["any", "miss", "hit", "parry", "block", "evade", "fumble", "style"][clampi(int(style.get("attackresultrequirement", 0)), 0, 7)]
	match kind:
		0:
			if val != 0 and (b.last_result != "style" or int(b.last_style.get("id", -1)) != val):
				return false
			if need != "any" and need != b.last_result:
				return false
		1:
			if need != "any" and (not is_same(st.last_swing_on, b) or st.swing_result != need):
				return false
		2:
			var to_bot := Vector2(b.pos.x - st.pos.x, b.pos.z - st.pos.z)
			var angle := fposmod(rad_to_deg(MeleeMath.npc_fwd(st).angle_to(to_bot)), 360.0)
			match val:
				0: return angle > 150.0 and angle < 210.0
				1: return (angle >= 45.0 and angle <= 150.0) or (angle >= 210.0 and angle <= 315.0)
				2: return angle > 315.0 or angle < 45.0
	return true


## A bot's kill (the player's rule): the monster's last words and death, the kill's experience at the bots' rate
## (none if grey, none 60 s after a charm), its faction's opinion of the bot.
func _bot_killed(b: BotFoe, st: NpcState) -> void:
	npcs.ambient(st, "dying", b.name)
	if st.view:
		(st.view as Npc).play_death()
		if (st.view as Npc).sounds:
			(st.view as Npc).sounds.event("die")
	var con := npcs.con_level(b.level(), st.level)
	var xp := 0
	if b.has_meta("companion"):                            # your companion's kill: yours and your group's
		if Time.get_ticks_msec() / 1000.0 - st.charmed_at >= 60.0 and group_xp.is_valid():
			group_xp.call(st)
		monster_killed.emit(st)                            # (quest kill steps count your group's kills)
	elif Time.get_ticks_msec() / 1000.0 - st.charmed_at >= 60.0:   # GameNPC.CHARMED_NOEXP_TIMEOUT
		xp = CombatRules.kill_xp(st.level, b.level(), con <= -3)
		b.sheet.gain_xp(xp)
	var looted := BotProgress.loot(b, st)                  # its coins and drops, the player's tables (gamebots only)
	if looted != "":
		b.note("looted", {"text": looted})
	b.sheet.faction_killed(int(st.spawn.get("faction", 0)))
	b.note("killed", {"name": String(st.spawn.name), "level": st.level, "xp": xp * b.sheet.xp_rate()})


## A monster's blow on a bot: the bot's defence (evade / parry / block by its abilities, specs and shield), the miss
## roll, the damage on the piece struck, its style - all MeleeMath, the same as on you. The bot may die of it.
func _npc_hits_bot(st: NpcState, b: BotFoe) -> void:
	if not st.alive or not st.fighting or not b.alive:
		return
	b.last_hit_at = Time.get_ticks_msec() / 1000.0
	b.hit_at = b.last_hit_at
	var style := _npc_style_to_use(st, b)
	var style_ok := not style.is_empty() and _npc_style_ok(st, style, b)
	st.swing_style = {}
	st.last_swing_on = b
	var defended := MeleeMath.character_defends(st, {"sheet": b.sheet, "pos": b.pos, "fwd": MeleeMath.char_fwd(b.yaw),
			"busy": b.sitting, "attackers": _bot_attackers_near(b), "arrow": _ranged_blow}, _npc_gear(st).has(12))
	if defended != "":
		st.swing_result = defended
		b.note("defended", {"by": String(st.spawn.name), "how": defended})
		return
	var slot := MeleeMath.hit_location()
	if MeleeMath.npc_misses(st, {"sheet": b.sheet, "sitting": b.sitting, "last_result": b.last_result,
			"last_style": b.last_style}, style, slot):
		st.swing_result = "miss"
		return
	st.swing_result = "hit"
	var r := MeleeMath.npc_damage(st, b.sheet, slot, style, style_ok, _npc_weapon(st), _npc_interval(st))
	if style_ok:
		if st.view and is_instance_valid(st.view) and player:
			StyleTrail.play_from_impact(player.get_parent(), (st.view as Npc).model, style)
		st.swing_result = "style"
		st.swing_style = style
	var dmg: int = r.dmg
	b.sheet.set_hp(b.sheet.hp - dmg)
	b.sitting = false                                      # a blow stands you up (GamePlayer: sitting ends on attack)
	if caster:
		caster.on_attacked(b, st.level)                    # its spell or bow draw (the player's interrupt rule)
	b.note("hit", {"by": String(st.spawn.name), "dmg": dmg, "where": r.where})
	if b.sheet.hp <= 0:
		_bot_died(b, st)


## A bot's release (the player's rule, Combat._do_release): the release losses (grave, constitution), full health,
## endurance and power; back on its feet. Returns where it goes: its bind spot ({zone, pos, face}) or {} - its start.
func bot_release(b: BotFoe, at: Vector3) -> Dictionary:
	b.sheet.release_losses(int(b.get_meta("death_loss", 0)), at, b.yaw, int(npcs.zone.info.id) if npcs and npcs.zone else -1)
	b.sheet.restore_full()
	b.alive = true
	b.sitting = false
	b.note("released")
	var bind = b.sheet.character.get("bind")
	return bind if bind is Dictionary else {}


## A bot's death (the player's rule): experience lost at level 6+ (CharacterState.death_xp_loss); the monsters that
## fought it go back to their lists (Combat finds the bot dead and moves on); the brain releases it.
func _bot_died(b: BotFoe, killer: NpcState) -> void:
	b.alive = false
	b.sitting = false
	var loss := b.sheet.death_xp_loss()
	b.set_meta("death_loss", loss)                         # taken again at the release, into its grave
	npcs.ambient(killer, "killing", b.name)
	for s in _fighting.keys():
		var st: NpcState = s
		if st.aggro.has(b):
			st.aggro.erase(b)
		if st.target_bot == b:
			st.target_bot = null
	b.note("died", {"by": String(killer.spawn.name), "level": killer.level, "xp_lost": loss})


# --- companions' choices (bot plan phase 6 - the stances, owner 2026-10-11) ------------------------------------------
#   aggressive: attacks what you attack, and whatever attacks you, it or the group - never a fight of its own (the
#               500-unit seek is gone - owner 2026-10-11)
#   defensive:  fights only when you or another companion is attacked, or a monster comes within 300 units
#   supportive: heals and buffs first; never fights with plain swings - only with the attacks on its TACTICS bar
#               (with one there it fights as a defensive companion would, using them)
#   passive:    only heals and buffs - never attacks, whatever its bar holds
const DEFENSIVE_NEAR := 300 * 0.025


## The monsters fighting you or one of your companions now.
func group_attackers() -> Array:
	var out := []
	for s in _fighting.keys():
		var st: NpcState = s
		if not st.alive or not st.fighting:
			_fighting.erase(st)
			continue
		if (st.target_bot != null and st.target_bot.has_meta("companion")) or (st.target_pet == null and st.target_bot == null and st.aggro.has("player")):
			out.append(st)
	return out


## What a companion should fight now by its stance (null: nothing - it follows you).
func companion_pick(b: BotFoe, stance: String) -> NpcState:
	if not b.alive or b.riding or stance == "passive":
		return null
	if stance == "supportive" and not _has_attack_tactic(b):
		return null
	var attackers := group_attackers()
	if stance == "aggressive":
		# what you attack - in melee or with a spell (it's fighting you) - and whatever attacks you, it or the others;
		# nothing it picks out for itself (owner 2026-10-11: they went after random monsters)
		var t: Npc = npcs.target if npcs.target and is_instance_valid(npcs.target) else null
		if t and t.state.alive and int(t.spawn.realm) == 0 and (attack_mode or t.state.player_hit or t.state.aggro.has("player")):
			return t.state
		return _nearest(attackers, b.pos, 1e9)
	var d := _nearest(attackers, b.pos, 1e9)
	if d:
		return d
	return _nearest_monster(b, DEFENSIVE_NEAR)


func _has_attack_tactic(b: BotFoe) -> bool:
	for t in b.tactics:
		if t is Dictionary and String(t.get("kind", "")) == "style":
			return true
		if t is Dictionary and String(t.get("kind", "")) == "spell" and bool(t.get("attack", false)):
			return true
	return false


func _nearest(list: Array, at: Vector3, r: float) -> NpcState:
	var best: NpcState = null
	var bd := r * r
	for s in list:
		var st: NpcState = s
		var d := st.pos.distance_squared_to(at)
		if d < bd:
			bd = d
			best = st
	return best


## The nearest monster a companion may take on: of no realm, alive, not peaceful or untargetable, not hiding or
## going home, not grey to it.
func _nearest_monster(b: BotFoe, r: float) -> NpcState:
	var best: NpcState = null
	var bd := r * r
	for s in npcs.states:
		var st: NpcState = s
		if not st.alive or int(st.spawn.realm) != 0 or st.stealthed or st.returning:
			continue
		var d := st.pos.distance_squared_to(b.pos)
		if d >= bd:
			continue
		if int(st.spawn.get("flags", 0)) & (Npc.FLAG_PEACE | Npc.FLAG_CANTTARGET):
			continue
		if npcs.con_level(b.level(), st.level) <= -3:
			continue
		bd = d
		best = st
	return best
