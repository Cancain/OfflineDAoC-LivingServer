extends SceneTree
## Debug: each mesh of a zone model and its box.  -s res://tests/model_aabb_probe.gd -- res://content/zones/zone000/models/b-rndtw2.gltf


func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		doc.append_from_file(ProjectSettings.globalize_path(path), st)
		var root := doc.generate_scene(st)
		for m in root.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			var xf: Transform3D = mi.transform
			var n: Node = mi.get_parent()
			while n != root and n is Node3D:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			var mats := []
			for i in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(i)
				mats.append(mat.resource_name if mat else "-")
			print("[aabb] ", mi.name, " ", xf * mi.get_aabb(), " surfaces ", mi.mesh.get_surface_count(), " ", mats)
		root.free()
	quit()
