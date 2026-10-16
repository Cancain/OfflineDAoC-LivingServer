extends Node
## Debug (owner 2026-10-10, old-version report "Fortune of Few missing"): a level 11 Armsman at Captain Alphin (the
## Armsman trainer, City of Camelot) - is the quest offered and marked while his training window opens?
##   --skip-login --zone=26 --realm=alb --figure=bri_m --ui-test --probe=trainer_quest_probe [--out=<folder>]
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	PlayerData.character["class_id"] = 2                        # Armsman
	PlayerData.level = 11
	PlayerData.quests = {}
	PlayerData.quests_done = {}
	var eng: QuestEngine = viewer.quests
	print("[tq] Fortune of Few qualifies: ", eng.qualifies(QuestDb.quest("20163")))
	var npc: Npc = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if String(st.spawn.name) == "Captain Alphin":
			viewer.player.global_position = st.pos + Vector3(1.5, 0.3, 0)
			print("[tq] Alphin at ", st.pos)
			for i in 80:
				await get_tree().create_timer(0.1).timeout
				if st.view:
					npc = st.view
					break
	if npc == null:
		print("[tq] no Captain Alphin")
		get_tree().quit()
		return
	viewer.player.face(atan2(-(npc.global_position.x - viewer.player.global_position.x), -(npc.global_position.z - viewer.player.global_position.z)))
	viewer.player.global_position = npc.global_position + Vector3(1.5, 0.3, 0)
	await get_tree().create_timer(4.0).timeout
	print("[tq] player at ", viewer.player.global_position, " npc at ", npc.global_position)
	var markers := npc.find_children("*", "", true, false).filter(func(n): return "ring" in String(n.name).to_lower() or "marker" in String(n.name).to_lower())
	print("[tq] marker nodes on Alphin: ", markers.map(func(n): return String(n.name)))
	var out := String(viewer.args.get("out", ""))
	if out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/alphin_marker.png")
	viewer.npcs.interact(npc)
	await get_tree().create_timer(0.8).timeout
	print("[tq] dialog visible ", viewer.ui.npc_dialog.visible)
	if out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/alphin_talk.png")
	get_tree().quit()
