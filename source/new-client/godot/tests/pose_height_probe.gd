extends Node
## Debug, offline (owner 2026-10-17: the windswept wraith - model 441, the Lich - floated while attacking): one
## --model (ghostly with --ghost) set down 4 m ahead, then each of --clips posed at the frame where its body is
## highest and pictured (user://pose_<clip>.png), with its hip and lowest foot height over the ground. Runs once.
##   --skip-login --zone=100 --figure=nor_m --probe=pose_height_probe --model=441 --ghost
var v: Node


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	await get_tree().create_timer(8.0).timeout
	for w in v.ui.windows.values():
		if w is Control and not (w is ChatWindow):
			(w as Control).visible = false
	var p: Player = v.player
	p.hold()
	var cam: Camera3D = get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var at := cam.global_position + fwd * 6.0                  # in front of the camera
	p.visible = false
	at.y = v.zone.height_at(at.x, at.z)
	var down := PhysicsRayQueryParameters3D.create(at + Vector3(0, 5, 0), at - Vector3(0, 5, 0), ZoneLoader.LAYER_FLOOR)
	var fl := get_viewport().get_world_3d().direct_space_state.intersect_ray(down)
	if not fl.is_empty():
		at.y = float(fl.position.y)                            # on the drawn ground, as the game places them
	var ms := String(v.args.get("model", "441"))
	var s := {"id": "pose_" + ms, "name": "windswept wraith", "guild": "", "level": 50, "realm": 0, "role": "",
			"trains": null, "class_type": "", "model": ms, "size": 50, "gender": 0, "pos": [at.x, at.y, at.z],
			"heading": 0, "aggro_level": 0, "aggro_range": 0, "roam": 0, "flags": 1 if v.args.has("ghost") else 0,
			"speed": 200, "items": "", "equipment": "", "faction": 0, "body_type": 0, "template": 0,
			"stats": [0, 0, 0, 0], "damage_type": 1, "race": 0, "respawn": 0, "defense": [0, 0, 0, 0], "spells": [],
			"spell_scale": 1.0, "martial": 1.0, "abilities": [], "levels": [50], "models": [int(ms)], "sizes": [50],
			"tether": 0, "styles": []}
	var st: NpcState = v.npcs.add_spawn(s)
	st.wait = 1e9
	await get_tree().create_timer(3.0).timeout
	var view := st.view as Npc
	if view == null or view.anim == null:
		print("[pose] no view")
		get_tree().quit()
		return
	view.look_at(Vector3(cam.global_position.x, view.global_position.y, cam.global_position.z), Vector3.UP, true)
	view.process_mode = Node.PROCESS_MODE_DISABLED              # (posed by hand: its own animation logic off)
	var skel := view.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var hip := skel.find_bone("Bip01")
	var ground := view.global_position.y
	for clip in String(v.args.get("clips", "idle,combat_idle,attack_med,attack_low")).split(","):
		if not view.anim.has_animation(clip):
			print("[pose] no clip ", clip)
			continue
		view.anim.play(clip)
		var len := view.anim.get_animation(clip).length
		var best_t := 0.0
		var best_y := -INF
		for i in 40:                                           # the frame where the body is highest
			var t := len * i / 40.0
			view.anim.seek(t, true)
			var y := (skel.global_transform * skel.get_bone_global_pose(hip)).origin.y
			if y > best_y:
				best_y = y
				best_t = t
		view.anim.seek(best_t, true)
		var low := INF
		var worst := INF                                       # a foot / toe bone against the drawn ground right under it
		var space := view.get_world_3d().direct_space_state
		for b in skel.get_bone_count():
			var n := skel.get_bone_name(b).to_lower()
			if "foot" in n or "toe" in n:
				var bp := (skel.global_transform * skel.get_bone_global_pose(b)).origin
				low = minf(low, bp.y)
				var q := PhysicsRayQueryParameters3D.create(bp + Vector3(0, 2, 0), bp - Vector3(0, 2, 0), ZoneLoader.LAYER_FLOOR)
				var hit := space.intersect_ray(q)
				if not hit.is_empty():
					worst = minf(worst, bp.y - float(hit.position.y))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://pose_%s.png" % clip)
		print("[pose] %-12s at %.2f s: hip %+.2f m, lowest foot %+.2f m over her spot, %+.2f m over the ground under it" % [
				clip, best_t, best_y - ground, low - ground, worst])
	get_tree().quit()
