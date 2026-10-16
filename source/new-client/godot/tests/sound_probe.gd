extends Node
## Debug (owner 2026-10-14: the quest begun / completed sounds): in the server's game, asks for the server's sound
## effects with the GM /cast sound command (Claude's test account only) and lists what plays.
##   tests/server_session.tscn ... --probe=sound_probe


func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	Server.world.connect(func(kind: String, d: Dictionary):
		if kind == "sound_effect":
			print("[sound] packet ", d)
			_count.call_deferred())
	for id in [7, 11]:
		Server.command("/cast sound %d" % id)
		await get_tree().create_timer(3.0).timeout
	get_tree().quit()


func _count() -> void:
	var n := 0
	for p in get_tree().current_scene.npcs.get_children():
		if p is AudioStreamPlayer and (p as AudioStreamPlayer).playing:
			n += 1
	print("[sound] server sounds playing now: ", n)
