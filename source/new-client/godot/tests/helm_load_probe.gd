extends Node
func _ready() -> void:
	for path in ["res://content/helms/hibrp01_cel_m__b_hat01/model.gltf", "res://content/weapons/h_st_staff05/model.gltf"]:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		var err := doc.append_from_file(ProjectSettings.globalize_path(path), st)
		print(path, " err=", err, " images=", st.get_images().size(), " textures=", st.get_textures().size())
		var scene := doc.generate_scene(st)
		for mi in scene.find_children("*", "MeshInstance3D", true, false):
			var m = (mi as MeshInstance3D).get_active_material(0)
			print("   mat ", m, " tex=", m.albedo_texture if m is BaseMaterial3D else "?")
	get_tree().quit()
