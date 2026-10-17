extends Node
## Debug: the belt bones' orientation (skeleton space, idle frame 0) on the Bonedancer commander vs a Norse figure.
func _ready() -> void:
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	doc.append_from_file(ProjectSettings.globalize_path("res://content/monsters/bonedancerpet__bonedancerpet01/model.gltf"), st)
	var bd := doc.generate_scene(st) as Node3D
	add_child(bd)
	var f := Fig3Figure.new()
	add_child(f)
	f.load_figure("nor_m")
	await get_tree().process_frame
	for pair in [["commander", bd], ["nor_m", f.model]]:
		var root: Node3D = pair[1]
		var ap := root.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.play("idle")
		ap.seek(0.0, true)
		var sk := root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		for bn in ["Bip01 R Belt", "Bip01 L Belt", "Bip01 R Held", "Bip01 Pelvis", "Bip01 R Thigh"]:
			var i := sk.find_bone(bn)
			if i < 0:
				print("[belt] ", pair[0], " ", bn, " MISSING")
				continue
			var g := sk.global_transform * sk.get_bone_global_pose(i)
			var rest := sk.get_bone_rest(i)
			print("[belt] %s %s x=%s y=%s z=%s | rest basis x=%s parent=%s anim_track=%s" % [pair[0], bn,
					(g.basis.x.normalized()).snapped(Vector3.ONE * 0.01), (g.basis.y.normalized()).snapped(Vector3.ONE * 0.01),
					(g.basis.z.normalized()).snapped(Vector3.ONE * 0.01), rest.basis.x.normalized().snapped(Vector3.ONE * 0.01),
					sk.get_bone_name(sk.get_bone_parent(i)), _has_track(ap, bn)])
	get_tree().quit()


func _has_track(ap: AnimationPlayer, bone: String) -> bool:
	var a := ap.get_animation("idle")
	for t in a.get_track_count():
		if String(a.track_get_path(t)).ends_with(":" + bone):
			return true
	return false
