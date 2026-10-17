extends Node
## Debug: NPC equipment (Greagoir) and the player's worn armour. --probe=dress_probe --out=<folder> (--ui-test, cel_m)
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var out := String(viewer.args.get("out", "user://dress_probe"))
	DirAccess.make_dir_recursive_absolute(out)
	var p: Player = viewer.player
	var npcs: NpcManager = viewer.npcs
	for name in ["Greagoir", "Sentinel", "Wony"]:
		var st: NpcState = null
		for s in npcs.states:
			if String((s as NpcState).spawn.name) == name:
				st = s
				break
		if st == null:
			continue
		var at: Vector3 = st.pos + Vector3(sin(st.yaw), 0, cos(st.yaw)) * 3.0
		at.y = viewer.zone.height_at(at.x, at.z) + 0.2
		p.global_position = at
		p.face(atan2(-(st.pos.x - at.x), -(st.pos.z - at.z)))
		p.visible = false                                  # the NPC alone in the shot
		p.cam_distance = 0.4
		p.cam_pitch = -0.05
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/npc_%s.png" % [out, name])
		print("[dress] ", name, " equipment ", st.spawn.get("equipment", ""), " rows ", npcs.data.equipment.get(String(st.spawn.get("equipment", "")), []).size())
	for slot_item in [[25, "woolen_padded_vest"], [27, "woolen_padded_pants"], [28, "woolen_padded_sleeves"],
			[22, "woolen_padded_gloves"], [23, "woolen_padded_boots"]]:
		PlayerData.inventory[slot_item[0]] = {"id": slot_item[1], "count": 1}
	p.visible = true
	p.refresh_gear()
	viewer._go_to_spot(viewer._spot_index)
	p.cam_distance = 2.6
	p.cam_yaw = p.char_yaw + PI
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/player_padded.png" % out)
	get_tree().quit()
