extends Node
## Debug: close-ups of the held / sheathed weapon (alignment with the hand) and a swing. Run with
##   --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=weapon_probe --out=<folder>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var out := String(viewer.args.get("out", "user://weapon_probe"))
	DirAccess.make_dir_recursive_absolute(out)
	var p: Player = viewer.player
	var c: Combat = viewer.combat
	p.cam_distance = 1.7
	p.cam_pitch = -0.15
	for view in [["sheathed_back", 0.0, false], ["sheathed_side", PI * 0.5, false], ["held_side", -PI * 0.5, true],
			["held_front", PI, true]]:
		if c:
			c.set_attack_mode(view[2])
		p.cam_yaw = p.char_yaw + float(view[1])
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, view[0]])
	var skel: Skeleton3D = p._model.find_children("*", "Skeleton3D", true, false)[0]
	for bone in ["Bip01 R Hand", "Bip01 R Held", "Bip01 R Finger1"]:
		var i := skel.find_bone(bone)
		print("%s at %s" % [bone, (skel.global_transform * skel.get_bone_global_pose(i)).origin])
	for g in p._gear:
		print("gear on %s at %s" % [(g as BoneAttachment3D).bone_name, (g as Node3D).global_position])
	p.cam_yaw = p.char_yaw - PI * 0.5
	p.swing("")
	for k in 3:
		await get_tree().create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/swing_%d.png" % [out, k])
	get_tree().quit()
