class_name Abilities
extends Node
## Usable abilities (the class's abilities from ClassDb; quickbar kind "ability", or their keys):
##   Sprint (old server SprintECSGameEffect / MaxSpeedCalculator): x1.3 run speed; while moving it costs 5 endurance a
##     second; stops at no endurance or after 6 s standing still. "You prepare to sprint!" / "You are no longer ready
##     to sprint." / "You are too fatigued to sprint!" - every class has it.
##   Quickcast (QuickCastAbilityHandler): the next spell casts in 2 s, can't be interrupted, costs double power; 30 s
##     between uses; not in melee combat. "You have activated quickcast." / "Your next spell will not be quickcasted."
##   Stealth (StealthSpecHandler, the Stealth spec): hide / come out ("You are now hidden!" / "You are no longer
##     hidden!"); not after recent combat, while attacking or casting, with a pulsing spell up, mezzed, stunned, dead, or
##     within 1024 - 896 x spec / its level units of a monster; 2 s between changes. Hidden: monsters don't notice you,
##     you move at 0.3 + (spec + 10) x 0.3 / (level + 10) of your speed (MaxSpeedCalculator); attacking, casting,
##     firing or being hit brings you out; critical strike styles need it.
##   Engage (EngageAbilityHandler / GameLiving block): on your target - not one hit in the last 5 s, not with a bow
##     out, not sitting / dead; you stop swinging and concentrate on blocking its blows: +65% base block chance (no
##     cap) for 5 endurance a block ("You concentrate on blocking the blow!"); your own attack ends it.
##   Berserk (Berserker; BerserkAbilityHandler): 20 s every hit is a critical, no evade / parry / block; 7 min reuse.
##   Stag (Hero; StagAbilityHandler): 30 s, max health and health + (ability level + 0.5 + 0..1) / 10; 15 min reuse.

const SPRINT := 1.3
var player: Player
var combat: Combat
var casting: Casting
var sprinting := false
var stealthed := false
var engaged: NpcState                         # Engage's target
var berserk_left := 0.0
var stag_left := 0.0
var _stag_hp := 0
var _reuse := {}                              # ability -> seconds until it can be used again
var _stealth_at := -10.0
var _idle := 0.0
var _drain := 0.0
var _quick_ready_at := -1000.0


func setup(p: Player, c: Combat, cast: Casting) -> void:
	player = p
	combat = c
	casting = cast
	PlayerData.hook(self, PlayerData.use_skill, func(e: Dictionary):
		if String(e.get("kind", "")) == "ability":
			use(String(e.get("id", ""))))


func use(key: String) -> void:
	match key.to_lower():
		"sprint": toggle_sprint()
		"quickcast": toggle_quickcast()
		"stealth": toggle_stealth()
		"engage": toggle_engage()
		"berserk": berserk()
		"stag": stag()
		"critical shot": combat.critical_shot()
		"rapid fire": combat.rapid_fire()


func toggle_sprint() -> void:
	if sprinting:
		_stop_sprint()
		return
	if player.dead:
		PlayerData.message.emit("You can't sprint when dead!", "system")
		return
	if PlayerData.end_pts <= 10:
		PlayerData.message.emit("You are too fatigued to sprint!", "system")
		return
	sprinting = true
	_idle = 0.0
	player.speed_mult = SPRINT
	PlayerData.message.emit("You prepare to sprint!", "system")


func toggle_stealth() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not stealthed and combat.in_combat():
		PlayerData.message.emit("You've been in combat recently and can't hide yet!", "system")
		return
	if now - _stealth_at < 2.0:
		PlayerData.message.emit("You must wait %d more second to attempt to hide!" % int(2.0 - (now - _stealth_at)), "system")
		return
	if stealthed:
		_stealth_at = now
		break_stealth()
		return
	if player.dead or PlayerData.hp <= 0:
		PlayerData.message.emit("You can't hide when dead!", "system")
		return
	if combat.attack_mode or not casting.casting.is_empty():
		PlayerData.message.emit("You must end your current action before hiding!", "system")
		return
	if not casting.pulse.is_empty():
		PlayerData.message.emit("You currently have an active, pulsing spell effect and cannot hide!", "system")
		return
	if player.cc == "mez":
		PlayerData.message.emit("You can't hide while mesmerized!", "system")
		return
	if player.cc == "stun":
		PlayerData.message.emit("You can't hide while stunned!", "system")
		return
	var spec := mini(int(PlayerData.specs.get("Stealth", 1)), 50)
	for s in combat.npcs.states:
		var st: NpcState = s
		if not st.alive or int(st.spawn.realm) != 0:
			continue
		var radius := (1024.0 - 896.0 * spec / maxf(1.0, st.level)) * 0.025
		if radius > 0.0 and st.pos.distance_to(player.global_position) <= radius:
			PlayerData.message.emit("You are too close to an enemy to hide!", "system")
			return
	_stealth_at = now
	stealthed = true
	if sprinting:
		_stop_sprint()
	var lvl := maxi(PlayerData.level, 1)
	player.stealth_mult = 0.3 + (mini(spec, lvl) + 10.0) * 0.3 / (lvl + 10.0)
	PlayerData.message.emit("You are now hidden!", "system")


func toggle_engage() -> void:
	if engaged != null:
		end_engage(true)
		return
	if player.dead or PlayerData.hp <= 0:
		PlayerData.message.emit("You can't enter combat mode while lying down!", "combat")
		return
	if player.sitting:
		PlayerData.message.emit("You can't enter combat mode while sitting down!", "combat")
		return
	if PlayerData.active_weapon == "ranged":
		PlayerData.message.emit("You can't enter melee combat mode with a fired weapon!", "combat")
		return
	var n: Npc = combat.npcs.target
	if n == null or not is_instance_valid(n) or not n.state.alive or n.is_friendly():
		PlayerData.message.emit("You can only engage mobs hostile to you.", "combat")
		return
	if Time.get_ticks_msec() / 1000.0 - n.state.hit_at < 5.0:
		PlayerData.message.emit("%s has been attacked recently and you are unable to engage." % combat._cap(combat._the(n.state)), "combat")
		return
	engaged = n.state
	combat.attack_mode = true                              # the effect puts you in combat mode without swinging
	PlayerData.message.emit("You concentrate on blocking the blows of %s!" % combat._the(n.state), "combat")


func end_engage(manual := false) -> void:
	if engaged == null:
		return
	engaged = null
	PlayerData.message.emit("You no longer concentrate on blocking the blows!" if manual else "You are no longer attempting to engage a target!", "combat")


func _ready_or_wait(key: String) -> bool:
	return float(_reuse.get(key, 0.0)) <= 0.0


func _can_act() -> bool:
	if player.dead or PlayerData.hp <= 0:
		PlayerData.message.emit("You can't do that while dead!", "system")
		return false
	if player.cc == "mez":
		PlayerData.message.emit("You can't do that while mesmerized!", "system")
		return false
	if player.cc == "stun":
		PlayerData.message.emit("You can't do that while paralyzed!", "system")
		return false
	if player.sitting:
		PlayerData.message.emit("You must be standing to use this ability!", "system")
		return false
	return true


func berserk() -> void:
	if not _ready_or_wait("berserk") or not _can_act():
		return
	_reuse["berserk"] = 7 * 60.0
	berserk_left = 20.0
	player.play_emote(18)                                  # BerserkECSEffect: Emote(MidgardFrenzy)
	PlayerData.message.emit("You go into a berserker frenzy!", "combat")


func stag() -> void:
	if not _ready_or_wait("stag") or not _can_act():
		return
	var lvl := 1
	for a in ClassDb.abilities_known(PlayerData.class_id(), PlayerData.level, PlayerData.specs):
		if String(a.key) == "Stag":
			lvl = int(a.level)
	_reuse["stag"] = 15 * 60.0
	stag_left = 30.0
	var pct := (lvl + 0.5 + randf()) / 10.0
	_stag_hp = int(PlayerData.max_hp * pct)
	PlayerData.bonus_max_hp += _stag_hp
	PlayerData.recalc_max()
	PlayerData.set_hp(mini(PlayerData.max_hp, PlayerData.hp + int(PlayerData.max_hp * pct)))
	player.play_emote(20)                                  # StagECSEffect: Emote(StagFrenzy)
	PlayerData.message.emit("You channel the Spirit of the Hunt!", "combat")


## Out of stealth (an attack, a spell, a shot, a hit on you, or the ability again).
func break_stealth() -> void:
	if not stealthed:
		return
	stealthed = false
	player.stealth_mult = 1.0
	PlayerData.message.emit("You are no longer hidden!", "system")


func _stop_sprint() -> void:
	sprinting = false
	player.speed_mult = 1.0
	PlayerData.message.emit("You are no longer ready to sprint.", "system")


func toggle_quickcast() -> void:
	if casting.quickcast:
		casting.quickcast = false
		PlayerData.message.emit("Your next spell will not be quickcasted.", "spells")
		return
	if not casting.casting.is_empty():
		PlayerData.message.emit("You can't prepare a quickcast while casting a spell!", "spells")
		return
	if player.dead:
		PlayerData.message.emit("You can't quick cast when dead!", "spells")
		return
	if combat.attack_mode:
		PlayerData.message.emit("You can not cast when your are in melee combat.", "spells")
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _quick_ready_at < 30.0:
		PlayerData.message.emit("You must wait %d more second to attempt to quick cast!" % ceili(30.0 - (now - _quick_ready_at)), "spells")
		return
	_quick_ready_at = now
	casting.quickcast = true
	PlayerData.message.emit("You have activated quickcast.", "spells")


func _physics_process(delta: float) -> void:
	for k in _reuse.keys():
		_reuse[k] = float(_reuse[k]) - delta
	if berserk_left > 0.0:
		berserk_left -= delta
		if berserk_left <= 0.0:
			PlayerData.message.emit("Your berserker frenzy ends.", "combat")
	if stag_left > 0.0:
		stag_left -= delta
		if stag_left <= 0.0:
			PlayerData.bonus_max_hp -= _stag_hp
			_stag_hp = 0
			PlayerData.recalc_max()
			PlayerData.message.emit("Your Spirit of the Hunt ends.", "combat")
	if engaged != null and (not engaged.alive or player.dead):
		end_engage()
	if not sprinting:
		return
	var moving := player.velocity.length() > 0.2
	_idle = 0.0 if moving else _idle + delta
	if moving:
		_drain += delta
		if _drain >= 1.0:
			_drain -= 1.0
			combat._spend_endurance(5)
	if PlayerData.end_pts - 5 <= 0 or _idle >= 6.0 or player.dead:
		_stop_sprint()


func _unhandled_input(event: InputEvent) -> void:
	if player._ui_typing():
		return
	if Keybinds.pressed(event, "sprint"):
		toggle_sprint()
	elif Keybinds.pressed(event, "sit"):                  # the client's Sit/Stand key toggles
		PlayerData.sit_requested.emit(not player.sitting)
