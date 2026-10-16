extends Node
## Debug: walk (autorun, no jumping) up the Lethantis tower's two stairs (owner 2026-10-09: stuck on the steps).
##   --headless --skip-login --zone=8 --realm=alb --ui-test --probe=stairs_walk_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var p: Player = viewer.player
	# side stairs: rising toward +x from (15137, 6084); front stairs: rising toward -z from (14134, 6483)
	for t in [[Vector3(15137 * 0.025 - 1.5, 2292 * 0.025 + 0.3, 6084 * 0.025), -PI * 0.5, "side stairs (+x)"],
			[Vector3(14134 * 0.025, 2292 * 0.025 - 1.6, 6483 * 0.025 + 5.0), 0.0, "front stairs (-z)"]]:
		p.global_position = t[0]
		p.velocity = Vector3.ZERO
		p.char_yaw = t[1]
		p.cam_yaw = t[1]
		await get_tree().create_timer(0.6).timeout
		var y0 := p.global_position.y
		var from := p.global_position
		p.autorun = true
		await get_tree().create_timer(3.0).timeout
		p.autorun = false
		print("[stairs] %s: climbed %.2f m over %.1f m walked (start %.2f, end %.2f)" % [t[2], p.global_position.y - y0,
				Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length(), y0, p.global_position.y])
	get_tree().quit()
