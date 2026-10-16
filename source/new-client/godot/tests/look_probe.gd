extends Node
## Debug: four pictures around the arrival spot (N, E, S, W), camera a little above the player.
##   --screen 1 --skip-login --zone=57 [--pos=x,y,z] --probe=look_probe --out=<dir> [--tag=name]
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(7.0).timeout
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.far = 3000.0
	var tag := String(v.args.get("tag", "look"))
	for i in 4:
		var yaw := i * PI * 0.5
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		cam.global_position = v.player.global_position + Vector3(0, 6, 0) - fwd * 4.0
		cam.look_at(cam.global_position + fwd * 10.0 + Vector3(0, -3.5, 0))
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [String(v.args.get("out", "user://")), tag, i])
	get_tree().quit()
