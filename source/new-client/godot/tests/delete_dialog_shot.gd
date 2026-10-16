extends Node
## Debug (owner 2026-10-10: the delete box in the granite style): opens character select, asks to delete a made-up
## character (nothing is deleted - the box is only shown), saves a picture.
##   godot --path godot --screen 1 res://tests/delete_dialog_shot.tscn -- --out=<dir>


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var pg: Node = load("res://game/pregame.tscn").instantiate()
	add_child(pg)
	await get_tree().create_timer(4.0).timeout
	pg.set("chars", [{"name": "Echnodaerna"}])
	pg.set("sel", 0)
	pg.call("_ask_delete")
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "/delete_dialog.png")
	get_tree().quit()
