extends Node
## Debug: run downhill (the owner's recording: loc ~21960,7200 heading towards 21000,6650) and log how often the
## player leaves the ground / plays the jump clip while running.

func _ready() -> void:
	await get_tree().create_timer(1.0).timeout
	var viewer := get_tree().current_scene
	var p: Player = viewer.player
	var x := 21962 * 0.025
	var z := 7201 * 0.025
	p.global_position = Vector3(x, viewer.zone.height_at(x, z) + 0.05, z)
	var to := Vector2(21000 - 21962, 6650 - 7201).normalized()
	p.char_yaw = atan2(-to.x, -to.y)                # forward = -Z rotated by yaw
	p.cam_yaw = p.char_yaw
	await get_tree().create_timer(0.3).timeout
	var e := InputEventKey.new()
	e.physical_keycode = KEY_W
	e.keycode = KEY_W
	e.pressed = true
	Input.parse_input_event(e)
	var air := 0
	var jumpclip := 0
	var frames := 0
	var y0 := p.global_position.y
	for i in 360:
		await get_tree().physics_frame
		frames += 1
		if not p.grounded:
			air += 1
		if p._anim and p._anim.current_animation == "jump":
			jumpclip += 1
	print("downhill: dropped %.1f m over %d frames, airborne %d frames, jump clip %d frames" % [y0 - p.global_position.y, frames, air, jumpclip])
	get_tree().quit()
