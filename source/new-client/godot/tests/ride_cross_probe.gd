extends Node
## Debug: a horse route across a zone border - Rumdor (Mag Mell, Lough Derg) -> Howth (Connacht). The probe is added
## again by the next zone's scene (same command line) and follows the ride there.
##   --headless --skip-login --zone=200 --figure=cel_m --ui-test --probe=ride_cross_probe
var viewer: Node
static var started := false


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(4.0).timeout
	print("[cross] zone ", viewer.zone.info.id, " ", viewer.zone.info.name, " ride ", HorseRoutes.ride.get("path", "-"), " point ", HorseRoutes.ride.get("i", "-"), " riding ", viewer.player.riding)
	if not started:
		started = true
		for s in viewer.npcs.states:
			if String((s as NpcState).spawn.name) == "Rumdor":
				var at: Vector3 = (s as NpcState).pos + Vector3(2, 0, 0)
				at.y = viewer.zone.height_at(at.x, at.z) + 0.3
				viewer.player.global_position = at
		await get_tree().create_timer(0.5).timeout
		PlayerData.buy("HR_MagMell_Howth", "Rumdor")
	for t in 240:
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
		if t % 20 == 0:
			print("[cross] zone ", viewer.zone.info.id, " t", t, " point ", HorseRoutes.ride.get("i", "-"), " riding ", viewer.player.riding)
		if HorseRoutes.ride.is_empty() and t > 5:
			print("[cross] ride over in zone ", viewer.zone.info.id, " ", viewer.zone.info.name, " at ", viewer.player.global_position)
			get_tree().quit()
			return
	get_tree().quit()
