extends Node
## Debug (owner 2026-10-17: "spawn in 8 companions somewhere remote and cast black plague on yourselves"): the server
## can't cast Dyranapur's Black Plague without its boss (a scripted spell), so this feeds the client what the server
## sends in that fight - SpellEffectAnimation client effect 4375 on every group member every --every s (the boss's 450
## radius AoE), its Lifedrain (2610) on one member every 1.5 s - at Iarnvidiur's Lair entrance with a full /spawn
## group, and logs frame rate, the worst frame, memory, video memory, nodes and live effects every 2 s. Runs once.
var v: Node
var _worst := 0.0
var _last := 0


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last > 0:
		_worst = maxf(_worst, (now - _last) / 1000.0)
	_last = now


func _ready() -> void:
	var secs := float(get_tree().current_scene.args.get("secs", "120"))
	var every := float(get_tree().current_scene.args.get("every", "1.0"))
	get_tree().create_timer(minf(secs + 60.0, 200.0)).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	await _wait(8.0)
	Server.command("/jump to 34991 37707 17231 161")          # Iarnvidiur's Lair, its entrance
	await _wait(10.0)
	for c in String(v.args.get("party", "Hero,Druid,Champion,Mentalist,Blademaster,Warden,Bard")).split(","):
		Server.command("/spawn " + c)
		await _wait(1.5)
	await _wait(8.0)
	var sw: ServerWorld = v.npcs
	var oids: Array = [Server.me_oid]
	for m in PlayerData.group_rows():
		if not bool(m.get("me", false)) and int(m.get("oid", 0)) > 0:
			oids.append(int(m.oid))
	print("[sim] group oids ", oids)
	var t0 := Time.get_ticks_msec()
	var next_plague := 0.0
	var next_drain := 0.0
	var next_log := 2.0
	var casts := 0
	_worst = 0.0
	while true:
		await get_tree().process_frame
		var t := (Time.get_ticks_msec() - t0) / 1000.0
		if t >= secs:
			break
		if t >= next_plague:
			next_plague += every
			casts += 1
			for o in oids:
				sw._spell_effect({"caster": 0, "target": o, "spell": 4375, "bolt": 0, "no_sound": 0, "success": 1})
		if t >= next_drain:
			next_drain += 1.5
			sw._spell_effect({"caster": 0, "target": oids.pick_random(), "spell": 2610, "bolt": 0, "no_sound": 0, "success": 1})
		if t >= next_log:
			next_log += 2.0
			print("[sim] t=%3d fps %5.1f worst %6.1f ms  mem %5.0f MB  vram %5.0f MB  nodes %5d  orphans %4d  live fx %3d  plagues %d" % [
					int(t), Engine.get_frames_per_second(), _worst,
					Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
					Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
					Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
					SpellFx._live.size(), casts])
			_worst = 0.0
	print("[sim] done")
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
