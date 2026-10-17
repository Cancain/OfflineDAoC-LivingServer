extends Node
## Debug (owner 2026-10-10: "the idle tilt is most noticeable when you make a new character without moving"): front,
## side and back pictures of the freshly spawned player in idle, plus the skeleton root / pelvis / spine angles.
##   --screen 1 --skip-login --zone=0 --figure=cel_m --probe=idle_pose_probe --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(7.0).timeout
	var p: Node3D = v.player
	var model: Node3D = p.get("_model")
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	for b in ["Bip01", "Bip01 Pelvis", "Bip01 Spine", "Bip01 Spine1", "Bip01 Neck", "Bip01 Head", "Bip01 L Thigh", "Bip01 R Thigh"]:
		var i := sk.find_bone(b)
		if i < 0:
			continue
		var g := sk.global_transform * sk.get_bone_global_pose(i)
		var up := g.basis.x.normalized()               # biped bones run along their local X
		print("[idle] %-14s at %s  axis %s  tilt from vertical %.1f deg" % [b, (g.origin - p.global_position).snapped(Vector3.ONE * 0.01),
				up.snapped(Vector3.ONE * 0.01), rad_to_deg(up.angle_to(Vector3.UP))])
	var anim: AnimationPlayer = p.get("_anim")
	print("[idle] clip ", anim.current_animation, " model rot ", model.global_rotation_degrees.snapped(Vector3.ONE * 0.1),
			" player rot ", p.global_rotation_degrees.snapped(Vector3.ONE * 0.1))
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	var f: Vector3 = model.global_transform.basis.z
	var s: Vector3 = model.global_transform.basis.x
	for view in [["front", f], ["side", s], ["back", -f]]:
		cam.global_position = p.global_position + (view[1] as Vector3) * 3.2 + Vector3(0, 1.0, 0)
		cam.look_at(p.global_position + Vector3(0, 0.95, 0))
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/idle_%s.png" % [String(v.args.get("out", "user://")), view[0]])
	get_tree().quit()
