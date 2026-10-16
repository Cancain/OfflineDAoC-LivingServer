extends Node
## Debug: fall damage. The player is dropped from 20 m and from 4 m onto open ground.
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=fall_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	for h in [20.0, 4.0]:
		PlayerData.set_hp(PlayerData.max_hp)
		var p: Vector3 = viewer.player.global_position + Vector3(30, 0, 0)
		p.y = viewer.zone.height_at(p.x, p.z) + h
		viewer.player.global_position = p
		viewer.player.velocity = Vector3.ZERO
		viewer.player.grounded = false
		await get_tree().create_timer(3.0).timeout
		print("[fall] from ", h, " m: hp ", PlayerData.hp, "/", PlayerData.max_hp, " end ", PlayerData.end_pts)
	get_tree().quit()
