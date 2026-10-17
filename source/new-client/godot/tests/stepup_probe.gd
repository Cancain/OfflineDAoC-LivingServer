extends Node
## Debug: the client-style step-up. Walk the player at the Mag Mell castle platform ledge (0.26 m) and across open
## ground, log height / grounded each 0.25 s.

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var viewer := get_tree().current_scene
	var p: Player = viewer.player
	for case in [["ledge (west)", Vector2(16606, 4358), PI / 2.0, KEY_W], ["open ground run", Vector2(25900, 9000), 0.0, KEY_W],
			["jump in place", Vector2(25900, 9000), 0.0, KEY_SPACE], ["into the Elf Hall (east)", Vector2(26400, 7298), -PI / 2.0, KEY_W]]:
		var x: float = case[1].x * 0.025
		var z: float = case[1].y * 0.025
		p.global_position = Vector3(x, viewer.zone.height_at(x, z) + 0.05, z)
		p.velocity = Vector3.ZERO
		p.char_yaw = case[2]
		p.cam_yaw = case[2]
		await get_tree().create_timer(0.5).timeout
		var y0 := p.global_position.y
		var line := []
		_key(case[3], true)
		for i in 8:
			await get_tree().create_timer(0.25).timeout
			line.append("%+.2f%s" % [p.global_position.y - y0, "g" if p.grounded else "a"])
			if i == 0:
				_key(case[3], false) if case[3] == KEY_SPACE else null
		_key(case[3], false)
		print("%s: moved %.1f m, height: %s" % [case[0], Vector2(p.global_position.x - x, p.global_position.z - z).length(), " ".join(line)])
	get_tree().quit()


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
