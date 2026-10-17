extends Node
## Debug, local (owner 2026-10-15: the spiritmaster's spirit pets - ghost race figures - don't match the old client):
## the nearest race-figure NPC drawn with the GHOST flag, pictures from the front at a few distances. Runs once (60 s).
##   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --figure=bri_m --probe=ghost_look_probe --out=<folder>
var v: Node


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	var out := String(v.args.get("out", "user://ghost_look"))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(8.0).timeout
	var st: NpcState = null
	for s in v.npcs.states:
		var x: NpcState = s
		if x.view and x.view.model is Fig3Figure and (st == null or x.pos.distance_to(v.player.global_position) < st.pos.distance_to(v.player.global_position)):
			st = x
	if st == null:
		print("[ghost] no figure")
		get_tree().quit()
		return
	st.wait = 1e9
	st.spawn["flags"] = int(st.spawn.get("flags", 0)) | Npc.FLAG_GHOST
	v.npcs.active.erase(st.index)
	st.view.queue_free()
	st.view = null
	await get_tree().create_timer(2.0).timeout
	print("[ghost] ", st.spawn.name, " view ", st.view != null)
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	var fwd := Vector3(sin(st.yaw), 0, cos(st.yaw))
	for d in [2.5, 5.0]:
		cam.global_position = st.pos + fwd * d + Vector3(0, 1.6, 0)
		cam.look_at(st.pos + Vector3(0, 1.1, 0))
		await get_tree().create_timer(0.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("ghost_%.1f.png" % d))
	get_tree().quit()
