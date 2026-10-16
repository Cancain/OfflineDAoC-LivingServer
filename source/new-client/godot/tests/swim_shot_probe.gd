extends Node
## Debug: a swimmer from the side at the waterline, and where he floats.   --zone=185 --pos=760,90,950 --probe=swim_shot_probe
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(8.0).timeout
	var p: Node3D = v.player
	var w: float = v.zone.water_level_at(p.global_position.x, p.global_position.z)
	var sk: Skeleton3D = p._model.find_children("*", "Skeleton3D", true, false)[0]
	var head := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 Head"))).origin
	print("[swimshot] swimming ", p.swimming, " feet ", snappedf(p.global_position.y - w, 0.01), " m, head ", snappedf(head.y - w, 0.01),
			" m against the surface; clip ", p._anim.current_animation)
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	var fwd := Vector3(-sin(p.char_yaw), 0, -cos(p.char_yaw))
	cam.global_position = p.global_position + fwd.cross(Vector3.UP) * 3.0 + Vector3(0, 0.25 + (w - p.global_position.y), 0)
	cam.look_at(Vector3(p.global_position.x, w, p.global_position.z))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(String(v.args.get("out", "user://")) + "/swim_side.png")
	get_tree().quit()
