extends SceneTree
## Debug (owner 2026-10-10: shield not centred on the back): where each race's back / spine bones sit (rest pose,
## figure space, DAoC units; x = side, y = forward/back, z = up).
##   --headless --path godot -s res://tests/back_bones_probe.gd


func _initialize() -> void:
	for race in ["bri_m", "bri_f", "elf_m", "cel_m", "nor_m", "tro_m", "lur_m", "dwa_m", "fir_m", "kob_m"]:
		var path := "res://content/characters/races/%s/figure.gltf" % race
		if not FileAccess.file_exists(path):
			continue
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
			continue
		var root := doc.generate_scene(st)
		var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
		var out: String = race + ":"
		for b in ["Bip01 Spine2", "Bip01 L Back", "Bip01 R Back", "Bip01 L Shield"]:
			var i := sk.find_bone(b)
			if i < 0:
				out += "  %s -" % b
				continue
			var p := sk.get_bone_global_rest(i).origin
			out += "  %s (%.1f %.1f %.1f)" % [b.trim_prefix("Bip01 "), p.x, p.y, p.z]
		print(out)
		root.free()
	quit()
