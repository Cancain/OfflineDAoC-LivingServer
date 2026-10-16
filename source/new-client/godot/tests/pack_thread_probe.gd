extends Node
## Debug (seamless zones): pack a zone's monster models on a worker thread while the game draws - does any hang?
##   --screen 1 --skip-login --zone=200 --figure=cel_m --probe=pack_thread_probe [--pack_zone=202]
var v: Node
var _i := 0
var _now := ""


func _work(paths: Array) -> void:
	for p in paths:
		_now = p
		var t := Time.get_ticks_msec()
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		state.base_path = ProjectSettings.globalize_path(String(p).get_base_dir())
		var ok := doc.append_from_file(p, state)
		var t1 := Time.get_ticks_msec()
		var root := doc.generate_scene(state) if ok == OK else null
		var t2 := Time.get_ticks_msec()
		var packed := PackedScene.new()
		if root:
			packed.pack(root)
			root.free()
		print("[pack] %s parse %d ms, generate %d ms, pack %d ms" % [String(p).get_file(), t1 - t, t2 - t1, Time.get_ticks_msec() - t2])
		_i += 1


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(3.0).timeout
	var nm: NpcManager = v.npcs
	var zid := int(v.args.get("pack_zone", "202"))
	var t = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zone%03d/npcs.json" % zid))
	var paths := []
	for s in t.spawns:
		var info: Dictionary = nm.models.get(String(s.get("model", "")), {})
		if info.has("gltf") and not paths.has(String(info.gltf)) and not nm._scenes.has(String(info.gltf)):
			paths.append(String(info.gltf))
	print("[pack] %d models to pack for zone %d" % [paths.size(), zid])
	var task := WorkerThreadPool.add_task(_work.bind(paths))
	var t0 := Time.get_ticks_msec()
	var last := -1
	while not WorkerThreadPool.is_task_completed(task):
		await get_tree().process_frame
		if _i == last and Time.get_ticks_msec() - t0 > 20000:
			print("[pack] STUCK on ", _now)
			t0 = Time.get_ticks_msec()
		if _i != last:
			last = _i
			t0 = Time.get_ticks_msec()
	print("[pack] done, main thread alive")
	get_tree().quit()
