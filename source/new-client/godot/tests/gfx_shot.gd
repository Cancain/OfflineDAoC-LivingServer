extends Node
## Debug: Options > VIDEO's quality page and the world at the LOW / EXTREME presets, as screenshots
## (user://gfx_*.png). Windowed, on the Acer:
##   --screen 1 -- --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=gfx_shot
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var ui = v.ui
	ui.options.show_window()
	ui.options.show_page("video")
	await get_tree().create_timer(0.8).timeout
	_shot("video1")
	for i in [1, 2, 3]:
		ui.options._scroll.scroll_vertical = 330 * i
		await get_tree().create_timer(0.5).timeout
		_shot("video%d" % (i + 1))
	ui.options.hide_window()
	for pre in ["low", "extreme", "defaults"]:
		Graphics.use_preset(pre)
		await get_tree().create_timer(4.0).timeout
		_shot("world_" + pre)
		print("[gfx] ", pre, " fps ", Engine.get_frames_per_second(), " far ", v.player.camera.far, " fog end ",
				v.sky.environment.fog_depth_end, " zones ", v.region.zones.keys() if v.region else [])
	print("[gfx] recommended ", Graphics.recommended())
	get_tree().quit()


func _shot(tag: String) -> void:
	get_viewport().get_texture().get_image().save_png("user://gfx_%s.png" % tag)
