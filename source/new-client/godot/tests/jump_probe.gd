extends Node
## Debug: a server teleport to another zone of the region (ZoneViewer._jump_in_region) - the scene must stay (no
## reload), the destination become the zone you're in, you stand on its ground.
##   --headless -- --skip-login --zone=100 --figure=nor_m --ui-test --probe=jump_probe
func _ready() -> void:
	var v := get_tree().current_scene
	if Engine.has_meta("jump_probe_ran"):                 # (a fallback reload: report it, don't run again)
		print("[jump] FAILED: the scene was reloaded")
		get_tree().quit()
		return
	Engine.set_meta("jump_probe_ran", true)
	Server._index = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zones_index.json"))
	await get_tree().create_timer(4.0).timeout
	var id_before := v.get_instance_id()
	var gx := 84.0 * 8192.0 + 30000.0                  # Skona Ravine (106), inside
	var gy := 110.0 * 8192.0 + 30000.0
	var t0 := Time.get_ticks_msec()
	v._on_server_jump({"zone": 106, "x": gx, "y": gy, "z": 2000.0, "face": 90.0})
	while v._jumping:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var cur := get_tree().current_scene
	var p: Vector3 = v.player.global_position
	print("[jump] same scene: ", cur.get_instance_id() == id_before, " | zone now ", int(v.region.current.info.id),
			" | took ", Time.get_ticks_msec() - t0, " ms | player at ", p, " ground ", v.region.height_at(p.x, p.z),
			" | expected local ", Vector3((gx - 84.0 * 8192.0) * 0.025, 0, (gy - 110.0 * 8192.0) * 0.025))
	get_tree().quit()
