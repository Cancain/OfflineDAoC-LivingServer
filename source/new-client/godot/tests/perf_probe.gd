extends Node
## Debug: where frame time goes at a spot (draw calls, objects, NPC views, process / physics time), then with the
## NPC views hidden, then with the name plates hidden.
##   --skip-login --zone=209 "--at=Tir na Nog bind area" --figure=cel_m --ui-test --probe=perf_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(8.0).timeout
	await _measure("all")
	var views := []
	for s in viewer.npcs.states:
		if (s as NpcState).view:
			views.append((s as NpcState).view)
	for v in views:
		var plate = v.get_meta("plate") if v.has_meta("plate") else null
		for pl in (plate if plate is Array else [plate]):
			if pl is Node3D:
				pl.visible = false
	await _measure("no plates")
	for v in views:
		var a: AnimationPlayer = v.anim if "anim" in v else null
		if a:
			a.active = false
	await _measure("no plates, no npc animation")
	for v in views:
		v.visible = false
	await _measure("no npcs drawn")
	get_tree().quit()


func _measure(label: String) -> void:
	await get_tree().create_timer(1.0).timeout
	var t0 := Time.get_ticks_usec()
	for i in 120:
		await get_tree().process_frame
	var fps := 120.0 / ((Time.get_ticks_usec() - t0) / 1e6)
	var n := 0
	for s in viewer.npcs.states:
		if (s as NpcState).view:
			n += 1
	print("[perf] %s: %.0f fps, draw calls %d, objects %d, primitives %d, npc views %d, process %.1f ms, physics %.1f ms" % [label, fps,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), n,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
