extends Node
## Debug, local (owner 2026-10-14: no accept-resurrect popup when a bot resurrects you): you dead with the RELEASE
## window up, then the server's resurrect question shown the way ServerWorld._dialog shows a yes / no box - is it on
## top, can it be clicked? user://rez_prompt.png. Runs once, quits itself.
func _ready() -> void:
	if get_tree().root.has_meta("rez_probe_ran"):
		return
	get_tree().root.set_meta("rez_probe_ran", true)
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit())
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	v.player.die()
	v.ui.show_release(true)
	await get_tree().create_timer(1.0).timeout
	var box: Control = UiArt.confirm(v.ui.root, "", "Do you allow Bjornaenbjorn to resurrected you\n with 10 percent hits/power?",
			"ACCEPT", "DECLINE", func(): print("[rez] ACCEPT clicked"), func(): print("[rez] DECLINE clicked"))
	await get_tree().create_timer(0.5).timeout
	var rel: Control = v.ui.windows.get("release")
	print("[rez] prompt index %d of %d under the interface root; release window index %d, visible %s" % [box.get_index(),
			v.ui.root.get_child_count(), rel.get_index() if rel else -1, rel.visible if rel else false])
	# what a click at the prompt's ACCEPT button would hit
	var hits := []
	for b in box.find_children("*", "Button", true, false):
		var c: Vector2 = (b as Control).get_global_rect().get_center()
		hits.append("%s at %s" % [(b as Button).text, c])
	print("[rez] buttons: ", hits)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://rez_prompt.png")
	get_tree().quit()
