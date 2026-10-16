extends Node
## Debug: a spell effect with vertex animation (earth fingers 171) - its blend-shape weights over time.
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(4.0).timeout
	var fx: Node3D = SpellFx.play(171, v.player, 1.8)
	for k in 6:
		await get_tree().create_timer(0.3).timeout
		var out := []
		for mi in fx.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var w := []
			for b in m.mesh.get_blend_shape_count() if m.mesh else 0:
				w.append(snappedf(m.get_blend_shape_value(b), 0.01))
			out.append([m.name, m.visible, w])
		print("[morph] t=", 0.3 * (k + 1), " ", out)
	get_tree().quit()
