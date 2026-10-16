extends Node
## Debug: /bind at a bind point (Mag Mell, BindPoint 344452 / 491649) and /release back to it; then a bind in another
## zone - the release loads that zone (the probe comes back with the next scene and reports where it is).
##   --headless --skip-login --zone=200 --figure=cel_m --ui-test --probe=bind_probe
var viewer: Node
static var stage := 0


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(4.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var combat: Combat = viewer.combat
	if stage == 1:
		print("[bind] after the cross-zone release: zone ", viewer.zone.info.id, " ", viewer.zone.info.name, " at ", viewer.player.global_position)
		get_tree().quit()
		return
	var spot := Vector3((344452 - 39 * 8192) * 0.025, 0, (491649 - 59 * 8192) * 0.025)
	spot.y = viewer.zone.height_at(spot.x, spot.z) + 0.3
	viewer.player.global_position = spot + Vector3(3, 0, 0)
	await get_tree().physics_frame
	PlayerData.bind_requested.emit()                      # bound
	PlayerData.bind_requested.emit()                      # too soon
	combat._bind_at = -1000.0
	viewer.player.global_position = spot + Vector3(60, 0, 0)
	viewer.player.global_position.y = viewer.zone.height_at(viewer.player.global_position.x, viewer.player.global_position.z) + 0.3
	await get_tree().physics_frame
	PlayerData.bind_requested.emit()                      # can't bind here
	# die far away, release: back at the bind
	viewer.player.global_position = spot + Vector3(300, 0, 0)
	PlayerData.set_hp(0)
	combat._player_died()
	combat._dead_for = 999.0
	combat.release()
	await get_tree().create_timer(0.5).timeout
	print("[bind] released at ", snappedf(viewer.player.global_position.distance_to(spot + Vector3(3, 0, 0)), 0.1), " m from where it bound")
	# a bind in Shannon Estuary: the release goes there
	PlayerData.character["bind"] = {"zone": 202, "pos": [300.0, 130.0, 600.0], "face": 0.0}
	stage = 1
	PlayerData.set_hp(0)
	combat._player_died()
	combat._dead_for = 999.0
	combat.release()
