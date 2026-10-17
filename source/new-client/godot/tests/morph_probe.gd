extends Node
## Headless check of the pregame vertex animation: loads a realm scene, samples the banner's frame weights.
func _ready() -> void:
	UiArt.settings_path = "user://settings_uitest.cfg"          # never the owner's settings
	for realm in ["mid", "hib", "alb"]:
		var s := NifScene.new()
		add_child(s)
		s.load_scene("res://content/pregame/%s/scene.gltf" % realm, "original")
		var mi: MeshInstance3D = s.find_children("morph_0", "MeshInstance3D", true, false)[0]
		print(realm, " animated meshes ", s._morphs.size(), " banner blend shapes ", mi.mesh.get_blend_shape_count())
		for step in 3:
			await get_tree().create_timer(0.35).timeout
			var on := []
			for i in mi.mesh.get_blend_shape_count():
				var w := mi.get_blend_shape_value(i)
				if w > 0.001:
					on.append("%d:%.2f" % [i, w])
			print("   t=%.2f frames %s" % [s._time, on])
		s.queue_free()
	get_tree().quit()
