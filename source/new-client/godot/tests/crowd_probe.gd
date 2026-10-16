extends Node
## Debug (owner 2026-10-10: "a couple hundred or more bots nearby animating and casting at once while being above 40
## fps"): a quiet baseline where you stand (Connla), then N humanoid NPCs (the zone's own race figures with their
## gear) in a ring 4-40 m around you, every one casting real spells (casting clip, gather effects, the spell going
## off at another bot, the hit, the sounds) - first with the frame-rate governor off, then on. Per phase: average
## FPS, 1% low, frame CPU (process) and physics time, draw calls, objects, video memory.
##   --screen 1 --skip-login --zone=202 --at=Connla --figure=cel_m --ui-test --probe=crowd_probe [--bots=250]
##   [--secs=20] [--target=60] [--out=<folder>]
var v: Node
var frames: Array = []
var recording := false
var bots: Array = []
var casts := 0
var spell_ces: Array = []
var use_anim := true
var use_fx := true
var use_sound := true
var churn := false


func _process(delta: float) -> void:
	if recording:
		frames.append(delta)
	if churn:                                               # one empty node added and freed per frame, nothing else
		var n := Node.new()
		add_child(n)
		n.queue_free()


func _phase(label: String, secs: float) -> void:
	frames.clear()
	await get_tree().create_timer(1.0).timeout                 # settle
	recording = true
	Npc.prof_us = 0
	AnimLod.prof_anim_us = 0
	AnimLod.prof_anim_n = 0
	NifScene.prof_us = 0
	SpellFx.prof_play_us = 0
	SpellFx.prof_sound_us = 0
	var f0 := Engine.get_process_frames()
	var c0 := casts
	var draws := 0.0
	var objs := 0.0
	var proc := 0.0
	var phys := 0.0
	var n := 0
	var t := 0.0
	while t < secs:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		n += 1
	recording = false
	var sorted := frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in frames:
		total += f
	var worst := sorted.slice(int(sorted.size() * 0.99)) if sorted.size() > 10 else sorted
	var w := 0.0
	for f in worst:
		w += f
	print("[crowd] %-26s fps avg %5.1f  1%% low %5.1f  process %5.1f ms  physics %5.1f ms  draws %5d  objects %5d  vram %4d MB  views %d  casts %d  governor level %.2f" % [
			label, frames.size() / maxf(total, 0.001), worst.size() / maxf(w, 0.001), proc / n, phys / n,
			int(draws / n), int(objs / n), int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
			v.npcs.active.size(), casts - c0, Perf.level])
	var nf := maxi(Engine.get_process_frames() - f0, 1)
	print("[crowd]    per frame: npc views %.1f ms (animation %.1f ms, %d advances/frame), effect scripts %.1f ms, effect spawning %.1f ms, sounds %.1f ms, effects alive %d, particle systems %d, voices %d" % [
			Npc.prof_us / 1000.0 / nf, AnimLod.prof_anim_us / 1000.0 / nf, AnimLod.prof_anim_n / nf, NifScene.prof_us / 1000.0 / nf,
			SpellFx.prof_play_us / 1000.0 / nf, SpellFx.prof_sound_us / 1000.0 / nf,
			get_tree().current_scene.find_children("*", "NifScene", true, false).size(),
			get_tree().current_scene.find_children("*", "GPUParticles3D", true, false).size(), CharacterSounds._voice_ends.size()])
	if v.args.has("out"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(v.args.out) + "/" + label.replace(" ", "_") + ".png")


func _cast_loop(n: Npc) -> void:
	await get_tree().create_timer(randf() * 3.0).timeout
	while is_instance_valid(n) and n.is_inside_tree():
		var ce: int = spell_ces[randi() % spell_ces.size()]
		var e := SpellFx.effect(ce)
		var other: Npc = bots[randi() % bots.size()] if bots.size() > 1 else n
		if use_anim and n.anim and n.anim.has_animation(String(e.get("anims", ["", "", ""])[1])):
			n.anim.play(String(e.anims[1]))
		var snd: CharacterSounds = n.sounds if use_sound else null
		var handles := SpellFx.begin(ce, n, snd) if use_fx else []
		if not use_fx and snd:
			SpellFx.sound(snd, int(e.get("sound_set", 0)), "gather")
		await get_tree().create_timer(randf_range(1.5, 2.8)).timeout
		if not is_instance_valid(n) or not n.is_inside_tree():
			SpellFx.drop(handles)
			return
		if use_fx and is_instance_valid(other) and other.is_inside_tree() and other != n:
			n.look_at(Vector3(other.global_position.x, n.global_position.y, other.global_position.z), Vector3.UP, true)
			SpellFx.fire(ce, handles, n, snd, other, func():
				if is_instance_valid(other) and other.is_inside_tree():
					SpellFx.land(ce, other, other.height, other.sounds if use_sound else null))
		else:
			SpellFx.drop(handles)
			if snd:
				SpellFx.sound(snd, int(e.get("sound_set", 0)), "cast")
				if is_instance_valid(other) and other.sounds:
					SpellFx.sound(other.sounds, int(e.get("sound_set", 0)), "hit")
		casts += 1
		if use_anim and n.anim and n.anim.has_animation(String(e.anims[2])):
			n.anim.play(String(e.anims[2]))
		await get_tree().create_timer(randf_range(1.0, 2.5)).timeout


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var secs := float(v.args.get("secs", "20"))
	var count := int(v.args.get("bots", "250"))
	# the spells bots cast: the classes' own client effects that have visuals
	var all: Dictionary = SpellFx.data().get("effects", {})
	for k in all:
		var e: Dictionary = all[k]
		if int(e.get("target", 0)) > 0 and not (e.get("gather", []) as Array).is_empty() and String((e.get("anims", ["", ""]) as Array)[1]) != "":
			spell_ces.append(int(k))
	spell_ces.shuffle()
	spell_ces = spell_ces.slice(0, 40)
	Perf.set_option("target_fps", 0)
	await _phase("quiet (no crowd)", secs)
	# the crowd: clones of the zone's humanoid figures with their equipment
	var templates := []
	for st in v.npcs.states:
		var s: NpcState = st
		if s.info.has("race") and String(s.spawn.get("equipment", "")) != "":
			templates.append(s)
	if templates.is_empty():
		for st in v.npcs.states:
			if (st as NpcState).info.has("race"):
				templates.append(st)
	var p: Vector3 = v.player.global_position
	for i in count:
		var src: NpcState = templates[i % templates.size()]
		var sp: Dictionary = src.spawn.duplicate(true)
		var ang := randf() * TAU
		var r := randf_range(4.0, 40.0)
		var x := p.x + cos(ang) * r
		var z := p.z + sin(ang) * r
		sp.id = "crowd%d" % i
		sp.pos = [x, v.zone.height_at(x, z), z]
		sp.roam = 0
		sp.aggro_level = 0
		sp.realm = PlayerData.realm_id()
		var st := NpcState.new(v.npcs.states.size(), sp, src.info)
		v.npcs.states.append(st)
	var t0 := Time.get_ticks_msec()
	v.npcs.prebuild()
	print("[crowd] built %d bots from %d templates in %d ms" % [count, templates.size(), Time.get_ticks_msec() - t0])
	var pbs := {}
	for k in Npc.prof_build:
		pbs[k] = "%d ms" % (int(Npc.prof_build[k]) / 1000)
	print("[crowd]    build time by part (all views): ", pbs)
	for st in v.npcs.states:
		if String((st as NpcState).spawn.id).begins_with("crowd") and (st as NpcState).view:
			bots.append((st as NpcState).view)
	t0 = Time.get_ticks_msec()                              # what the loading screen does for a zone's spells
	print("[crowd] preloaded %d effect models in %d ms" % [SpellFx.preload_effects(spell_ces), Time.get_ticks_msec() - t0])
	await _phase("crowd idle, governor off", secs)
	if v.args.has("split"):
		for bn in bots:
			bn.set_process(false)
		await _phase("idle, npc script only off", secs)
		for bn in bots:
			bn.set_process(true)
		await _phase("idle, back on", secs)
		for bn in bots:
			bn.process_mode = Node.PROCESS_MODE_DISABLED
		await _phase("idle, npc subtree paused", secs)
		for bn in bots:
			bn.process_mode = Node.PROCESS_MODE_INHERIT
		await _phase("idle, back on 2", secs)
		get_tree().quit()
		return
	if v.args.has("kids"):
		for kind in ["Skeleton3D", "CharacterSounds", "StaticBody3D", "AnimationPlayer", "Label3D"]:
			for bn in bots:
				for c in bn.find_children("*", kind, true, false):
					(c as Node).process_mode = Node.PROCESS_MODE_DISABLED
			await _phase("idle, %s paused (cumulative)" % kind, secs)
		get_tree().quit()
		return
	if v.args.has("budget"):
		for b in [40, 20, 10, 5, 0]:
			Perf.anim_budget = b
			Perf.anim_range = 0.01                       # everyone counts as far: only the budget animates
			await _phase("idle, %d skeleton updates/frame" % b, secs)
		get_tree().quit()
		return
	if v.args.has("diag"):
		var plates: Node = v.npcs.find_children("*", "NamePlates", false, false)[0] if v.npcs.find_children("*", "NamePlates", false, false).size() > 0 else null
		if plates:
			plates.process_mode = Node.PROCESS_MODE_DISABLED
		await _phase("idle, name plates frozen", secs)
		for bn in bots:
			bn.process_mode = Node.PROCESS_MODE_DISABLED
		await _phase("idle, npc scripts off", secs)
		v.npcs.set_physics_process(false)
		await _phase("idle, npc world sim off", secs)
		for bn in bots:
			bn.visible = false
		await _phase("idle, crowd hidden", secs)
		get_tree().quit()
		return
	if v.args.has("clips"):
		for clip in ["idle", "cast_crossed_mid", "walk", "cast_1h_circ_mid"]:
			for bn in bots:
				if bn.anim and bn.anim.has_animation(clip):
					bn.anim.play(clip)
			await _phase("all play " + clip, secs)
		get_tree().quit()
		return
	if v.args.has("churn"):
		churn = true
		await _phase("idle + 1 node freed/frame", secs)
		churn = false
		get_tree().quit()
		return
	for b in bots:
		_cast_loop(b)
	if v.args.has("variants"):
		use_fx = false
		use_sound = false
		await _phase("casting clips only", secs)
		use_fx = true
		use_anim = false
		use_sound = false
		await _phase("effects only (no sound)", secs)
		use_fx = false
		use_sound = true
		await _phase("sounds only", secs)
		use_anim = true
		use_fx = true
	await _phase("crowd, governor off", secs)
	Perf.set_option("target_fps", int(v.args.get("target", "60")))
	await get_tree().create_timer(4.0).timeout              # let it settle on a level
	await _phase("crowd, governor %s fps" % v.args.get("target", "60"), secs)
	get_tree().quit()
