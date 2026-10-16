extends Node
## Debug (owner 2026-10-10: 7 fps after Camelot Hills -> Shannon Estuary, 140 fps on a fresh start): how much video
## memory and how many objects are still held after a zone change, against a fresh load of the same zone.
##   fresh:  --screen 1 --skip-login --zone=202 --figure=cel_m --probe=zone_swap_probe -- --with-loading
##   swap:   --screen 1 --skip-login --zone=0 --figure=cel_m --probe=zone_swap_probe -- --with-loading --swap_to=202
## (the probe is added again in the next zone; the static counter says which leg this is)
static var leg := 0


func _ready() -> void:
	var v := get_tree().current_scene
	leg += 1
	await get_tree().create_timer(12.0).timeout
	_report("zone %d (leg %d)" % [int(v.zone.info.id), leg])
	if leg == 1 and v.args.has("swap_to"):
		Accounts.account = "testcopy"                     # travel_to saves the character: never into a real account
		if not PlayerData.character.has("name"):
			PlayerData.character["name"] = "ZoneSwapProbe"
		var to := int(v.args["swap_to"])
		var zj = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zone%03d/zone.json" % to))
		var spot: Dictionary = (zj.spots as Array)[0]       # the zone's first spot, as an exit's arrival point
		v.travel_to(to, spot.pos, float(spot.get("face", 0.0)))
		return
	if leg >= 2 or not v.args.has("swap_to"):
		print("[swap] orphan nodes:")
		Node.print_orphan_nodes()
		get_tree().quit()


func _report(where: String) -> void:
	var mb := func(m): return "%.0f MB" % (Performance.get_monitor(m) / 1048576.0)
	print("[swap] ", where, ": video ", mb.call(Performance.RENDER_VIDEO_MEM_USED),
			", textures ", mb.call(Performance.RENDER_TEXTURE_MEM_USED),
			", buffers ", mb.call(Performance.RENDER_BUFFER_MEM_USED),
			", objects ", int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			", resources ", int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			", nodes ", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			", orphans ", int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			", fps ", Engine.get_frames_per_second())
