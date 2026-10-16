extends Node
## Debug (windowed): monsters whose look is a client effect (mist sheerie cloud, dew sheerie water glob).
##   --screen 1 --skip-login --zone=200 --figure=cel_m --ui-test --probe=effect_shots --out=<folder>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var out := String(viewer.args.get("out", "user://fx"))
	DirAccess.make_dir_recursive_absolute(out)
	for nm in ["mist sheerie", "dew sheerie", "swarm of flies"]:
		for s in viewer.npcs.states:
			var st: NpcState = s
			if String(st.spawn.name) == nm and st.alive:
				var at := st.pos + Vector3(4, 0, 0)
				at.y = viewer.zone.height_at(at.x, at.z) + 0.3
				viewer.player.global_position = at
				viewer.player.face(atan2(-(st.pos.x - at.x), -(st.pos.z - at.z)))
				viewer.player.cam_distance = 4.0
				await get_tree().create_timer(3.0).timeout
				print("[fx] ", nm, " view ", st.view != null, " children ", st.view.get_child_count() if st.view else 0)
				get_viewport().get_texture().get_image().save_png("%s/fx_%s.png" % [out, nm.replace(" ", "_")])
				break
	get_tree().quit()
