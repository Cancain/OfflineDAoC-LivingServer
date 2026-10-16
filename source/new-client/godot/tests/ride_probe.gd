extends Node
## Debug: a stable master horse route. Next to Rumdor (Mag Mell) the player buys "Ticket to East Lough Derg"; the
## horse appears, the player mounts, rides the path and is set down at its end.
##   --headless --skip-login --zone=200 --figure=cel_m --ui-test --probe=ride_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var stable: NpcState = null
	for s in viewer.npcs.states:
		if String((s as NpcState).spawn.name) == "Rumdor":
			stable = s
	var at := stable.pos + Vector3(2, 0, 0)
	at.y = viewer.zone.height_at(at.x, at.z) + 0.3
	viewer.player.global_position = at
	await get_tree().create_timer(0.5).timeout
	var r: Dictionary = HorseRoutes.routes().get("HS_MagMell_ParthenonFarm", {})
	print("[ride] route points ", r.get("points", []).size(), " mount ", r.get("mount"))
	PlayerData.buy("HS_MagMell_ParthenonFarm", "Rumdor")
	var start: Vector3 = viewer.player.global_position
	for t in 60:
		await get_tree().create_timer(1.0).timeout
		if t % 5 == 0 or HorseRoutes.ride.is_empty():
			print("[ride] t", t, " riding ", viewer.player.riding, " point ", HorseRoutes.ride.get("i", "-"), " from start ",
					snappedf(viewer.player.global_position.distance_to(start), 0.1), " m, anim ",
					viewer.player._anim.current_animation if viewer.player._anim else "-")
		if HorseRoutes.ride.is_empty() and t > 6:
			break
	var end_pt: Array = r.points[-1]
	var idx: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/zones/zones_index.json"))
	var me: Dictionary = idx.get(str(int(viewer.zone.info.id)), {})
	var o := Vector2(float(me.get("x", 0)) * 8192.0, float(me.get("y", 0)) * 8192.0)
	var endp := Vector3((end_pt[0] - o.x) * 0.025, 0, (end_pt[1] - o.y) * 0.025)
	var pp: Vector3 = viewer.player.global_position
	print("[ride] done: riding ", viewer.player.riding, " distance to path end ", snappedf(Vector2(pp.x - endp.x, pp.z - endp.z).length(), 0.1), " m")
	get_tree().quit()
