extends Node
## Debug, local (owner 2026-10-16: the Cairnbreaker "is upside down completely"): your figure in combat stance with each
## of --weapons=<model,model,...> in the right hand in turn, a picture from the side of each - the set's weapon next to
## stock ones to see which way the stock ones point. Runs once (60 s cap).
##   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --probe=weapon_grip_probe --weapons=4834,3897,13,3
var v: Node


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	var out := String(v.args.get("out", "user://weapon_grip"))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(7.0).timeout
	v.ui.visible = false
	if v.hud:
		v.hud.visible = false
	var p: Player = v.player
	p.hold()
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.fov = 35.0
	for ms in String(v.args.get("weapons", "4834")).split(","):
		var model := int(ms)
		var item_at := func(slot: int) -> Dictionary:
			return {"model": model} if slot == 10 else {}
		for g in p._gear:
			if is_instance_valid(g):
				g.queue_free()
		p._gear = Player.dress(p._model, item_at, "standard", true, false, {})
		p.in_combat = true                                   # combat idle: the weapon held up
		await get_tree().create_timer(1.2).timeout
		# close on the weapon hand, from the figure's right side
		var sk: Skeleton3D = p._model.find_children("*", "Skeleton3D", true, false)[0]
		var hand := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 R Hand")).origin
		var right := (hand - p.global_position) * Vector3(1, 0, 1)
		right = right.normalized() if right.length() > 0.01 else Vector3.RIGHT
		cam.global_position = hand + right * 3.0 + Vector3(0, 0.4, 0)
		cam.look_at(hand + Vector3(0, 0.3, 0))
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("grip_%d.png" % model))
		print("[grip] ", model, " clip ", p._anim.current_animation)
	get_tree().quit()
