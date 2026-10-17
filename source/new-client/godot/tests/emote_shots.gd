extends Node
## Debug (windowed): screenshots of the player mid-emote (wave, bow, cheer, dance) to check the clips look right.
##   --screen 1 --skip-login --zone=200 --figure=cel_m --ui-test --probe=emote_shots --out=<folder>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var out := String(viewer.args.get("out", "user://emotes"))
	DirAccess.make_dir_recursive_absolute(out)
	var p = viewer.player
	p.cam_distance = 3.2
	p.cam_yaw = p.char_yaw + PI                           # look at its face
	for cmd in ["wave", "bow", "cheer", "dance", "salute", "point"]:
		viewer.combat._emote_at = -100.0
		PlayerData.emote_requested.emit(cmd)
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png("%s/emote_%s.png" % [out, cmd])
		await get_tree().create_timer(2.6).timeout
	get_tree().quit()
