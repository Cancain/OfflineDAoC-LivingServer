extends Node
## Debug (owner 2026-10-10: "super low framerate when you first load into the game"): every half second for the first
## 40 s after the zone loads - FPS, frame / process / physics time, draw calls, objects, nodes, pipeline (shader)
## compilations, video memory, NPC views.
##   --screen 1 --skip-login --zone=200 --figure=cel_m --ui-test --probe=load_fps_probe [--near=<npc name>] [--secs=40]
## --near: stand by that NPC from the first frame (Lethantis Guard in Campacorentin, Captain Alphin in Camelot).
var t := 0.0
var placed := false
var next := 0.0
var last_frames := 0
var last_t := 0.0


func _process(delta: float) -> void:
	t += delta
	var v0 := get_tree().current_scene
	if not placed and v0.get("npcs") and v0.args.has("near") and not v0.args.has("with-loading"):
		placed = true
		for st in v0.npcs.states:
			if String((st as NpcState).spawn.name) == String(v0.args.near):
				v0.player.global_position = (st as NpcState).pos + Vector3(1.5, 0.3, 0)
				print("[fps] placed by ", v0.args.near, " at ", (st as NpcState).pos)
				break
	if t < next:
		return
	next += 0.5
	var v := get_tree().current_scene
	var frames := Engine.get_process_frames()
	var fps := (frames - last_frames) / maxf(t - last_t, 0.001)
	last_frames = frames
	last_t = t
	var comp := 0
	for m in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH,
			Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW,
			Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		comp += int(Performance.get_monitor(m))
	var views: int = v.npcs.active.size() if v.get("npcs") and v.npcs else -1
	var loading := not v.find_children("*", "LoadingScreen", false, false).is_empty()
	print("[fps] t=%5.1f fps=%5.1f process=%5.1fms physics=%5.1fms draws=%d objects=%d nodes=%d pipelines=%d vram=%dMB npc_views=%d%s" % [
			t, fps, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), comp,
			int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0), views, " LOADING" if loading else ""])
	if t > float(get_tree().current_scene.args.get("secs", "40")):
		print("[fps] memory: textures %d MB, buffers %d MB, total video %d MB; static memory %d MB" % [
				int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
				int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0),
				int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
				int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)])
		get_tree().quit()
