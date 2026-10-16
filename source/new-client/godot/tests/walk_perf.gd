extends Node
## Debug (owner 2026-10-14: hitches and fps drops in Tir na Nog, "try moving around too"): the player runs a loop
## through the zone (run speed, around --pos) for --secs while NPC views come and go; every frame over 33 ms is
## listed with what the NPC manager built in it, then the view build broken down by step (Npc.prof_build: figure
## load, look, dress, monster instance / anims ...) and the model parses (NpcManager.prof_parse_us).
##   --screen 1 -- --skip-login --zone=209 --pos=580.25,191.5,689.35 --figure=elf_m --ui-test --probe=walk_perf
var v: Node
var t := 0.0
var walking := false
var centre := Vector3.ZERO
var radius := 60.0
var slow: Array = []
var frames := 0
var total := 0.0
var last_built := 0
var _pipe_last := 0
var _pipe_start := 0
var _snd_last := 0
var _build_last := 0
var _wall0 := 0                                    # the walk's wall clock vs the sum of the deltas the engine gave
var _inflated := 0                                 # frames whose delta was over twice the wall time since the last
var _t_proc := 0                                   # this frame's main-thread marks: our _process, pre-draw, post-draw
var _t_pre := 0
var _t_post := 0
var _span := [0, 0, 0, 0, 0, 0]                             # last frame: process -> pre-draw, pre -> post draw, post -> next


## Pipelines compiled so far (draw / specialization / surface / mesh): a first-time draw's cost.
func _pipelines() -> int:
	var n := 0
	for k in [RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION,
			RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE, RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH]:
		n += int(RenderingServer.get_rendering_info(k))
	return n


var _t_phys := 0                                   # this frame's first physics tick (the frame: post-draw -> ticks -> process)
var _ticks := 0


func _physics_process(_d: float) -> void:
	if _t_phys <= _t_proc:
		_t_phys = Time.get_ticks_usec()
	_ticks += 1


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ph := _t_phys > _t_proc and _t_phys > _t_post
	_span = [(now - _t_proc) / 1000, (_t_pre - _t_proc) / 1000 if _t_pre > _t_proc else -1,
			(_t_post - _t_pre) / 1000 if _t_post > _t_pre and _t_pre > _t_proc else -1,
			(_t_phys - _t_post) / 1000 if ph else -1, (now - _t_phys) / 1000 if ph else (now - _t_post) / 1000, _ticks]
	_ticks = 0
	_t_proc = now
	if not walking:
		return
	if delta > 0.03 and delta * 1000.0 > 2.0 * float(_span[0]) + 5.0:
		_inflated += 1
	t += delta
	frames += 1
	total += delta
	var mgr: NpcManager = v.npcs
	var parts: Dictionary = Perf.frame_parts           # what ran since the last frame (the time delta measures)
	Perf.frame_parts = {}
	if _span[0] > 33:                                  # (the wall time: a stall early in the frame shows in its delta one late)
		var top := ""
		var ks := parts.keys()
		ks.sort_custom(func(x, y): return int(parts[x]) > int(parts[y]))
		for k in ks.slice(0, 4):
			top += "%s %.0f " % [k, int(parts[k]) / 1000.0]
		top += "| wall %d: process %d, draw %d, to the ticks %d, ticks %d (%d) | " % _span
		top += "build %.0f process %.0f physics %.0f" % [(mgr.prof_build_us - _build_last) / 1000.0,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0]
		slow.append([snappedf(t, 0.01), int(_span[0]), mgr.prof_built - last_built, mgr.active.size(),
				int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
				_pipelines() - _pipe_last, (ZoneAudio.load_us + CharacterSounds.load_us - _snd_last) / 1000, top])
	_build_last = mgr.prof_build_us
	_pipe_last = _pipelines()
	_snd_last = ZoneAudio.load_us + CharacterSounds.load_us
	last_built = mgr.prof_built
	var a := t * 7.0 / radius                                   # 7 m/s around the loop
	var p := centre + Vector3(cos(a), 0.0, sin(a)) * radius
	p.y = mgr.ground_at(Vector3(p.x, centre.y + 30.0, p.z)) + 0.05
	v.player.global_position = p


func _ready() -> void:
	v = get_tree().current_scene
	RenderingServer.frame_pre_draw.connect(func(): _t_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func(): _t_post = Time.get_ticks_usec())
	var secs := 40.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.get_slice("=", 1))
		elif a.begins_with("--radius="):
			radius = float(a.get_slice("=", 1))
	await get_tree().create_timer(8.0).timeout
	v.ui.visible = false
	centre = v.player.global_position
	var mgr: NpcManager = v.npcs
	Npc.prof_build.clear()
	Npc.prof_peak.clear()
	var b0: int = mgr.prof_build_us
	var n0: int = mgr.prof_built
	var p0: int = mgr.prof_parse_us
	var q0: int = mgr.prof_parsed
	last_built = mgr.prof_built
	_pipe_start = _pipelines()
	_pipe_last = _pipe_start
	walking = true
	_wall0 = Time.get_ticks_usec()
	await get_tree().create_timer(secs).timeout
	walking = false
	print("[walk] wall %.2f s, sum of deltas %.2f s, %d frames with a delta over twice their wall time" % [
			(Time.get_ticks_usec() - _wall0) / 1e6, total, _inflated])
	print("[walk] pipelines compiled during the walk: ", _pipelines() - _pipe_start)
	var own := 0                                          # the server's game: every living is the server's (an oid)
	for st in mgr.states:
		if mgr is ServerWorld and not (st as NpcState).spawn.has("oid"):
			own += 1
	print("[walk] spawns %d, of them not the server's: %d" % [mgr.states.size(), own])
	print("[walk] %d frames, avg fps %.1f, %d frames over 33 ms" % [frames, frames / total, slow.size()])
	slow.sort_custom(func(x, y): return x[1] > y[1])
	print("[walk] worst frames [t s, ms, views built, views alive, nodes, draws, pipelines compiled, sound load ms, parts ms]: ", slow.slice(0, 15))
	var built: int = mgr.prof_built - n0
	print("[walk] views built %d, %.1f ms each on average; model parses %d, %.1f ms total" % [built,
			(mgr.prof_build_us - b0) / 1000.0 / maxi(built, 1), mgr.prof_parsed - q0, (mgr.prof_parse_us - p0) / 1000.0])
	var keys := Npc.prof_build.keys()
	keys.sort_custom(func(x, y): return int(Npc.prof_build[x]) > int(Npc.prof_build[y]))
	for k in keys:
		print("[walk]   %-14s %.1f ms total, %.2f ms per view, longest %.1f ms" % [k, int(Npc.prof_build[k]) / 1000.0,
				int(Npc.prof_build[k]) / 1000.0 / maxi(built, 1), int(Npc.prof_peak.get(k, 0)) / 1000.0])
	get_tree().quit()
