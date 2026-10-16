extends Node
## Debug, local (owner 2026-10-15: the bubble's progress bar under the experience jewels): the status panel at a few
## experience values, pictured (user://xpbar_<n>.png). Runs once, quits (hard stop 30 s).
func _ready() -> void:
	if get_tree().root.has_meta("xp_bar_ran"):
		return
	get_tree().root.set_meta("xp_bar_ran", true)
	get_tree().create_timer(30.0).timeout.connect(func(): get_tree().quit())
	var v := get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var st: Control = v.ui.windows.get("status")
	for f in [0.0, 0.07, 0.47, 0.95]:
		PlayerData.exp_frac = f
		v.ui._refresh()
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		var r := st.get_global_rect()
		var img := get_viewport().get_texture().get_image()
		var sc: Vector2 = Vector2(img.get_size()) / get_viewport().get_visible_rect().size
		img.get_region(Rect2i(Vector2i(r.position * sc), Vector2i(r.size * sc))).save_png("user://xpbar_%d.png" % roundi(f * 100))
		print("[xp] %.2f saved" % f)
	get_tree().quit()
