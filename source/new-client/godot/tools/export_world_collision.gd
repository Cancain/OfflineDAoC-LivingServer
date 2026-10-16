extends SceneTree
## Bot plan phase 3: each built zone's collision exactly as the game builds it (ZoneLoader), for the world host - which
## runs bots without loading a zone's graphics. Written next to the zone: content/zones/zoneNNN/world/
##   floor.f32     every fixture floor triangle in world space (float32 x y z per vertex): the floor layer the floor
##                 pick reads (with the zone's height grid outside cities)
##   walls.f32     every wall triangle (collidee faces of Collide fixtures + ladders' climb walls): the wall layer
##   navfloor.f32  the floors of SOLID fixtures only - buildings, bridges, docks, stairs (Collide fixtures with collidee
##                 geometry) - what the navigation bakes as walkable besides the ground (tree canopies, bushes and
##                 props baked into hundreds of thousands of islands Godot's navigation map couldn't join - phase 0)
##   meta.json     size, height grid file / size / cell, city, spots (arrival / start points), camps (monster spawns:
##                 pos, level, aggro range), exits (the zone's jump quads), triangle counts
##   Godot --headless --path godot -s res://tools/export_world_collision.gd -- [zone ids...]   (none: every built zone)


func _initialize() -> void:
	var ids: Array = []
	for a in OS.get_cmdline_user_args():
		ids.append(int(a))
	if ids.is_empty():
		var idx = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zones_index.json"))
		for k in idx:
			if FileAccess.file_exists("res://content/zones/zone%03d/zone.json" % int(k)):
				ids.append(int(k))
		ids.sort()
	var t0 := Time.get_ticks_msec()
	for id in ids:
		_export(int(id))
	print("[world] %d zones in %d s" % [ids.size(), (Time.get_ticks_msec() - t0) / 1000])
	quit()


func _export(zone_id: int) -> void:
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
	var nav := _solid_floors(zl, dir)
	var wdir := ProjectSettings.globalize_path(dir.path_join("world"))
	DirAccess.make_dir_recursive_absolute(wdir)
	_save(wdir.path_join("floor.f32"), floors)
	_save(wdir.path_join("walls.f32"), walls)
	_save(wdir.path_join("navfloor.f32"), nav)
	var camps := []
	var npcs = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("npcs.json")))
	for s in (npcs.get("spawns", []) if npcs is Dictionary else []):
		if int(s.get("realm", 0)) != 0:
			continue                                   # realm 0: monsters (guards, merchants and trainers belong to realms)
		var p = s.get("pos")
		p = JSON.parse_string(p) if p is String else p
		camps.append({"pos": p, "level": int(s.get("level", 1)), "aggro": float(s.get("aggro_range", 0)) * 0.025,
				"aggressive": int(s.get("aggro_level", 0)) > 0, "name": String(s.get("name", ""))})
	var meta := {"id": zone_id, "name": zl.info.name, "size_m": float(zl.info.size_m), "city": zl.city,
			"heights": String(zl.info.get("heights_2x", zl.info.heights)), "hsize": zl.hsize, "cell": zl.cell,
			"spots": zl.info.get("spots", []), "exits": zl.info.get("exits", []), "camps": camps,
			"floor_tris": floors.size() / 3, "wall_tris": walls.size() / 3, "navfloor_tris": nav.size() / 3}
	var mf := FileAccess.open(wdir.path_join("meta.json"), FileAccess.WRITE)
	mf.store_string(JSON.stringify(meta))
	mf.close()
	print("[world] zone %3d %-24s floors %7d  walls %6d  solid floors %6d  camps %4d  %5d ms" % [zone_id, zl.info.name,
			floors.size() / 3, walls.size() / 3, nav.size() / 3, camps.size(), Time.get_ticks_msec() - t0])
	zl.free()


## The visible faces of every Collide fixture whose model has collidee geometry (a building, bridge, dock, stair),
## placed the way ZoneLoader places its floors (scaled, then turned by yaw or a dungeon piece's full basis).
func _solid_floors(zl: ZoneLoader, dir: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	var parts_of := {}
	for f in zl.info.fixtures:
		if not f.get("collide", false) or f.get("no_collision", false):
			continue
		var m := int(f.m)
		if not parts_of.has(m):
			parts_of[m] = zl._load_model(dir.path_join(zl.info.models[m].file))
		var parts: Dictionary = parts_of[m]
		if parts.is_empty() or (parts.collision as PackedVector3Array).is_empty():
			continue
		var vf: PackedVector3Array = parts.visible_faces
		var sc := float(f.scale)
		var origin := Vector3(f.pos[0], f.pos[1], f.pos[2])
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(f.yaw))), origin)
		if f.has("basis"):
			var bb: Array = f.basis
			xf = Transform3D(Basis(Vector3(bb[0], bb[1], bb[2]), Vector3(bb[3], bb[4], bb[5]), Vector3(bb[6], bb[7], bb[8])), origin)
		var base := out.size()
		out.resize(base + vf.size())
		for k in vf.size():
			out[base + k] = xf * (vf[k] * sc)
	return out


func _save(path: String, v: PackedVector3Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(v.to_byte_array())
	f.close()
