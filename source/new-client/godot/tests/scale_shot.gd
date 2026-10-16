extends Node
## Debug (windowed): stand next to the first spawn named --name=<x> and take a picture (monster size checks).
##   --screen 1 --skip-login --zone=202 --figure=cel_m --ui-test --probe=scale_shot --name=sand crab --out=<folder>
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var want := String(v.args.get("name", "sand crab"))
	for s in v.npcs.states:
		var st: NpcState = s
		if String(st.spawn.name) == want:
			var at := st.pos + Vector3(4.0, 0, 0)
			at.y = v.zone.height_at(at.x, at.z) + 0.3
			v.player.global_position = at
			v.player.char_yaw = PI * 0.5
			v.player.cam_yaw = PI * 0.5
			break
	v.ui.visible = false
	v.player.cam_distance = 5.0
	v.player.cam_pitch = -0.35
	await get_tree().create_timer(3.0).timeout
	get_viewport().get_texture().get_image().save_png(String(v.args.get("out", "user://")) + "/" + want.replace(" ", "_") + ".png")
	get_tree().quit()
