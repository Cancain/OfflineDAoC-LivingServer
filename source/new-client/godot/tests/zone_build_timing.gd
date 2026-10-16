extends SceneTree
## Debug (seamless zones): how long each part of a zone's build takes, to plan loading neighbours in the background.
##   --path godot -s res://tests/zone_build_timing.gd -- --zones=200,201,202
func _initialize() -> void:
	await process_frame
	var ids := "200,201,202"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--zones="):
			ids = a.trim_prefix("--zones=")
	for id in ids.split(","):
		var z := ZoneLoader.new()
		get_root().add_child(z)
		var dir := "res://content/zones/zone%03d" % int(id)
		z.dir = dir
		z.info = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("zone.json")))
		z.city = bool(z.info.get("city", false))
		z.terrain_set = "blend" if z.terrain_sets().has("blend") else ("" if z.terrain_sets().is_empty() else z.terrain_sets()[0])
		z.texture_set = "x4plus" if z.info.texture_sets.has("x4plus") else "original"
		var folders := {}
		for k in z.info.texture_sets:
			folders[k] = dir.path_join(z.info.texture_sets[k])
		z.materials = NifMaterials.new(folders, z.texture_set)
		var t := Time.get_ticks_usec()
		var times := {}
		z._load_heights()
		times.heights = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		if not z.city:
			z._build_terrain()
			times.terrain = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
			z._build_water()
			times.water = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		z._build_fixtures()
		times.fixtures = Time.get_ticks_usec() - t; t = Time.get_ticks_usec()
		z._build_lights()
		times.lights = Time.get_ticks_usec() - t
		var msg := "[build] zone %s %s:" % [id, z.info.name]
		for k in times:
			msg += "  %s %d ms" % [k, times[k] / 1000]
		print(msg, "  | static mem %d MB, video %d MB" % [OS.get_static_memory_usage() / 1048576,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576])
	quit()
