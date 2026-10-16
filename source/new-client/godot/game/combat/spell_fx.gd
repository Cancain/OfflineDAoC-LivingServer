class_name SpellFx
extends RefCounted
## Spell visuals and sounds, the client's way (content/spells/spell_fx.json from pipeline/build_spell_fx.py; the
## client's spells.csv / speffects.csv / spnifs.csv and sounds/cc_spells.csv):
##   begin   the spell's own casting animation (start, mid looping), its gather effects on the caster (the hand glows,
##           on the bones speffects names) and the sound set's "gather" sound;
##   fire    the gather effects go, the "cast" effects play on the caster with the "cast" sound;
##   bolt    a projectile effect flies to the target at 850 units / s (BoltSpellHandler) with the "travel" sound;
##   land    the target effect on the target ("targetchest" = chest height, "rootnode" = feet) and the "hit" sound;
##           a resisted spell shows the resist effect and the "resisted" sound instead;
##   fizzle  an interrupted cast drops its gather effects and plays the "fizzle" sound.
## Effects last speffects' Duration (ms) and are then freed. Each plays its NIF's own timeline from the start
## (NifScene.timeline: the particle emit windows, Gleam Ray's streak shown and stretched for half a second).
## Owner 2026-10-10 (Gleam Ray "way overblown, no ray, the explosion massive"): speffects "Auto Scale" = 1 scales the
## effect by the size of the character it sits on (size_of) - the effect NIFs are authored for a full-size figure
## (the explosion's sprites are 2.5 - 6 m), so on a badger cub it is a small pink puff, as in the owner's old-client
## clip; "Track Angle" turns the effect to face the target (the hand burst's streak becomes the ray toward the enemy).

const BOLT_SPEED_M := 850.0 * 0.025
static var _data := {}
static var _scenes := {}                    # gltf path -> NifScene template (duplicated per use)


static func data() -> Dictionary:
	if _data.is_empty():
		var p = JSON.parse_string(FileAccess.get_file_as_string("res://content/spells/spell_fx.json")) \
				if FileAccess.file_exists("res://content/spells/spell_fx.json") else null
		_data = p if p is Dictionary else {"effects": {}, "fx": {}}
	return _data


static func effect(client_effect: int) -> Dictionary:
	return (data().get("effects", {}) as Dictionary).get(str(client_effect), {})


# Pooled effects (owner 2026-10-10: 250 bots casting at 60+ fps): a finished effect goes back to its pool and the
# next cast of it restarts its timeline - copying a NIF scene (meshes, particle systems, animations) for every cast
# was ~1.4 ms each, ~40 ms a frame in a raid. Effects are also culled (Perf: off screen, beyond fx_range, or over
# max_effects alive - the nearest kept); the characters themselves always stay drawn.
const POOL_MAX := 48                        # spare copies kept per effect NIF
static var _pool := {}                      # gltf path -> [NifScene] ready to reuse
static var _live := {}                      # instance id -> NifScene playing now
static var _prune_at := 0


static func _instance(path: String) -> NifScene:
	var spare: Array = _pool.get(path, [])
	while not spare.is_empty():
		var p = spare.pop_back()
		if is_instance_valid(p):
			(p as NifScene).restart()
			return p
	var c := NifScene.copy_of(path)
	if c == null:
		return null
	c.timeline = true
	c.set_meta("fx_path", path)
	return c


## An effect is done: back to its pool (its bone holder freed), or freed when the pool is full.
static func release(node: Node) -> void:
	if not is_instance_valid(node):
		return
	var fx: NifScene = node as NifScene
	var holder: Node = null
	if fx == null:
		holder = node
		for c in node.get_children():
			if c is NifScene:
				fx = c
				break
	if fx == null:
		node.queue_free()
		return
	_live.erase(fx.get_instance_id())
	for c in fx.get_children():
		if c is _Track:
			c.queue_free()
	if fx.get_parent():
		fx.get_parent().remove_child(fx)
	if holder:
		holder.queue_free()
	var path := String(fx.get_meta("fx_path", ""))
	var spare: Array = _pool.get(path, [])
	if path == "" or spare.size() >= POOL_MAX:
		fx.queue_free()
		return
	spare.append(fx)
	_pool[path] = spare


static func _live_count() -> int:
	var now := Time.get_ticks_msec()
	if now >= _prune_at:                   # effects freed with their character's view
		_prune_at = now + 1000
		for k in _live.keys():
			if not is_instance_valid(_live[k]):
				_live.erase(k)
	return _live.size()


## Behind the loading screen: every effect the zone's monsters and your own spells can show is parsed and its
## textures loaded now, so the first cast of each doesn't stall the game (owner 2026-10-10: a long ~1 fps stretch
## when a crowd started casting). Returns how many effect models were made ready.
static func preload_effects(client_effects: Array) -> int:
	var paths := {}
	var fx: Dictionary = data().get("fx", {})
	for ce in client_effects:
		var e := effect(int(ce))
		var ids: Array = (e.get("gather", []) as Array) + (e.get("cast_fx", []) as Array)
		for k in ["projectile", "target", "resist"]:
			if int(e.get(k, 0)) > 0:
				ids.append(int(e[k]))
		for id in ids:
			var f: Dictionary = fx.get(str(id), {})
			if not f.is_empty():
				paths[String(f.nif)] = true
	for path in paths:
		var c := NifScene.copy_of(path)        # parses + packs once; the copy itself goes to the pool
		if c:
			c.timeline = true
			c.set_meta("fx_path", path)
			var spare: Array = _pool.get(path, [])
			spare.append(c)
			_pool[path] = spare
	return paths.size()


## The client effects a zone may need: its monsters' spells and the player's.
static func zone_effects(npc_states: Array) -> Array:
	var ces := {}
	for st in npc_states:
		for sid in (st as NpcState).spawn.get("spells", []):
			var ce := int(NpcCasting.spell(int(sid)).get("clienteffect", 0))
			if ce > 0:
				ces[ce] = true
	for line in ClassDb.spell_lines(PlayerData.class_id(), PlayerData.level, PlayerData.specs):
		for sid in line.spells:
			var ce := int(ClassDb.spell(int(sid)).get("clienteffect", 0))
			if ce > 0:
				ces[ce] = true
	return ces.keys()


## How big a character is to the client's Auto Scale, against a standard 1.85 m figure: a race figure's own scale
## (players, humanoid NPCs), a monster model's drawn height / 1.85. Measured against the owner's old-client Gleam Ray
## clip (2026-10-10): the caster's hand glows match at the elf figure's scale, and the hit on a badger cub (about a
## quarter metre tall) is a puff about 1 m across - its height ratio (~0.13), not its spawn size / 50 (0.42, which drew
## the explosion's 6 m purple flash).
const STANDARD_HEIGHT := 1.85
static var _heights := {}                   # model scene path -> its unscaled drawn height


static func size_of(on: Node3D) -> float:
	var m = on.get("model") if on.get("model") != null else on.get("_model")
	if not (m is Node3D):
		return 1.0
	var model := m as Node3D
	if model is Fig3Figure:
		return absf(model.scale.y)
	var info = on.get("info")
	var key := String((info as Dictionary).get("gltf", "")) if info is Dictionary else ""
	if key == "" or not _heights.has(key):
		var lo := INF
		var hi := -INF
		var inv := model.global_transform.affine_inverse()
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (inv * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).get_aabb()
			lo = minf(lo, b.position.y)
			hi = maxf(hi, b.end.y)
		if key == "":
			return (hi - lo if hi > lo else STANDARD_HEIGHT) * absf(model.scale.y) / STANDARD_HEIGHT
		_heights[key] = hi - lo if hi > lo else STANDARD_HEIGHT
	return float(_heights[key]) * absf(model.scale.y) / STANDARD_HEIGHT


## Keeps a tracking effect turned toward its target (speffects Track Angle) while its bone moves.
class _Track extends Node:
	var fx: Node3D
	var target: Node3D
	var height := 1.8

	func _process(_d: float) -> void:
		if not is_instance_valid(fx) or not is_instance_valid(target):
			queue_free()
			return
		var to := target.global_position + Vector3(0, height * 0.6, 0)
		var dir := to - fx.global_position
		if dir.length() > 0.01:
			var k := fx.global_basis.get_scale()
			fx.global_basis = Basis.looking_at(dir, Vector3.UP).scaled(k)


static func _skeleton(root: Node) -> Skeleton3D:
	if root == null:
		return null
	if root.has_meta("fx_skel"):                 # cached: walking a figure's 34 parts on every cast added up
		var c = root.get_meta("fx_skel")
		if c == null or is_instance_valid(c):
			return c
	var s := root.find_children("*", "Skeleton3D", true, false)
	var sk: Skeleton3D = s[0] if s.size() > 0 else null
	root.set_meta("fx_skel", sk)
	return sk


## One speffects entry on a character: on its bone, at its chest, or at its feet. Returns the node (freed after the
## effect's duration, or by the caller).
static var prof_play_us := 0                 # debug timing (tests/crowd_probe.gd)
const SAME_FX_MS := 400
const SAME_FX_MAX := 6
static var _fx_burst := {}                  # effect id -> [when its burst began (ticks ms), copies started in it]
static var prof_sound_us := 0


static func play(fx_id: int, on: Node3D, height := 1.8, keep := false, target: Node3D = null) -> Node3D:
	var t0 := Time.get_ticks_usec()
	var r := _play(fx_id, on, height, keep, target)
	prof_play_us += Time.get_ticks_usec() - t0
	return r


static func _play(fx_id: int, on: Node3D, height := 1.8, keep := false, target: Node3D = null) -> Node3D:
	var f: Dictionary = (data().get("fx", {}) as Dictionary).get(str(fx_id), {})
	if f.is_empty() or on == null or not on.is_inside_tree():
		return null
	# one effect landing on many at once (a group buff on eight, a crowd's same spell): at most SAME_FX_MAX copies
	# start in SAME_FX_MS (owner 2026-10-14) - the ones on you always show
	var now := Time.get_ticks_msec()
	var burst: Array = _fx_burst.get(fx_id, [0, 0])
	if now - int(burst[0]) > SAME_FX_MS:
		burst = [now, 0]
	if int(burst[1]) >= SAME_FX_MAX and not (on is Player):
		return null
	burst[1] = int(burst[1]) + 1
	_fx_burst[fx_id] = burst
	var cam := on.get_viewport().get_camera_3d()
	if cam and not Perf.brute:               # culled: off screen, too far, or too many alive (the nearest win)
		var d := cam.global_position.distance_to(on.global_position)
		if d > 6.0 and (d > Perf.fx_range or not cam.is_position_in_frustum(on.global_position + Vector3(0, 1, 0))
				or _live_count() >= Perf.max_effects):
			return null
	var node: Node3D = _instance(String(f.nif))
	if node == null:
		return null
	_live[node.get_instance_id()] = node
	var bone := String(f.get("node", ""))
	var skel := _skeleton(on)
	var bi := skel.find_bone(bone) if skel and bone.begins_with("Bip01") else -1
	var fx := node
	if bi >= 0:
		var at := BoneAttachment3D.new()
		at.bone_name = skel.get_bone_name(bi)
		skel.add_child(at)
		at.add_child(node)
		node = at
		# the bone's world scale (the model's) cancelled, then the effect's own size: the character's for Auto Scale
		var want := size_of(on) if bool(f.get("autoscale", false)) else 1.0
		fx.scale = Vector3.ONE * want / maxf(at.global_basis.get_scale().x, 0.001)
	else:
		on.add_child(node)
		var k := size_of(on) if bool(f.get("autoscale", false)) else 1.0
		fx.scale = Vector3.ONE * k / maxf(on.scale.y, 0.001)
		if bone.to_lower().contains("chest"):
			node.position.y = height * 0.6 / maxf(on.scale.y, 0.001)
		elif bone.to_lower().contains("head"):
			node.position.y = height * 0.9 / maxf(on.scale.y, 0.001)
	# the effect itself on the main thread, not the character's posing thread (NPC views pose on worker threads): its
	# timeline shows / hides its meshes, which only the main thread may do (owner 2026-10-11: the earth crack's plates
	# on an NPC logged hundreds of thread errors and didn't animate). Its bone attachment stays with the skeleton - the
	# posing thread moves it every frame (on the main thread, every bone-held effect on a bot logged an error a frame:
	# 100-500 thousand a session, the stutter near bots - owner 2026-10-13)
	AnimLod.keep_on_main(fx)
	if int(f.get("track", 0)) > 0 and target and is_instance_valid(target):
		var tr := _Track.new()
		tr.fx = fx
		tr.target = target
		tr.height = float(target.get("height")) if target.get("height") != null else 1.8
		fx.add_child(tr)
		tr._process(0.0)
	NifParticles.fit_to_scale(fx)
	for gp in (fx as NifScene).particles():
		(gp as GPUParticles3D).amount_ratio = Perf.particle_ratio   # fewer sparks in a busy fight (Perf governor)
	if not keep:
		var secs := float(f.get("duration_s", 3.0))
		on.get_tree().create_timer(secs if secs > 0.0 else 3.0).timeout.connect(func(): release(node))
	return node


static func sound(snd: CharacterSounds, set_id: int, event: String) -> void:
	if snd == null or set_id <= 0:
		return
	var t0 := Time.get_ticks_usec()
	_sound(snd, set_id, event)
	prof_sound_us += Time.get_ticks_usec() - t0


# Spells all at once (owner 2026-10-14: a group's buffs, a fight's casters - "sounds like an actual war zone"): the
# same spell sound starting again within SAME_SOUND_MS plays once, and only SPELL_SOUNDS_MAX spell sounds start in
# any SPELL_WINDOW_MS around you; your own spells always sound. (The character sounds' voice cap still applies.)
const SAME_SOUND_MS := 350
const SPELL_WINDOW_MS := 600
const SPELL_SOUNDS_MAX := 4
static var _sound_at := {}                  # spell sound name -> when it last started (ticks ms)
static var _sound_starts: Array = []        # when the spell sounds of the last SPELL_WINDOW_MS started


static func _sound(snd: CharacterSounds, set_id: int, event: String) -> void:
	var row: Dictionary = (snd.index.get("spells", {}) as Dictionary).get(str(set_id), {})
	var name := String(row.get(event, ""))
	if name == "":
		return
	var now := Time.get_ticks_msec()
	while not _sound_starts.is_empty() and now - int(_sound_starts[0]) > SPELL_WINDOW_MS:
		_sound_starts.pop_front()
	var mine := snd.get_parent() is Player
	if not mine and (now - int(_sound_at.get(name, -100000)) < SAME_SOUND_MS or _sound_starts.size() >= SPELL_SOUNDS_MAX):
		return
	_sound_at[name] = now
	_sound_starts.append(now)
	snd.play_structure(name)


## An emote's overlay (emotes.csv Spell column -> spells.csv): Pray 8005 (blue light shafts + a light sprinkle), Level
## Up 8007 (the big camelot knot under you), the realm binds 8010 / 8006 / 8009 - their effects on the character and
## their sound set's hit sound (set 10 for all of them), as the client played the server's emote.
static func emote(client_effect: int, on: Node3D, snd: CharacterSounds) -> void:
	var e := effect(client_effect)
	if e.is_empty() or on == null or not on.is_inside_tree():
		return
	for k in ["buildup", "target"]:
		if int(e.get(k, 0)) > 0:
			play(int(e[k]), on, 1.8)
	sound(snd, int(e.get("sound_set", 0)), "hit")


## The caster starts casting: returns the gather effects (to drop at fire / fizzle).
static func begin(client_effect: int, caster: Node3D, snd: CharacterSounds) -> Array:
	var e := effect(client_effect)
	var out := []
	var cam := caster.get_viewport().get_camera_3d() if caster.is_inside_tree() else null
	if cam and not Perf.brute and cam.global_position.distance_to(caster.global_position) > Perf.gather_range:
		sound(snd, int(e.get("sound_set", 0)), "gather")
		return out                           # a far caster's hand glows: off under load (Perf)
	for id in e.get("gather", []):
		var n := play(int(id), caster, 1.8, true)
		if n:
			out.append(n)
	sound(snd, int(e.get("sound_set", 0)), "gather")
	return out


static func drop(handles: Array) -> void:
	for n in handles:
		release(n)
	handles.clear()


static func fizzle(client_effect: int, handles: Array, snd: CharacterSounds) -> void:
	drop(handles)
	sound(snd, int(effect(client_effect).get("sound_set", 0)), "fizzle")


## The spell goes off: cast effects on the caster, the cast sound, and (for a bolt) the projectile toward the target.
## `then` runs when it arrives (immediately with no projectile).
static func fire(client_effect: int, handles: Array, caster: Node3D, snd: CharacterSounds, target: Node3D = null,
		then: Callable = Callable()) -> void:
	drop(handles)
	var e := effect(client_effect)
	# a character's caster effects (spells.csv Effect2 / 3) go with its casting animation: a spell with none (Anim1-3
	# all 0 - the skald's songs and chants) shows only its target effect (owner 2026-10-14: a skald showed the
	# minstrel's musical notes, alb_min_cst, where the original shows only the small blue effect over the head)
	var animated := (e.get("anims", []) as Array).any(func(a): return String(a) != "")
	var figure := caster is Player or (caster is Npc and (caster as Npc).model is Fig3Figure)
	if animated or not figure:
		for id in e.get("cast_fx", []):
			play(int(id), caster, 1.8, false, target)
	sound(snd, int(e.get("sound_set", 0)), "cast")
	var pid := int(e.get("projectile", 0))
	if pid > 0 and target and is_instance_valid(target) and caster.is_inside_tree():
		var f: Dictionary = (data().get("fx", {}) as Dictionary).get(str(pid), {})
		var bolt: Node3D = _instance(String(f.get("nif", ""))) if not f.is_empty() else null
		if bolt:
			caster.get_tree().current_scene.add_child(bolt)
			var from := caster.global_position + Vector3(0, 1.3, 0)
			var to := target.global_position + Vector3(0, 1.1, 0)
			bolt.global_position = from
			bolt.look_at(to, Vector3.UP, true) if from.distance_to(to) > 0.01 else null
			var secs := from.distance_to(to) / BOLT_SPEED_M
			sound(snd, int(e.get("sound_set", 0)), "travel")
			var tw := bolt.create_tween()
			tw.tween_property(bolt, "global_position", to, secs)
			tw.tween_callback(func():
				release(bolt)
				if then.is_valid(): then.call())
			return
	if then.is_valid():
		then.call()


## On the target: its effect (or the resist effect) and the hit / resisted sound (heard at the target if it has
## sounds, else at the caster).
## A cast effect with a release moment (its streak / flash shows partway in: Gleam Ray's ray at 0.93 s) holds the
## target effect and its sound until then, as the old client did (the ray first, then the puff); the damage itself is
## already dealt.
static func land(client_effect: int, target: Node3D, height: float, snd: CharacterSounds, resisted := false) -> void:
	var e := effect(client_effect)
	var wait := float(e.get("release_s", 0.0))
	if wait > 0.0 and target and target.is_inside_tree():
		await target.get_tree().create_timer(wait).timeout
		if not is_instance_valid(target) or not target.is_inside_tree():
			return
	var id := int(e.get("resist" if resisted else "target", 0))
	if id > 0:
		play(id, target, height)
	if not resisted and int(e.get("buildup", 0)) > 0 and int(e.buildup) != id:
		play(int(e.buildup), target, height)            # spells.csv Buildup Effect, with the target effect (a summon's
														# only one: Arawn's eyes on a necromancer's new servant)
	sound(snd, int(e.get("sound_set", 0)), "resisted" if resisted else "hit")
