extends Node
## Debug, test server (owner 2026-10-15: the Bonedancer sub pets "just glow their hands and stand there" - bonehealer,
## bone diviner; bone archers swing a sword at range): a GM Bonedancer (class 30, level 50) summons a commander and its
## minions; every cast / combat packet from a pet is logged with what its view does over the next 2 s (clip, time,
## casting flag, the model's cast clips). Back to the Animist at the end. Runs once; hard stop 150 s.
const SUMMONS := ["Summon Bone Boss", "Summon Bone Master", "Summon Bone Commander", "Summon Boneknitter",
		"Summon Bonemender", "Summon Bonehealer", "Summon Bone Warmage", "Summon Bonemage", "Summon Bone Diviner",
		"Summon Bone Archer", "Summon Bone Deadeye", "Summon Bone Hunter"]
var v: Node
var t0 := 0
var _pets := {}                            # oid -> name


func _ready() -> void:
	if get_tree().root.has_meta("subpet_srv_ran"):
		return
	get_tree().root.set_meta("subpet_srv_ran", true)
	get_tree().create_timer(150.0).timeout.connect(func(): Server.quit_world(true))
	v = get_tree().current_scene
	t0 = Time.get_ticks_msec()
	Server.world.connect(_on_world)
	PlayerData.message.connect(func(t, _k): _log("chat: " + String(t)))
	await _wait(8.0)
	Server.use("srv:spell:0:1")                             # (a cast ends the GM's login stealth)
	await _wait(4.0)
	Server.client.call("Target", Server.me_oid, 0x6000)
	await _wait(1.0)
	Server.command("/player class 30")
	await _wait(3.0)
	Server.command("/player level 50")
	await _wait(5.0)
	# the summons by spell id (GM /cast spell: the test character has no Bone Army spec): commander, bonehealer, bone
	# diviner, bone archer
	for sid in [10103, 10064, 10005, 10153]:
		_log("GM cast spell %d" % sid)
		Server.command("/cast spell %d" % sid)
		await _wait(7.0)
	_log("waiting for the minions' own casts (buffs on themselves)")
	await _wait(25.0)
	_finish()


func _finish() -> void:
	Server.command("/pet release")
	await _wait(2.0)
	Server.client.call("Target", Server.me_oid, 0x6000)
	await _wait(1.0)
	Server.command("/player class 55")
	await _wait(3.0)
	Server.quit_world(true)


func _on_world(kind: String, d: Dictionary) -> void:
	match kind:
		"npc":
			var nm := String(d.get("name", ""))
			if nm.to_lower().begins_with("bone") and not _pets.has(int(d.oid)):
				_pets[int(d.oid)] = nm
				_log("pet %d %s model %d" % [int(d.oid), nm, int(d.model) & 0x7FFF])
		"cast":
			if _pets.has(int(d.caster)):
				_log("CAST by %s: effect %d, %.1f s" % [_pets[int(d.caster)], int(d.spell), int(d.get("time", 0)) / 10.0])
				_watch(int(d.caster))
		"spell_effect":
			if _pets.has(int(d.caster)):
				_log("EFFECT by %s: effect %d -> %d" % [_pets[int(d.caster)], int(d.spell), int(d.target)])
		"interrupt":
			if _pets.has(int(d.caster)):
				_log("INTERRUPT %s" % _pets[int(d.caster)])
		"combat":
			if _pets.has(int(d.get("attacker", 0))):
				_log("COMBAT by %s: %s" % [_pets[int(d.attacker)], d])
		"equipment":
			if _pets.has(int(d.get("oid", 0))):
				_log("EQUIP %s: slots %s active %s" % [_pets[int(d.oid)], (d.get("items", []) as Array).map(func(i): return [i.slot, i.model]), d.get("weapon_slots", "?")])


func _watch(oid: int) -> void:
	for k in 7:
		await get_tree().process_frame if k == 0 else _wait(0.3)
		var n = (v.npcs as ServerWorld)._view_of(oid)
		if n == null or not (n is Npc):
			_log("   view: %s" % n)
			continue
		var npc := n as Npc
		var a := npc.anim
		_log("   +%d: clip '%s' %.2f playing %s, casting %s, action_left %.2f, cast clips %s, info cast_clips %s" % [k, a.current_animation if a else "-",
				a.current_animation_position if a and a.current_animation != "" else -1.0, a.is_playing() if a else false,
				npc.casting_spell, npc.get("_action_left"), npc.get("_cast_clips"), (npc.info as Dictionary).has("cast_clips")])


func _log(s: String) -> void:
	print("[sp] %6d ms  %s" % [Time.get_ticks_msec() - t0, s])


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
