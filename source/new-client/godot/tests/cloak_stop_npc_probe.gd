extends Node
## Debug, local (owner 2026-10-15: bots' cloaks "stuck in motion" once they stop - only gamebots / companions): the
## nearest NPC with a race figure gets a cloak, runs 2 s (its state, as ServerWorld's mover sets it) and stops; its clip
## and the centre cloak's lowest bone (under the neck / behind) logged, a picture after the stop. Runs once (60 s cap).
##   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --figure=bri_m --probe=cloak_stop_npc_probe --out=<folder>
var v: Node


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	var out := String(v.args.get("out", "user://cloak_stop_npc"))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(8.0).timeout
	var n: Npc = null
	for s in v.npcs.states:
		var st: NpcState = s
		if st.view and st.view.model is Fig3Figure and (n == null or
				st.pos.distance_to(v.player.global_position) < n.state.pos.distance_to(v.player.global_position)):
			n = st.view
	if n == null:
		print("[cloak] no figure NPC")
		get_tree().quit()
		return
	var st: NpcState = n.state
	st.wait = 1e9
	st.roam = 0.0
	(n.model as Fig3Figure).set_armor({"cloak": [1, "cat_cloak"]}, {})
	print("[cloak] npc ", n.spawn.name, " ", n.info.get("race"), " threaded ", AnimLod.threaded)
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	var follow := func():
		cam.global_position = st.pos + Vector3(sin(st.yaw), 0, cos(st.yaw)) * -4.0 + Vector3(0, 2.0, 0)
		cam.look_at(st.pos + Vector3(0, 1.2, 0))
	follow.call()
	await get_tree().create_timer(1.0).timeout
	_log(n, "standing")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		st.mode = NpcState.Mode.WALK
		st.running = true
		st.pos += Vector3(sin(st.yaw), 0, cos(st.yaw)) * 5.0 * get_process_delta_time()
		follow.call()
		await get_tree().process_frame
	_log(n, "running")
	st.mode = NpcState.Mode.IDLE
	st.running = false
	var waited := 0.0
	for t in [0.2, 0.5, 1.0, 3.0]:
		await get_tree().create_timer(t - waited).timeout
		waited = t
		_log(n, "stopped +%.1f s" % t)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("npc_stop.png"))
	get_tree().quit()


func _log(n: Npc, what: String) -> void:
	var sk: Skeleton3D = n.model.find_children("*", "Skeleton3D", true, false)[0]
	var d := sk.get_bone_global_pose(sk.find_bone("Bip01 C Cloak05")).origin - sk.get_bone_global_pose(sk.find_bone("Bip01 Neck")).origin
	print("[cloak] %-15s mode %d clip %-12s pos %.2f playing %s tip below neck %.1f behind %.1f" % [what, n.state.mode,
			n.anim.current_animation, n.anim.current_animation_position, n.anim.is_playing(), -d.y, d.z])
