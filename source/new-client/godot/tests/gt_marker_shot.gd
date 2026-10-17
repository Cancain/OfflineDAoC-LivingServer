extends Node
## Debug (owner 2026-10-14): the ground target marker 3 m ahead, screenshot user://gt_marker.png.
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	v.ui.visible = false
	var p: Vector3 = v.player.global_position + (-v.player.global_transform.basis.z).normalized() * 3.0
	p.y = v.npcs.ground_at(Vector3(p.x, p.y + 10.0, p.z)) if v.npcs else p.y
	v.show_ground_target(p)
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://gt_marker.png")
	get_tree().quit()
