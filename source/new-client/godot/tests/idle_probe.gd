extends Node
## Debug: run the zone for --secs (default 20) and quit (log counting, e.g. thread errors). --toggle-fight: every NPC
## drawn flips in and out of combat every 2 s (weapons drawn / sheathed).
func _ready() -> void:
	var secs := 20.0
	var toggle := "--toggle-fight" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			secs = float(a.get_slice("=", 1))
	var viewer := get_tree().current_scene
	var t := 0.0
	var flips := 0
	while t < secs:
		await get_tree().create_timer(2.0).timeout
		t += 2.0
		if toggle and viewer.get("npcs"):
			for s in viewer.npcs.states:
				var st: NpcState = s
				if st.view:
					st.fighting = not st.fighting
					flips += 1
	var nm = viewer.npcs
	if "--rebuild" in OS.get_cmdline_user_args():
		for st in nm.states:
			if st.view:
				st.view.free()
				st.view = null
		nm.active.clear()
		await get_tree().process_frame
		nm.prof_built = 0
		nm.prof_build_us = 0
		Npc.prof_build.clear()
		var tw := Time.get_ticks_usec()
		nm.update_views(1 << 30)
		print("[idle] rebuild wall ", (Time.get_ticks_usec() - tw) / 1000.0, " ms")
	print("[idle] views built ", nm.prof_built, " in ", nm.prof_build_us / 1000.0, " ms; parts ", Npc.prof_build)
	if "--bench-models" in OS.get_cmdline_user_args():
		var rows := []
		for k in nm._scenes:
			var ps: PackedScene = nm._scenes[k]
			if ps == null:
				continue
			var tq := Time.get_ticks_usec()
			var n := ps.instantiate()
			var t_inst := Time.get_ticks_usec() - tq
			var res := 0
			for c in n.find_children("*", "", true, false):
				res += 1
			n.free()
			rows.append([t_inst, k, res])
		rows.sort_custom(func(a, b): return a[0] > b[0])
		for r in rows.slice(0, 12):
			print("[idle] inst %.2f ms nodes %d %s" % [r[0] / 1000.0, r[2], r[1]])
	print("[idle] done, flips ", flips, " nodes ", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	get_tree().quit()
