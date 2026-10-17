extends Node
## Debug: drive the player with injected input and log the animation state (strafe freeze investigation).
var viewer: Node

func _ready() -> void:
	await get_tree().create_timer(3.0).timeout
	viewer = get_tree().current_scene
	var p: Player = viewer.player
	for combo in [["", KEY_W], ["", KEY_S], ["rmb", KEY_D], ["", KEY_E], ["", KEY_A]]:
		if combo[0].begins_with("rmb"):
			_mouse(true)
		var start := p.global_position
		var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, p.char_yaw)
		var right_v := Vector3(1, 0, 0).rotated(Vector3.UP, p.char_yaw)
		_key(combo[1], true)
		var yaw0 := p.char_yaw
		for i in 4:
			for f in 15:
				if combo[0] == "rmb_move":
					var m := InputEventMouseMotion.new()
					m.relative = Vector2(3, 0)
					m.button_mask = MOUSE_BUTTON_MASK_RIGHT
					Input.parse_input_event(m)
				await get_tree().process_frame
			var a := p._anim
			print("%s+%s t=%.2f clip=%s pos=%.3f speed=%.2f playing=%s" % [combo[0], OS.get_keycode_string(combo[1]), i * 0.25,
				a.current_animation, a.current_animation_position, a.speed_scale, a.is_playing()])
		var moved := p.global_position - start
		print("  [%s] %s+%s moved: right %.1f m, forward %.1f m in 1 s, turned %.0f deg, clip %s at x%.2f" % [p.movement_mode, combo[0], OS.get_keycode_string(combo[1]), moved.dot(right_v), moved.dot(fwd), rad_to_deg(p.char_yaw - yaw0), p._anim.current_animation, p._anim.speed_scale])
		_key(combo[1], false)
		if combo[0].begins_with("rmb"):
			_mouse(false)
		await get_tree().create_timer(0.5).timeout
	get_tree().quit()

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)

func _mouse(down: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = down
	e.position = Vector2(400, 300)
	Input.parse_input_event(e)
