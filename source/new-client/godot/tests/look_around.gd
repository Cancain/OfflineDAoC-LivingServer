extends Node
## Debug: four screenshots from where you stand, turned 0 / 90 / 180 / 270 degrees (user://look_<n>.png) - the place
## an owner screenshot was taken (--pos in engine metres = DAoC units x 0.025).
##   --screen 1 -- --skip-login --zone=209 --pos=580.25,191.5,689.35 --figure=elf_m --ui-test --probe=look_around
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	v.ui.visible = false
	for k in 4:
		v.player.face(deg_to_rad(90.0 * k))
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png("user://look_%d.png" % k)
	get_tree().quit()
