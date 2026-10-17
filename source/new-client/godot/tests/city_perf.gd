extends Node
## Debug (owner 2026-10-14: Tir na Nog 39-49 fps CPU-bound with ~200 NPCs drawn): where the main thread's time goes
## in a busy city. Phases of --secs each, standing still: baseline; NPC animations frozen; name plates off; NPC views
## hidden and not processed. Per phase: average fps, 1% low, Performance TIME_PROCESS, NpcManager's own process time,
## NPC views alive.
##   --screen 1 -- --skip-login --zone=209 --pos=580.25,191.5,689.35 --figure=elf_m --ui-test --probe=city_perf [--secs=8]
var v: Node
var frames: Array = []
var procs: Array = []
var recording := false


func _process(delta: float) -> void:
	if recording:
		frames.append(delta)
		procs.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)


func _ready() -> void:
	v = get_tree().current_scene
	var secs := 8.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.get_slice("=", 1))
	await get_tree().create_timer(12.0).timeout              # zone in, NPC views built
	await _phase("baseline", secs)
	var mgr: NpcManager = v.npcs
	for n in mgr.active.values():                          # animations frozen
		if n.anim:
			(n.anim as AnimationPlayer).active = false
	await _phase("anims frozen", secs)
	for n in mgr.active.values():
		if n.anim:
			(n.anim as AnimationPlayer).active = true
	var plates := get_tree().root.find_children("*", "NamePlates", true, false)
	for p in plates:
		p.process_mode = Node.PROCESS_MODE_DISABLED
		(p as CanvasItem).visible = false if p is CanvasItem else true
	await _phase("plates off", secs)
	for p in plates:
		p.process_mode = Node.PROCESS_MODE_INHERIT
	for n in mgr.active.values():                          # views hidden, not processed
		n.visible = false
		n.process_mode = Node.PROCESS_MODE_DISABLED
	await _phase("npc views off", secs)
	get_tree().quit()


func _phase(name: String, secs: float) -> void:
	var mgr: NpcManager = v.npcs
	frames.clear()
	procs.clear()
	var p0: int = mgr.prof_proc_us
	recording = true
	await get_tree().create_timer(secs).timeout
	recording = false
	var n := frames.size()
	var total := 0.0
	for f in frames:
		total += f
	var sorted := frames.duplicate()
	sorted.sort()
	var low := 1.0 / float(sorted[int(n * 0.99)]) if n > 0 else 0.0
	var pavg := 0.0
	for p in procs:
		pavg += p
	pavg /= maxf(n, 1)
	print("[city] %-14s fps %.1f  1%%low %.1f  process %.1f ms  npc mgr %.2f ms/frame  views %d  draws %d" % [name,
			n / total, low, pavg, (mgr.prof_proc_us - p0) / 1000.0 / maxf(n, 1), mgr.active.size(),
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))])
