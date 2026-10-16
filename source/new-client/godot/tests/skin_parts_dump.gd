extends SceneTree
## Debug: a race figure's parts - each mesh, its part, texture and tint mode (skin tones on bare skin).
##   --headless --path godot -s res://tests/skin_parts_dump.gd -- --prefix=kob_m
func _initialize() -> void:
	var prefix := "cel_m"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--prefix="):
			prefix = a.trim_prefix("--prefix=")
	var f := Fig3Figure.new()
	get_root().add_child(f)
	f.load_figure(prefix)
	f.apply({"skin": 7})
	print("[parts] ", prefix, " tint parts ", f.meta.get("skin_tint_parts"), " clothes ", f.meta.get("clothes"))
	for mi in f.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).material_override as ShaderMaterial
		var tex = m.get_shader_parameter("albedo_tex") if m else null
		print("[parts]   %s visible %s tex %s mode %s" % [mi.name, (mi as MeshInstance3D).is_visible_in_tree(),
				(tex as Texture2D).resource_path.get_file() if tex is Texture2D and (tex as Texture2D).resource_path != "" else str(tex),
				m.get_shader_parameter("tint_mode") if m else "-"])
	quit()
