extends Node
## Debug: walk DOWN the Lethantis side stairs and off the 0.40 m arch step - count frames airborne (owner: fell instead
## of walking down).  --headless --skip-login --zone=8 --realm=alb --ui-test --probe=stairs_down_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var p: Player = viewer.player
	for t in [[Vector3(15137 * 0.025 + 4.5, 62.4, 6084 * 0.025), PI * 0.5, "side stairs down (-x)"],
			[Vector3(14134 * 0.025, 2292 * 0.025 + 0.7, 6483 * 0.025 - 3.0), PI, "arch step down (+z)"]]:
		p.global_position = t[0]
		p.velocity = Vector3.ZERO
		p.char_yaw = t[1]
		p.cam_yaw = t[1]
		await get_tree().create_timer(0.8).timeout
		var y0 := p.global_position.y
		var air := 0
		var fall_pose := 0
		p.autorun = true
		for i in 120:
			await get_tree().physics_frame
			if not p.grounded:
				air += 1
			if p._anim and p._anim.current_animation == "jump":
				fall_pose += 1
		p.autorun = false
		print("[down] %s: dropped %.2f m, %d physics frames airborne, %d frames in the falling pose" % [t[2], y0 - p.global_position.y, air, fall_pose])
	get_tree().quit()
