extends SceneTree
## Debug (owner 2026-10-11: a one-hander hangs straight down on the male Celt's hip, angled on the female): every
## race figure's belt / back attach bones - where they are and which way their axes point at rest.
##   --headless --path godot -s res://tests/belt_bone_dump.gd
func _initialize() -> void:
	for r in ["cel", "bri", "ava", "hig", "sar", "inc", "nor", "tro", "dwa", "kob", "val", "fir", "elf", "lur", "syl"]:
		for g in ["m", "f"]:
			var f := Fig3Figure.new()
			get_root().add_child(f)
			if not f.load_figure("%s_%s" % [r, g]):
				continue
			var sk: Skeleton3D = f.find_children("*", "Skeleton3D", true, false)[0]
			var ap: AnimationPlayer = f.anim
			if ap and ap.has_animation("idle"):
				ap.play("idle")
				ap.seek(0.3, true)
				ap.advance(0.0)
			var pi := sk.find_bone("Bip01 L Belt")
			var pel := sk.find_bone("Bip01 Pelvis")
			if pi >= 0 and pel >= 0:
				var pose := sk.get_bone_global_pose(pi)
				var pp := sk.get_bone_global_pose(pel)
				var local := pp.affine_inverse() * pose              # the belt in the pelvis' frame (animation's doing)
				var track := ap.get_animation("idle").find_track(NodePath("%s:Bip01 L Belt" % ap.get_parent().get_path_to(sk)), Animation.TYPE_ROTATION_3D) if ap else -1
				print("[belt] %s_%s idle: belt Y in pelvis frame %s, world Y %s, idle has a belt track: %s" % [r, g,
						local.basis.y.normalized().snapped(Vector3.ONE * 0.01), (sk.global_transform.basis * pose.basis).y.normalized().snapped(Vector3.ONE * 0.01), track >= 0])
			var line := "%s_%s" % [r, g]
			for bone in ["Bip01 L Belt", "Bip01 R Belt"]:
				var i := sk.find_bone(bone)
				if i < 0:
					line += "  %s: none" % bone
					continue
				var t := sk.get_bone_global_rest(i)
				var parent := sk.get_bone_name(sk.get_bone_parent(i))
				# the weapon model's long axis is its local Y (NIF up): how far that tilts from straight down / up
				var y := t.basis.y.normalized()
				var tilt := rad_to_deg(acos(clampf(absf(y.y), 0.0, 1.0)))
				line += "  %s (parent %s): pos %s  Y %s  tilt %.0f deg  scale %s" % [bone.trim_prefix("Bip01 "), parent,
						t.origin.snapped(Vector3.ONE * 0.01), y.snapped(Vector3.ONE * 0.01), tilt, t.basis.get_scale().snapped(Vector3.ONE * 0.01)]
			print("[belt] ", line)
			f.free()
	quit()
