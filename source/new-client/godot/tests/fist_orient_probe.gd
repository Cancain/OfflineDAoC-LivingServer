extends Node3D
## Debug, headless (owner 2026-10-17: a savage's right-hand fist weapon points sideways instead of stabbing): every
## hand-to-hand weapon (weapons.json stance 13) dressed by Player.dress in each hand of a Norse figure, measured
## against the forearm (Bip01 Forearm -> Hand): how far it reaches past the fist along the arm (FWD), back along the
## arm (BACK) and out to the side (SIDE), in cm. A blade that stabs reaches FWD; SIDE >> FWD = pointing sideways.
## Writes user://fist_orient.txt. Runs once.
##   Godot --headless --path godot res://tests/fist_orient_probe.tscn [-- <race>]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var race := String(args[0]) if args.size() > 0 else "nor_m"
	var f := Fig3Figure.new()
	add_child(f)
	f.load_figure(race)
	var skel := f.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var clip := String(args[1]) if args.size() > 1 else ""      # a pose: the clip's first frame (else the rest pose)
	if clip != "":
		var ap := f.model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.play(clip)
		ap.seek(float(args[2]) if args.size() > 2 else 0.0, true)
		ap.pause()
	await get_tree().process_frame
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://content/weapons/weapons.json"))
	var ids: Array = []
	for k in (data.models as Dictionary).keys():
		if int(data.models[k].get("stance", 0)) == 13:
			ids.append(int(k))
	ids.sort()
	var lines := ["race %s, pose %s: model nif | right hand (bone: FWD BACK SIDE cm) | left hand (bone: FWD BACK SIDE)" % [race, clip if clip != "" else "rest"]]
	var bad := 0
	for id in ids:
		var info: Dictionary = data.models[str(id)]
		var row := "%5d %-40s" % [id, String(info.nif)]
		for slot in [10, 11]:
			var shield: bool = int(info.get("shield", 0)) > 0 and slot == 11
			var item_at := func(s: int) -> Dictionary:
				return {"model": id, "object_type": 42 if shield else 0} if s == slot else {}
			var made: Array = Player.dress(f.model, item_at, "standard", true, false)
			await get_tree().process_frame
			var side := "R" if slot == 10 else "L"
			var hand := (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Bip01 %s Hand" % side))).origin
			var fore := (skel.global_transform * skel.get_bone_global_pose(skel.find_bone("Bip01 %s Forearm" % side))).origin
			var arm := (hand - fore).normalized()
			var fwd := -INF
			var back := INF
			var perp := 0.0
			var bone := ""
			for a in made:
				bone = String((a as BoneAttachment3D).bone_name).replace("Bip01 ", "")
				for mi in (a as Node).find_children("*", "MeshInstance3D", true, false):
					var m := mi as MeshInstance3D
					for s in m.mesh.get_surface_count():
						for v in m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
							var d: Vector3 = m.global_transform * v - hand
							var p := d.dot(arm)
							fwd = maxf(fwd, p)
							back = minf(back, p)
							perp = maxf(perp, (d - arm * p).length())
				(a as Node).queue_free()
			if made.is_empty():
				row += " | %s: none" % side
				continue
			var flag := "" if fwd * 100.0 >= 8.0 and fwd >= perp * 0.6 else "  <-- NOT FORWARD"
			if flag != "":
				bad += 1
			row += " | %s %-8s %5.0f %5.0f %5.0f%s" % [side, bone, fwd * 100.0, -back * 100.0, perp * 100.0, flag]
		lines.append(row)
	lines.append("%d hands not pointing forward" % bad)
	var out := FileAccess.open("user://fist_orient.txt", FileAccess.WRITE)
	out.store_string("\n".join(lines) + "\n")
	out.close()
	print("\n".join(lines))
	get_tree().quit()
