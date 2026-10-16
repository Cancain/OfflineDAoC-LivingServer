extends Node
## Debug (owner 2026-10-11: bots and players share rules - a stuck spot that would stop the player too means the rule
## changes for both): the player walks (autorun) from a spot in a direction and reports position / height every 0.25 s.
##   --screen 1 --skip-login --zone=51 --figure=cel_m --probe=step_probe --from=1098,121,1376 --dir=0,-1
func _ready() -> void:
	var v := get_tree().current_scene
	var p: Player = v.player
	await get_tree().create_timer(5.0).timeout
	var f := String(v.args.get("from", "1098,121,1376")).split(",")
	var d := String(v.args.get("dir", "0,-1")).split(",")
	var dir := Vector2(float(d[0]), float(d[1])).normalized()
	p.global_position = Vector3(float(f[0]), float(f[1]), float(f[2]))
	p.char_yaw = atan2(-dir.x, -dir.y)
	p.cam_yaw = p.char_yaw
	p.hold()
	await get_tree().create_timer(1.0).timeout
	print("[step] start %s grounded %s" % [p.global_position.snapped(Vector3.ONE * 0.01), p.grounded])
	p.autorun = true
	var last := p.global_position
	for i in 28:
		await get_tree().create_timer(0.25).timeout
		var pos := p.global_position
		var what := ""
		for k in p.get_slide_collision_count():
			var c := p.get_slide_collision(k)
			var o := c.get_collider() as Node
			what += " hit %s (%s) at %s" % [o.name if o else "?", o.get_parent().name if o and o.get_parent() else "", c.get_position().snapped(Vector3.ONE * 0.01)]
		print("[step] t=%.2f pos %s moved %.2f m up %.2f%s" % [(i + 1) * 0.25, pos.snapped(Vector3.ONE * 0.01), Vector2(pos.x - last.x, pos.z - last.z).length(), pos.y - last.y, what])
		last = pos
	p.autorun = false
	if v.args.has("out"):                                    # a picture from behind and above, looking the walk's way
		var cam := Camera3D.new()
		v.add_child(cam)
		cam.current = true
		var at := p.global_position
		cam.global_position = at + Vector3(-dir.x, 0, -dir.y) * 6.0 + Vector3(0, 3.0, 0)
		cam.look_at(at + Vector3(dir.x, 0, dir.y) * 3.0 + Vector3(0, 1.0, 0))
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(v.args.out).path_join("step.png"))
	get_tree().quit()
