extends Node
## Debug (windowed): a staff held outside attack mode (objects.csv On Belt = 0).
##   --screen 1 --skip-login --zone=200 --figure=elf_m --ui-test --no-npcs --probe=staff_shot --out=<folder>
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(4.0).timeout
	PlayerData.inventory.erase(10)
	PlayerData.inventory.erase(11)
	PlayerData.inventory[12] = {"id": "oaken_Mentalist_Staff_of_Magic", "count": 1}
	PlayerData.active_weapon = "twohand"
	v.player.refresh_gear()
	v.ui.visible = false
	v.player.cam_yaw = v.player.char_yaw + PI * 0.6
	v.player.cam_distance = 3.5
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png(String(v.args.get("out", "user://")) + "/staff.png")
	get_tree().quit()
