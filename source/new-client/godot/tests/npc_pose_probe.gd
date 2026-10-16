extends Node
## Debug (owner 2026-10-10: NPCs in a tilted idle): stand at --pos, then a side and a front picture of the nearest
## active NPC of each --models id, playing idle.
##   --screen 1 --skip-login --zone=N --figure=cel_m --probe=npc_pose_probe --pos=x,y,z --models=870,871 --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var p := String(v.args.get("pos", "")).split(",")
	if p.size() == 3:
		v.player.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
		v.player.hold()
	await get_tree().create_timer(4.0).timeout
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	for mid in String(v.args.get("models", "")).split(","):
		var best: Node3D = null
		for k in v.npcs.active:
			var n = v.npcs.active[k]
			if String(n.spawn.model) == mid and (best == null or n.global_position.distance_to(v.player.global_position) < best.global_position.distance_to(v.player.global_position)):
				best = n
		if best == null:
			print("[pose] model ", mid, ": none active")
			continue
		var fwd: Vector3 = best.global_transform.basis.z
		var side: Vector3 = best.global_transform.basis.x
		var h: float = float(best.get("height")) if best.get("height") != null else 2.0
		for view in [["side", side], ["front", fwd]]:
			cam.global_position = best.global_position + (view[1] as Vector3) * (h * 2.2) + Vector3(0, h * 0.6, 0)
			cam.look_at(best.global_position + Vector3(0, h * 0.5, 0))
			await get_tree().create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/pose_%s_%s.png" % [String(v.args.get("out", "user://")), mid, view[0]])
		var a: AnimationPlayer = best.anim
		print("[pose] model ", mid, " ", best.spawn.name, " clip=", a.current_animation if a else "-", " mode=", int(best.state.mode))
	get_tree().quit()
