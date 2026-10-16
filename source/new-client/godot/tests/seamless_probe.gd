extends Node
## Debug (seamless zones, bot plan priority 1): start in a zone, let the region's neighbours stream in, then travel in
## a straight line over the borders at a set speed (default the horse routes' 37.5 m/s) - no scene reload may happen.
## Prints when each neighbour loads, every crossing, the NPC count, frame times (worst / over 34 ms) per stretch, and
## saves a look back over each border just after crossing it.
##   --screen 1 --skip-login --zone=200 --figure=cel_m --probe=seamless_probe --out=<folder>
##     [--from=500,1450] [--dir=0,1] [--metres=3600] [--speed=37.5]
var v: Node
var _worst := 0.0
var _long := 0
var _frames := 0
var _start_scene: Node


func _process(delta: float) -> void:
	_frames += 1
	_worst = maxf(_worst, delta)
	if delta > 0.034:
		_long += 1


func _stretch(label: String) -> void:
	print("[seamless] %s: %d frames, worst %.1f ms, over 34 ms: %d, fps now %d | draws %d, objects %d, prims %dk, process %.1f ms, physics %.1f ms, nodes %d, video %d MB" % [label, _frames, _worst * 1000.0, _long,
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576])
	if v.npcs:
		var nm: NpcManager = v.npcs
		print("[seamless]    npc views: built %d in %d ms, model parses %d in %d ms, ticks %d ms, active %d" % [nm.prof_built,
				nm.prof_build_us / 1000, nm.prof_parsed, nm.prof_parse_us / 1000, nm.prof_tick_us / 1000, nm.active.size()])
		nm.prof_built = 0
		nm.prof_build_us = 0
		nm.prof_parsed = 0
		nm.prof_parse_us = 0
		nm.prof_tick_us = 0
	_frames = 0
	_worst = 0.0
	_long = 0


func _ready() -> void:
	v = get_tree().current_scene
	_start_scene = v
	var out := String(v.args.get("out", "user://seamless"))
	DirAccess.make_dir_recursive_absolute(out)
	var from := String(v.args.get("from", "500,1450")).split(",")
	var dir := String(v.args.get("dir", "0,1")).split(",")
	var metres := float(v.args.get("metres", "3600"))
	var speed := float(v.args.get("speed", "37.5"))
	var p: Player = v.player
	var region: RegionWorld = v.region
	if region == null:                                   # --single-zone: the same ride inside one zone (a baseline)
		print("[seamless] no region (single zone)")
	else:
		region.zone_added.connect(func(z: ZoneLoader): print("[seamless] +%s (%d) at %s, t=%.1f s" % [z.info.name, int(z.info.id), z.position, Time.get_ticks_msec() / 1000.0]))
	var start := Vector3(float(from[0]), 0, float(from[1]))
	var hz: Object = region if region else v.zone
	p.global_position = Vector3(start.x, hz.height_at(start.x, start.z) + 0.5, start.z)
	var step := Vector3(float(dir[0]), 0, float(dir[1])).normalized()
	p.face(atan2(-step.x, -step.z))
	await get_tree().create_timer(1.0).timeout
	_stretch("settle")
	# the first neighbours stream in while we stand (test runs have no loading screen)
	var t0 := Time.get_ticks_msec()
	while region and (region._task >= 0 or region.zones.size() < 2):
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 40000:
			break
	print("[seamless] standing: %d zones loaded after %.1f s, %d NPC states" % [region.zones.size() if region else 1, (Time.get_ticks_msec() - t0) / 1000.0, v.npcs.states.size() if v.npcs else 0])
	_stretch("streaming while standing")
	# travel
	var zone_before := int(v.zone.info.id)
	var gone := 0.0
	var bisect: bool = v.args.has("bisect")
	var cross_at := 0.0
	var crossings := 0
	var cam := Camera3D.new()
	v.add_child(cam)
	while gone < metres:
		await get_tree().physics_frame
		if get_tree().current_scene != _start_scene:
			print("[seamless] FAIL the scene reloaded (a loading screen) at %.0f m" % gone)
			return
		var dt := get_physics_process_delta_time()
		var q := p.global_position + step * speed * dt
		q.y = hz.height_at(q.x, q.z) + 0.3
		p.global_position = q
		p.velocity = Vector3.ZERO
		gone += speed * dt
		if bisect and crossings > 0 and int((gone - cross_at) / 100.0) != int((gone - cross_at - speed * dt) / 100.0):
			_bisect_step(int((gone - cross_at) / 100.0))
		elif gone > 0.0 and int(gone / 200.0) != int((gone - speed * dt) / 200.0):
			_stretch("ride %d m" % int(gone))
		if int(v.zone.info.id) != zone_before:
			crossings += 1
			cross_at = gone
			_stretch("ride into %s" % v.zone.info.name)
			print("[seamless] crossing %d: now in %s (%d), player at %s, %d zones loaded, %d NPC states, %d views" % [crossings,
					v.zone.info.name, int(v.zone.info.id), p.global_position.snapped(Vector3.ONE * 0.1), region.zones.size() if region else 1,
					v.npcs.states.size() if v.npcs else 0, v.npcs.active.size() if v.npcs else 0])
			zone_before = int(v.zone.info.id)
			# look back over the border just crossed
			var here := p.global_position
			cam.global_position = here + step * 30.0 + Vector3(0, 18.0, 0)
			cam.look_at(here - step * 60.0)
			cam.current = true
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("cross_%d_%s.png" % [crossings, String(v.zone.info.name).replace(" ", "_").replace(".", "")]))
			cam.current = false
	_stretch("ride end")
	print("[seamless] done: %d crossings, %.0f m, ended in %s, zones loaded %s" % [crossings, gone, v.zone.info.name, region.zones.keys() if region else []])
	get_tree().quit()


## --bisect: every 100 m one more system stops processing - which one was eating the frame?
var _off: Array = []


func _bisect_step(k: int) -> void:
	var wl: Node = get_node_or_null("/root/WorldLink")
	var gb: Node = wl.get("bots") if wl else null
	var old_zones := []
	if v.region:
		for id in v.region.zones:
			if v.region.zones[id] != v.zone:
				old_zones.append(v.region.zones[id])
	var groups := [["nothing off", []], ["gamebots off", [gb] if gb else []], ["other zones off", old_zones],
			["grass off", v.clutters.values()], ["npc views off", [v.npcs]],
			["quest markers off", v.find_children("QuestMarkers", "", true, false)], ["region off", [v.region]],
			["sky off", [v.sky]], ["audio off", [v.audio]], ["ui off", [v.ui]], ["combat off", [v.combat]]]
	if k - 1 >= 0 and k - 1 < groups.size():
		_stretch("with %s" % groups[k - 1][0])
	if k < groups.size():
		for n in groups[k][1]:
			if n is Node and is_instance_valid(n):
				(n as Node).process_mode = Node.PROCESS_MODE_DISABLED
				if n is ZoneLoader:
					(n as ZoneLoader).visible = false
