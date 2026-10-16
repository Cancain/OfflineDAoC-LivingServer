extends Node
## Look-only: bone-by-bone difference between the idle pose right after spawning and the idle pose after a short run
## (owner: "if you move it fixes itself").
func _pose(sk: Skeleton3D) -> Array:
	var out := []
	for i in sk.get_bone_count():
		out.append(sk.get_bone_pose(i))
	return out


func _ready() -> void:
	UiArt.settings_path = "user://settings_uitest.cfg"          # never the owner's settings
	var zv: Node = load("res://game/zone_viewer.tscn").instantiate()
	add_child(zv)
	await get_tree().create_timer(3.0).timeout
	var p: Node = zv.get("player")
	var root: Node3D = p.get("_model")
	var sk: Skeleton3D = root.find_children("*", "Skeleton3D", true, false)[0]
	var ap: AnimationPlayer = p.get("_anim")
	ap.seek(1.0, true)
	var a := _pose(sk)
	p.set("autorun", true)
	await get_tree().create_timer(1.0).timeout
	p.set("autorun", false)
	await get_tree().create_timer(2.0).timeout
	ap.seek(1.0, true)
	var b := _pose(sk)
	for i in sk.get_bone_count():
		var ra: Transform3D = a[i]
		var rb: Transform3D = b[i]
		var ang := rad_to_deg(ra.basis.get_rotation_quaternion().angle_to(rb.basis.get_rotation_quaternion()))
		var mv := ra.origin.distance_to(rb.origin)
		if ang > 0.2 or mv > 0.01:
			print("%-22s rot diff %.2f deg  move %.3f   spawn %s   after-run %s" % [sk.get_bone_name(i), ang, mv,
					ra.basis.get_rotation_quaternion(), rb.basis.get_rotation_quaternion()])
	print("rest pelvis ", sk.get_bone_rest(sk.find_bone("Bip01 Pelvis")).basis.get_rotation_quaternion())
	get_tree().quit()
