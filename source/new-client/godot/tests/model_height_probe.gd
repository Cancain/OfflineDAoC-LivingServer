extends Node
## Debug: raw glTF height (m) of monster models, and the drawn height for a spawn size, with / without monsters.csv scale.
##   --headless --skip-login --zone=209 --figure=cel_m --ui-test --no-npcs --probe=model_height_probe
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(2.0).timeout
	var all = JSON.parse_string(FileAccess.get_file_as_string("res://content/monsters/monsters.json"))
	var models: Dictionary = all.get("models", all)
	var mgr := NpcManager.new()
	add_child(mgr)
	for k in ["592", "591", "469", "119", "120", "403", "402", "2346", "448", "590", "577"]:
		var info: Dictionary = models.get(k, {})
		if not info.has("gltf"):
			continue
		var m: Node3D = mgr.instance_model(String(info.gltf))
		add_child(m)
		await get_tree().process_frame
		var lo := INF
		var hi := -INF
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
			lo = minf(lo, b.position.y)
			hi = maxf(hi, b.end.y)
		print("[h] %s %-22s raw %.2f m   client scale %.2f -> at size 50: %.2f m" % [k, info.get("name", ""), hi - lo, float(info.get("scale", 1)), (hi - lo) * float(info.get("scale", 1))])
		m.queue_free()
	get_tree().quit()
