extends Node
## Debug: zone borders. In Lough Derg it steps off the east edge; the scene reloads into the neighbour (Valley of Bri
## Leith) at the same region spot (the probe runs again there and prints where it arrived), then steps back west.
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=border_probe
var viewer: Node
static var hops := 0


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var p: Vector3 = viewer.player.global_position
	var size := float(viewer.zone.info.size_m)
	print("[border] hop ", hops, " in zone ", viewer.zone.info.id, " ", viewer.zone.info.name, " at ", p, " (", p.x / 0.025, ", ", p.z / 0.025, " units)")
	hops += 1
	if hops > 2:
		get_tree().quit()
		return
	var z := size * 0.5
	if hops == 1:
		viewer.player.global_position = Vector3(size - 0.5, viewer.zone.height_at(size - 0.5, z) + 0.3, z)
		await get_tree().create_timer(0.5).timeout
		viewer.player.global_position = Vector3(size + 0.3, viewer.player.global_position.y, z)    # one step east
	else:
		viewer.player.global_position = Vector3(0.5, viewer.zone.height_at(0.5, p.z) + 0.3, p.z)
		await get_tree().create_timer(0.5).timeout
		viewer.player.global_position = Vector3(-0.3, viewer.player.global_position.y, p.z)        # one step west
	await get_tree().create_timer(4.0).timeout
	print("[border] no reload after 4 s")
	get_tree().quit()
