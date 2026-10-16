extends Node
## Debug: /wave, /bow ... (EmoteCommandHandler): the animation and the lines, the 3 s guard, a target's line.
##   --headless --skip-login --zone=200 --figure=cel_m --ui-test --probe=emote_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, k): print("[chat] ", k, ": ", t))
	var p = viewer.player
	for cmd in ["wave", "bow", "dance"]:
		PlayerData.emote_requested.emit(cmd)
		print("[emote] /", cmd, " playing ", p._action)
		await get_tree().create_timer(3.2).timeout
	PlayerData.emote_requested.emit("cheer")
	PlayerData.emote_requested.emit("cheer")               # too soon
	await get_tree().create_timer(3.2).timeout
	var n: Npc = viewer.npcs.nearest_enemy(80.0)
	if n:
		viewer.npcs.target = n
		viewer.player.global_position = n.global_position + Vector3(3, 0, 0)
		PlayerData.emote_requested.emit("point")
	var have := 0
	for i in range(1, 47):
		if p._anim and p._anim.has_animation("emote_%d" % i):
			have += 1
	print("[emote] figure has ", have, " emote clips")
	get_tree().quit()
