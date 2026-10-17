extends Node
## Debug (owner 2026-10-14: pet summons' casting animation / sound timing - bonedancer, sluaghbinder ... - as the old
## client): on a test server run, each summon spell you have is cast and its timeline logged in ms from the cast
## request: the server's cast and effect packets, the pet's creation and when its view is drawn, every clip your figure
## plays, every spell effect started (and on whom), every sound played. --class=<id>: a GM class change first (yourself
## targeted; back to the Animist at the end).
const SUMMON_TYPES := ["Spore Spewer", "Grove's Eliminator", "Forest's Compatriot", "Tangler Youngling",
		"Summon Bone Boss", "Summon Bone Master", "Summon Bonecrusher", "Summon Bone Warmage", "Summon Boneknitter",
		"Raise Shambling Dead", "Call Minor Zombie Servant", "Summon Spirit Fighter", "Underhill Friend",
		"Call Minor Nature Spirit", "Amber Simulacrum"]
var v: Node
var t0 := 0
var watching := false
var _clip := ""
var _fx_seen := {}
var _snd_seen := 0
var _pet := 0
var _pet_drawn := false


func _ready() -> void:
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k):
		if watching:
			_log("chat: " + String(t)))
	Server.world.connect(_on_world)
	await _wait(8.0)
	Server.use("srv:spell:0:1")                             # (a cast ends the GM's login stealth)
	await _wait(5.0)
	var cls := int(String(v.args.get("class", "0")))
	if cls > 0:
		Server.client.call("Target", Server.me_oid, 0x6000)
		await _wait(1.0)
		Server.command("/player class %d" % cls)
		await _wait(4.0)
	var casts := []
	for li in Server.spell_lines.size():
		for sp in Server.spell_lines[li].spells:
			if String(sp.name) in SUMMON_TYPES:
				casts.append(["srv:spell:%d:%d" % [li, int(sp.level)], String(sp.name)])
	print("[sum] summons known: ", casts.map(func(c): return c[1]))
	for c in casts.slice(0, 3):
		print("[sum] ===== ", c[1])
		_pet = 0
		_pet_drawn = false
		_fx_seen = {}
		var snd: CharacterSounds = v.player.get("sounds")
		_snd_seen = snd.play_log.size() if snd else 0
		t0 = Time.get_ticks_msec()
		watching = true
		Server.use(String(c[0]))
		await _wait(14.0)
		watching = false
		Server.command("/pet release")
		await _wait(3.0)
	if cls > 0:
		Server.client.call("Target", Server.me_oid, 0x6000)
		await _wait(1.0)
		Server.command("/player class 55")
		await _wait(3.0)
	Server.quit_world(true)


func _on_world(kind: String, d: Dictionary) -> void:
	if not watching:
		return
	match kind:
		"cast":
			if int(d.caster) == Server.me_oid:
				_log("CAST packet: effect %d, cast time %.1f s" % [int(d.spell), int(d.get("time", 0)) / 10.0])
		"spell_effect":
			if int(d.caster) == Server.me_oid or int(d.caster) == _pet:
				_log("EFFECT packet: effect %d, caster %d -> target %d%s" % [int(d.spell), int(d.caster), int(d.target),
						" (the pet)" if int(d.target) == _pet else ""])
		"npc":
			if _pet == 0:
				_pet = int(d.oid)
				_log("PET created: oid %d %s (model %d)" % [_pet, String(d.get("name", "")), int(d.model) & 0x7FFF])
		"interrupt":
			if int(d.caster) == Server.me_oid:
				_log("INTERRUPT packet")


func _process(_delta: float) -> void:
	if not watching or v == null or v.player == null:
		return
	var a: AnimationPlayer = v.player.get("_anim")
	var clip: String = a.current_animation if a else ""
	if clip != _clip:
		_clip = clip
		_log("your clip: " + clip)
	if _pet != 0 and not _pet_drawn and v.npcs is ServerWorld and (v.npcs as ServerWorld)._view_of(_pet) != null:
		_pet_drawn = true
		_log("PET drawn (its view built)")
	for k in SpellFx._live:
		if not _fx_seen.has(k) and is_instance_valid(SpellFx._live[k]):
			_fx_seen[k] = true
			var n: Node = SpellFx._live[k]
			var who: String = "you" if v.player.is_ancestor_of(n) else ("the pet" if _pet != 0 and (v.npcs as ServerWorld)._view_of(_pet) \
					and (v.npcs as ServerWorld)._view_of(_pet).is_ancestor_of(n) else "elsewhere")
			_log("effect started: %s on %s" % [String(n.get_meta("fx_path", "?")).get_base_dir().get_file(), who])
	var snd: CharacterSounds = v.player.get("sounds")
	if snd and snd.play_log.size() != _snd_seen:
		for i in range(mini(_snd_seen, snd.play_log.size()), snd.play_log.size()):
			_log("your sound: %s" % [snd.play_log[i]])
		_snd_seen = snd.play_log.size()


func _log(s: String) -> void:
	print("[sum] %6d ms  %s" % [Time.get_ticks_msec() - t0, s])


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
