extends SceneTree
## Bot plan phase 0 (owner 2026-10-10, the C# vs GDScript host test): a zone's collision exactly as the game builds it
## (ZoneLoader), saved for the separate host_bench project - which reads files, never this project's scripts.
##   Godot --headless --path godot -s res://tools/export_bench_zone.gd -- <out dir> <zone id> [<zone id> ...]
## Per zone, <out dir>/zoneNNN/:
##   meta.json   size_m, hsize, cell, city, spots (arrival / start points), camps (monster spawns: pos, level,
##               aggro range - the camps bots pick and the areas to route around)
##   heights.f32 the ground grid the game's floor pick uses outside cities (heights_2x when there)
##   floor.f32   every fixture floor triangle in world space (float32 x y z per vertex) - the floor layer's faces
##   walls.f32   every wall triangle (collidee faces of Collide fixtures + ladders' climb walls) - the wall layer


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := String(args[0])
	for i in range(1, args.size()):
		_export(int(args[i]), out)
	quit()


func _export(zone_id: int, out: String) -> void:
	var t0 := Time.get_ticks_msec()
	var dir := "res://content/zones/zone%03d" % zone_id
	var zl := ZoneLoader.new()
	root.add_child(zl)
	zl.load_zone(dir)
	var floors := PackedVector3Array()
	var walls := PackedVector3Array()
	for body_name in ["FloorBodies", "FixtureBodies", "ClimbBodies"]:
		var body := zl.get_node_or_null(body_name)
		if body == null:
			continue
		for cs in body.get_children():
			var shape := (cs as CollisionShape3D).shape as ConcavePolygonShape3D
			if shape == null:
				continue
			var faces := shape.get_faces()
			var xf: Transform3D = (cs as CollisionShape3D).transform
			var dst := floors if body_name == "FloorBodies" else walls
			var base := dst.size()
			dst.resize(base + faces.size())
			for k in faces.size():
				dst[base + k] = xf * faces[k]
	var zdir := out.path_join("zone%03d" % zone_id)
	DirAccess.make_dir_recursive_absolute(zdir)
	_save(zdir.path_join("floor.f32"), floors)
	_save(zdir.path_join("walls.f32"), walls)
	var hf := FileAccess.open(zdir.path_join("heights.f32"), FileAccess.WRITE)
	hf.store_buffer(zl.heights.to_byte_array())
	hf.close()
	var camps := []
	var npcs = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("npcs.json")))
	for s in (npcs.get("spawns", []) if npcs is Dictionary else []):
		if int(s.get("realm", 0)) != 0:
			continue                                   # realm 0: monsters (guards, merchants and trainers belong to realms)
		var p = s.get("pos")
		p = JSON.parse_string(p) if p is String else p
		var lv = s.get("level", 1)
		camps.append({"pos": p, "level": int(lv), "aggro": float(s.get("aggro_range", 0)) * 0.025,
				"aggressive": int(s.get("aggro_level", 0)) > 0})
	var meta := {"id": zone_id, "name": zl.info.name, "size_m": float(zl.info.size_m), "hsize": zl.hsize, "cell": zl.cell,
			"city": zl.city, "spots": zl.info.get("spots", []), "camps": camps,
			"floor_tris": floors.size() / 3, "wall_tris": walls.size() / 3}
	var mf := FileAccess.open(zdir.path_join("meta.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify(meta, " "))
	mf.close()
	print("[export] zone %d %s: %d floor tris, %d wall tris, %d camps, grid %d, %d ms" % [zone_id, zl.info.name,
			floors.size() / 3, walls.size() / 3, camps.size(), zl.hsize, Time.get_ticks_msec() - t0])
	zl.free()


func _save(path: String, v: PackedVector3Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(v.to_byte_array())
	f.close()
