extends Node
## Debug, local (owner 2026-10-16: one release button where the original client had four): the death window shown with
## a running release timer, one picture. Runs once (40 s cap).
##   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --figure=nor_m --probe=release_window_probe --out=<folder>
var v: Node


func _ready() -> void:
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	var out := String(v.args.get("out", "user://release_window"))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(7.0).timeout
	v.ui.show_release(true)
	PlayerData.release_timer.emit(600.0)
	PlayerData.release_timer.emit(412.0)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var w: Control = v.ui.windows["release"]
	var r := Rect2i(Vector2i(w.global_position) - Vector2i(20, 20), Vector2i(w.size) + Vector2i(40, 40))
	img.get_region(r).save_png(out.path_join("release_window.png"))
	get_tree().quit()
