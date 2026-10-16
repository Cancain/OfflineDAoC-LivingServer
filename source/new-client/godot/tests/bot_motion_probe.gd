extends Node
## Debug (bot plan phase 3): every second for 20 s, each in-game bot's movement state (GameBots.Debug).
##   game: Godot_mono --path godot --screen 1 -- --skip-login --zone=<Z> --figure=cel_m --with-loading --with-bots
##         --world-dir=<T> --probe=bot_motion_probe
func _ready() -> void:
	for i in 60:
		await get_tree().create_timer(1.0).timeout
		if WorldLink.bots and int(WorldLink.bots.get("Count")) > 0:
			break
	var gb: Node = WorldLink.bots
	if gb == null:
		get_tree().quit()
		return
	var ids: Array = gb.call("Ids")
	for t in 20:
		for id in ids.slice(0, 3):
			print("[motion] t=%2d bot %d: %s" % [t, id, gb.call("Debug", id)])
		await get_tree().create_timer(1.0).timeout
	get_tree().quit()
