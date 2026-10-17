extends Node
## Debug (owner 2026-10-10: /follow /stick /face, /invite): targets an NPC about 10 m away and tries each command.
##   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --probe=track_probe
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var best: Npc = null
	for st in v.npcs.states:
		var s: NpcState = st
		if s.view and s.alive:
			var d: float = s.pos.distance_to(v.player.global_position)
			if d > 8.0 and d < 20.0 and (best == null or absf(d - 10.0) < absf(best.global_position.distance_to(v.player.global_position) - 10.0)):
				best = s.view
	v.npcs.select(best)
	var gap := func(): return snappedf(Vector2(best.global_position.x - v.player.global_position.x, best.global_position.z - v.player.global_position.z).length(), 0.01)
	print("[track] target ", best.spawn.name, " at ", gap.call(), " m")
	PlayerData.track_requested.emit("follow")
	await get_tree().create_timer(4.0).timeout
	print("[track] after 4 s of /follow: ", gap.call(), " m  mode ", v.player.track_mode)
	PlayerData.track_requested.emit("stick")
	await get_tree().create_timer(2.0).timeout
	print("[track] after 2 s of /stick: ", gap.call(), " m  mode ", v.player.track_mode)
	PlayerData.track_requested.emit("face")
	v.player.char_yaw += 2.0
	await get_tree().create_timer(0.5).timeout
	var d: Vector3 = best.global_position - v.player.global_position
	print("[track] /face: yaw off by ", snappedf(rad_to_deg(angle_difference(v.player.char_yaw, atan2(-d.x, -d.z))), 0.1), " deg")
	Input.action_press("move_back")
	await get_tree().create_timer(0.3).timeout
	Input.action_release("move_back")
	print("[track] after moving: mode '", v.player.track_mode, "'")
	PlayerData.invite_requested.emit("")
	best.spawn["gamebot"] = true
	PlayerData.invite_requested.emit("")
	get_tree().quit()
