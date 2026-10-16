extends Node
## Debug (time_stack_probe): in the new world - its clock against the server's, then the NPC heights; a proper /quit.


func _ready() -> void:
	var first := get_tree().current_scene
	var s: Node = null
	for i in 80:
		await get_tree().create_timer(0.25).timeout
		s = get_tree().current_scene
		if s != first and s and s.get("sky") and s.get("npcs"):
			break
	print("[ts] new world built: sky %.2f h, server clock %.2f h" % [s.sky.hour(), Server.game_hour()])
	await get_tree().create_timer(10.0).timeout
	print("[ts] 10 s in: sky %.2f h, server clock %.2f h" % [s.sky.hour(), Server.game_hour()])
	var worst := {}
	for k in 6:
		await get_tree().create_timer(5.0).timeout
		var w = s.npcs
		for st: NpcState in w.states:
			if st.view == null or st.swimming or st.ride_clip != "" or bool(w._mover.get(st, {}).get("flying", false)):
				continue
			var ground: float = w._grid_at(st.pos)
			var floor_y: float = w.floor_at(Vector3(st.pos.x, float(w._mover.get(st, {}).get("sy", st.pos.y)), st.pos.z))
			var over: float = st.pos.y - maxf(ground, floor_y)
			if over > 0.3 and over > float(worst.get(st, [0.0])[0]):
				worst[st] = [over, String(st.spawn.get("name", "?")), st.pos.y - ground]
		print("[ts] sample %d: %d drawn NPCs, %d above their floor" % [k, w.states.size(), worst.size()])
	var list := worst.values()
	list.sort_custom(func(a, b): return a[0] > b[0])
	for e in list.slice(0, 10):
		print("[ts]   %s %.2f m over its floor (%.2f m over the terrain)" % [e[1], e[0], e[2]])
	Server.quit_world(true)
