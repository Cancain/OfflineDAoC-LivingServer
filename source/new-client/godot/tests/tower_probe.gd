extends Node
## Debug (owner 2026-10-10: a floating flag, no tower, Camelot Hills): looks at the guard tower at 486, 659 from 240 m,
## 100 m and 30 m.   --screen 1 --skip-login --zone=0 --probe=tower_probe --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var tower := Vector3(486, 70, 659)
	for t in [Vector3(998.4, 71.2, 800.0), Vector3(486.4, 70.45, 659.2), Vector3(860.65, 56.838, 100.55)]:
		var hs := []
		for o in [Vector2.ZERO, Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
			hs.append(snappedf(v.zone.height_at(t.x + o.x, t.z + o.y), 0.1))
		print("[tower] base y ", t.y, " ground ", hs)
	for d in [240.0, 100.0, 30.0]:
		var at: Vector3 = tower + Vector3(60, 0, 230).normalized() * d
		at.y = v.zone.height_at(at.x, at.z) + 1.0
		v.player.global_position = at
		var dir: Vector3 = tower - at
		v.player.face(atan2(-dir.x, -dir.z))
		await get_tree().process_frame
		v.player.cam_yaw = v.player.char_yaw
		v.player.cam_pitch = -0.05
		await get_tree().create_timer(2.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/tower_%d.png" % [String(v.args.get("out", "user://")), int(d)])
	for c in v.zone.find_children("*", "MultiMeshInstance3D", true, false):
		var mmi := c as MultiMeshInstance3D
		if String(mmi.name).begins_with("Guard tower"):
			var pts := []
			for k in mmi.multimesh.instance_count:
				pts.append(mmi.global_transform * mmi.multimesh.get_instance_transform(k).origin)
			print("[tower] ", mmi.name, " vis ", mmi.visible, " in tree ", mmi.is_visible_in_tree(), " range ", mmi.visibility_range_end,
					" mesh aabb ", mmi.multimesh.mesh.get_aabb().size, " at ", pts)
	get_tree().quit()
