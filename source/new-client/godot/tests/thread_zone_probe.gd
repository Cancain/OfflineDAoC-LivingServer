extends Node
## Debug (seamless zones): can a neighbour zone be built on a worker thread while you play, and placed beside yours
## without a hitch? Builds Silvermine Mts. (201, south of Lough Derg in region 200) off the tree, measures the frame
## times on the main thread meanwhile, adds it at its region offset and looks across the border.
##   --screen 1 --skip-login --zone=200 --figure=cel_m --probe=thread_zone_probe --out=<folder>
var v: Node
var _zone: ZoneLoader
var _done := false
var _worst := 0.0
var _frames := 0
var _long := 0


func _build(dir: String) -> void:
	var z := ZoneLoader.new()
	z.name = "Neighbour"
	z.load_zone(dir, "blend", "x4plus")
	_zone = z
	_done = true


func _process(delta: float) -> void:
	if not _done and _zone == null and _frames >= 0:
		_frames += 1
		_worst = maxf(_worst, delta)
		if delta > 0.034:
			_long += 1


func _ready() -> void:
	v = get_tree().current_scene
	var out := String(v.args.get("out", "user://thread"))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(6.0).timeout
	var idx = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zones_index.json"))
	var me: Dictionary = idx["200"]
	var nb: Dictionary = idx["201"]
	var offset := Vector3((float(nb.x) - float(me.x)) * 204.8, 0, (float(nb.y) - float(me.y)) * 204.8)
	print("[thread] neighbour offset ", offset)
	_frames = 0
	_worst = 0.0
	var t0 := Time.get_ticks_msec()
	var task := WorkerThreadPool.add_task(_build.bind("res://content/zones/zone201"))
	while not _done:
		await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(task)
	var built_ms := Time.get_ticks_msec() - t0
	print("[thread] built on a worker in %d ms; main-thread frames meanwhile %d, worst %.1f ms, over 34 ms: %d" % [built_ms, _frames, _worst * 1000.0, _long])
	_frames = -1
	var t1 := Time.get_ticks_usec()
	_zone.position = offset
	v.add_child(_zone)
	print("[thread] added to the world in %.1f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	var worst2 := 0.0
	for i in 60:
		var t2 := Time.get_ticks_usec()
		await get_tree().process_frame
		worst2 = maxf(worst2, (Time.get_ticks_usec() - t2) / 1000.0)
	print("[thread] first 60 frames after adding: worst %.1f ms" % worst2)
	# look at the border (Lough Derg's south edge at z = 1638.4): straight down on it, then low along it
	var p: Player = v.player
	var bx := float(v.args.get("bx", "800"))
	p.global_position = Vector3(bx, v.zone.height_at(bx, 1600) + 2.0, 1600)
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	var gy: float = v.zone.height_at(bx, 1637)
	var shots := [["down", Vector3(bx, gy + 45.0, 1638.4), Vector3(bx + 0.01, gy, 1638.4)],
			["along", Vector3(bx - 40.0, gy + 6.0, 1636.0), Vector3(bx + 60.0, gy, 1640.0)],
			["across", Vector3(bx, gy + 12.0, 1600.0), Vector3(bx, gy, 1680.0)]]
	for sh in shots:
		cam.global_position = sh[1]
		cam.look_at(sh[2], Vector3.FORWARD if sh[0] == "down" else Vector3.UP)
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("border_%s_%d.png" % [sh[0], int(bx)]))
	print("[thread] done")
	get_tree().quit()
