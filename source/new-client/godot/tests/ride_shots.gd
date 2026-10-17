extends Node
## Debug (windowed): screenshots of a horse route ride (seat on the saddle, the horse running).
##   --screen 1 --skip-login --zone=200 --figure=cel_m --ui-test --probe=ride_shots --out=<folder>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var out := String(viewer.args.get("out", "user://ride"))
	DirAccess.make_dir_recursive_absolute(out)
	for s in viewer.npcs.states:
		if String((s as NpcState).spawn.name) == "Rumdor":
			var at: Vector3 = (s as NpcState).pos + Vector3(2, 0, 0)
			at.y = viewer.zone.height_at(at.x, at.z) + 0.3
			viewer.player.global_position = at
	await get_tree().create_timer(0.5).timeout
	PlayerData.buy("HS_MagMell_ParthenonFarm", "Rumdor")
	viewer.player.cam_distance = 6.0
	for i in 4:
		await get_tree().create_timer(3.0 if i == 0 else 4.0).timeout
		viewer.player.cam_yaw = viewer.player.char_yaw + (PI * 0.5 if i % 2 == 1 else 0.0)
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png("%s/ride_%d.png" % [out, i])
	get_tree().quit()
