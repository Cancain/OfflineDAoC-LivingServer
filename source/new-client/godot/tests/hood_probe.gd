extends Node
## Debug, local (owner 2026-10-15: /hood doesn't put the hood up): your figure with a cloak, hood down then up, pictures
## from the front and the side; which cloak meshes / hair are drawn. Runs once (60 s cap).
##   --screen 1 --skip-login --zone=100 --figure=kob_m --probe=hood_probe --out=<folder>
var v: Node


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	var out := String(v.args.get("out", "user://hood"))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(6.0).timeout
	var p: Player = v.player
	var fig := p._model as Fig3Figure
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	for hood in [false, true]:
		fig.hood_up = hood
		fig.set_armor({"cloak": [1, "cat_cloak"]}, {})
		var shown := []
		for mi in fig.find_children("*", "MeshInstance3D", true, false):
			if (mi as MeshInstance3D).visible and (String(mi.name).begins_with("cloak") or String(mi.name).contains("hair")):
				shown.append(String(mi.name))
		print("[hood] hood ", hood, " drawn: ", shown)
		for side in [0.0, PI * 0.5]:
			var dir := Vector3(sin(p.char_yaw + PI + side), 0, cos(p.char_yaw + PI + side))
			cam.global_position = p.global_position + dir * 2.2 + Vector3(0, 1.1, 0)
			cam.look_at(p.global_position + Vector3(0, 0.8, 0))
			await get_tree().create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("hood_%s_%d.png" % [hood, int(side * 10)]))
	get_tree().quit()
