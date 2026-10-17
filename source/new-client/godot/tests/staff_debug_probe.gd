extends Node
## Debug (the dyed staff not drawn): the player's two-hand slot, active set and what dress() hangs.
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await _wait(8.0)
	print("[staff] slot 12: ", PlayerData.item_at(12), "  active ", PlayerData.active_weapon, "  combat ", v.player.in_combat)
	v.player.refresh_gear()
	await _wait(0.5)
	print("[staff] gear nodes: ", v.player._gear.size())
	for g in v.player._gear:
		if is_instance_valid(g):
			var meshes: Array = (g as Node).find_children("*", "MeshInstance3D", true, false)
			var t = []
			for mi in meshes:
				var m: Material = (mi as MeshInstance3D).get_active_material(0)
				t.append(m.get_shader_parameter("tint") if m is ShaderMaterial else (m.get_class() if m else "none"))
			print("[staff]   ", (g as BoneAttachment3D).bone_name, " meshes ", meshes.size(), " tints ", t)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://staff_debug.png")
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
