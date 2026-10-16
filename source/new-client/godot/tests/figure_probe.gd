extends Node
## Debug: --probe=figure_probe --figure=<prefix> [--out=<png>]: the race figure as the player in the zone, one screenshot.

func _ready() -> void:
	var out := "user://figure_probe.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.split("=", true, 1)[1]
	get_window().size = Vector2i(1600, 900)
	await get_tree().create_timer(4.0).timeout
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
	get_tree().quit()
