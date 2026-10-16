extends Node
## Debug (owner 2026-10-14: a spell clicked while another casts is "queued" in chat but never cast): your first
## spell, then the same one again 1 s into its cast; every chat line, cast / effect / interrupt packet and the position
## updates you send, for 12 s. Runs once, hard limit 60 s.
var t0 := 0


func _ready() -> void:
	if get_tree().root.has_meta("queue_probe_ran"):
		return
	get_tree().root.set_meta("queue_probe_ran", true)
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit())
	var v := get_tree().current_scene
	PlayerData.message.connect(func(t, _k): _log("chat: " + String(t)))
	Server.world.connect(func(k: String, d: Dictionary):
		if k in ["cast", "spell_effect", "interrupt"] and int(d.get("caster", 0)) == Server.me_oid:
			_log("%s packet %s" % [k, {"spell": d.get("spell"), "time": d.get("time")}]))
	await get_tree().create_timer(8.0).timeout
	Server.use("srv:spell:0:1")                           # (breaks the GM login stealth)
	await get_tree().create_timer(5.0).timeout
	t0 = Time.get_ticks_msec()
	_log("first cast")
	Server.use("srv:spell:0:1")
	await get_tree().create_timer(1.0).timeout
	_log("second cast (queued)")
	Server.use("srv:spell:0:1")
	await get_tree().create_timer(11.0).timeout
	Server.quit_world(true)


func _log(s: String) -> void:
	print("[q] %6d ms  %s" % [Time.get_ticks_msec() - t0 if t0 > 0 else -1, s])
