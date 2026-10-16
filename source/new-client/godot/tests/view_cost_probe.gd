extends Node
## Debug (seamless zones): after a border crossing, which NPC views cost the frame? Crosses from Lough Derg into
## Silvermine, stands, then switches each view's processing off in turn and prints the frame time it saves.
##   --screen 1 --skip-login --zone=200 --figure=cel_m --probe=view_cost_probe [--single]
var v: Node


func _avg(n: int) -> float:
	var t := 0.0
	for i in n:
		var a := Time.get_ticks_usec()
		await get_tree().process_frame
		t += Time.get_ticks_usec() - a
	return t / n / 1000.0


func _ready() -> void:
	v = get_tree().current_scene
	var p: Player = v.player
	var region: RegionWorld = v.region
	await get_tree().create_timer(2.0).timeout
	if region:
		p.global_position = Vector3(500, region.height_at(500, 1450) + 0.5, 1450)
		while not region.zones.has(201):
			await get_tree().process_frame
	else:
		p.global_position = Vector3(500, v.zone.height_at(500, 7) + 0.5, 7)
	await get_tree().create_timer(4.0).timeout
	_phys("before crossing")
	p.global_position.z = 1645.0
	p.global_position.y = region.height_at(500, 1645) + 0.5 if region else p.global_position.y
	await get_tree().create_timer(11.0).timeout          # crossed, views built, settled
	_phys("after crossing")
	var nm: NpcManager = v.npcs
	nm.prof_phys_us = 0
	nm.prof_proc_us = 0
	var t0 := Time.get_ticks_usec()
	var fr0 := Engine.get_process_frames()
	var ph0 := Engine.get_physics_frames()
	await get_tree().create_timer(3.0).timeout
	var el := (Time.get_ticks_usec() - t0) / 1000.0
	print("[cost] over %.0f ms: %d frames, %d physics ticks; npc physics %.0f ms, npc process %.0f ms" % [el,
			Engine.get_process_frames() - fr0, Engine.get_physics_frames() - ph0, nm.prof_phys_us / 1000.0, nm.prof_proc_us / 1000.0])
	print("[cost] zone %s, %d views, nodes %d, frame %.1f ms" % [v.zone.info.name, nm.active.size(),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), await _avg(60)])
	var kinds := {}
	for c in nm.get_children():
		var k := c.get_class() + ("/" + (c.get_script() as Script).resource_path.get_file() if c.get_script() else "")
		kinds[k] = int(kinds.get(k, 0)) + 1
	print("[cost] npc manager children: ", kinds)
	for c in nm.get_children():
		if not (c is Npc):
			c.process_mode = Node.PROCESS_MODE_DISABLED
	print("[cost] non-view children off: %.1f ms" % await _avg(60))
	for c in nm.get_children():
		if not (c is Npc):
			c.process_mode = Node.PROCESS_MODE_INHERIT
	nm.set_process(false)
	print("[cost] manager _process off: %.1f ms" % await _avg(60))
	nm.set_process(true)
	nm.set_physics_process(false)
	print("[cost] manager _physics_process off: %.1f ms" % await _avg(60))
	nm.set_physics_process(true)
	var all_off := 0.0
	for i in nm.active:
		(nm.active[i] as Node).process_mode = Node.PROCESS_MODE_DISABLED
	all_off = await _avg(60)
	for i in nm.active:
		(nm.active[i] as Node).process_mode = Node.PROCESS_MODE_INHERIT
	var plates := nm.find_children("*", "NamePlates", false, false)
	print("[cost] every view's processing off: %.1f ms" % all_off)
	var base := await _avg(40)
	var rows := []
	for i in nm.active:
		var n: Npc = nm.active[i]
		n.process_mode = Node.PROCESS_MODE_DISABLED
		var t := await _avg(15)
		n.process_mode = Node.PROCESS_MODE_INHERIT
		var anims := n.find_children("*", "AnimationPlayer", true, false)
		var modes := []
		for a in anims:
			modes.append((a as AnimationPlayer).callback_mode_process)
		rows.append([base - t, "%s (model %s, zone %d, %d nodes, anim modes %s, particles %d)" % [n.spawn.name, n.spawn.get("model", "?"),
				n.state.zone_id, n.find_children("*", "", true, false).size(), modes, n.find_children("*", "GPUParticles3D", true, false).size()]])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("[cost] frame with all on: %.1f ms; biggest savings:" % base)
	for r in rows.slice(0, 10):
		print("[cost]   %.1f ms  %s" % [r[0], r[1]])
	get_tree().quit()


func _phys(label: String) -> void:
	print("[cost] %s: physics active %d, pairs %d, islands %d, fps %d" % [label, Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
			Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
			Engine.get_frames_per_second()])
