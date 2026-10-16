extends Node
## Debug (owner 2026-10-10: shield not centred on a Briton's back): three shields (round 59, heater 60, tower 61) on
## the back (sheathed) and on the arm (attack mode), pictures from behind and in front.
##   --screen 1 --skip-login --zone=0 --figure=bri_m --probe=shield_probe --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var out := String(v.args.get("out", "user://"))
	var p: Node = v.player
	p.cam_distance = 2.6
	p.cam_pitch = -0.15
	for m in [59, 60, 61]:
		var id := "probe_shield_%d" % m
		ItemDb.add_runtime(id, {"id": id, "name": "probe shield", "object_type": 42, "item_type": 11, "model": m, "type_damage": 2})
		PlayerData.inventory[11] = {"id": id, "count": 1}
		for mode in ["back", "arm"]:
			p.in_combat = mode == "arm"
			p.refresh_gear()
			p.cam_yaw = p.char_yaw + (0.0 if mode == "back" else PI)
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/shield_%d_%s.png" % [out, m, mode])
	get_tree().quit()
