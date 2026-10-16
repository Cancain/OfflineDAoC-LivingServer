extends Node
## Debug, test server (owner 2026-10-15: "my sit hotkey of x doesn't do anything at all"; V = sprint): presses X, then
## X again, then V as real key events and logs who sees them, your sitting flag, clip and the server's status after.
## Runs once; hard stop 60 s.
var v: Node
var t0 := 0


func _ready() -> void:
	if get_tree().root.has_meta("sit_key_ran"):
		return
	get_tree().root.set_meta("sit_key_ran", true)
	get_tree().create_timer(60.0).timeout.connect(func(): Server.quit_world(true))
	v = get_tree().current_scene
	t0 = Time.get_ticks_msec()
	PlayerData.message.connect(func(t, _k): _log("chat: " + String(t)))
	await _wait(10.0)
	_log("bindings: sit %s sprint %s, focus %s, typing %s" % [Keybinds.bindings.get("sit"), Keybinds.bindings.get("sprint"),
			get_viewport().gui_get_focus_owner(), v.player._ui_typing()])
	for k in [KEY_X, KEY_X, KEY_V]:
		_log("press %s" % OS.get_keycode_string(k))
		_key(k, true)
		await get_tree().process_frame
		_key(k, false)
		for i in 3:
			await _wait(0.8)
			var a: AnimationPlayer = v.player.get("_anim")
			_log("   sitting %s, clip '%s', vel %.2f" % [v.player.sitting, a.current_animation if a else "-",
					Vector2(v.player.velocity.x, v.player.velocity.z).length()])
	Server.quit_world(true)


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)


func _log(s: String) -> void:
	print("[sk] %6d ms  %s" % [Time.get_ticks_msec() - t0, s])


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
