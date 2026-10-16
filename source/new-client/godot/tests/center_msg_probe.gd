extends Node
## Debug, local (owner 2026-10-15: quest kill progress and realm announcements on screen): a few screen-centre lines
## as the server sends them (CT_ScreenCenter / ...Smaller), pictured (user://center_msg.png). Runs once, quits.
func _ready() -> void:
	if get_tree().root.has_meta("center_msg_ran"):
		return
	get_tree().root.set_meta("center_msg_ran", true)
	get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit())
	var v := get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	v.ui.center_message("The forces of Midgard are attacking Caer Benowyc!")
	v.ui.center_message("Kill 5 wolf adolescents: 2/5")
	v.ui.center_message("You have entered the Lough Derg area.", true)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.get_region(Rect2i(0, 0, img.get_width(), img.get_height() / 2)).save_png("user://center_msg.png")
	await get_tree().create_timer(5.5).timeout
	print("[cm] lines left after 6 s: ", v.ui._center_box.get_child_count())
	get_tree().quit()
