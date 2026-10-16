extends Node
## Debug (hood_skald_probe): left under the root before a jump to another region - the new world's speed for you
## against the server's last MaxSpeed, then a proper /quit.


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	Server.world.connect(func(k: String, d: Dictionary):
		if k == "max_speed":
			print("[hs] %+d ms: MaxSpeed %d%%" % [Time.get_ticks_msec() - t0, int(d.percent)]))
	var first := get_tree().current_scene
	for i in 40:
		await get_tree().create_timer(0.5).timeout
		var s := get_tree().current_scene
		if s != first and s and s.get("player") and Server.playing:
			await get_tree().create_timer(2.0).timeout
			print("[hs] after the region change (%s): server speed %d%%, your speed x%.2f  effects %s" % [
					s.zone.info.name if s.get("zone") else "?", Server.max_speed_pct, s.player.encumbrance, _effects()])
			Server.use("srv:spell:0:1")                        # (ends the login stealth)
			await get_tree().create_timer(5.0).timeout
			print("[hs] out of stealth: server speed %d%%, your speed x%.2f  effects %s" % [Server.max_speed_pct,
					s.player.encumbrance, _effects()])
			break
	Server.quit_world(true)


func _effects() -> Array:
	return Server.effects.values().map(func(e): return e.get("name", "?"))
