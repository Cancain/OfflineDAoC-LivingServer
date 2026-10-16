extends Node
## Debug: a classic quest end to end - "Please Deliver!" (Ula -> Dirmyg, Lough Derg, Stalker level 2): the offer, the
## keyword chain, the accept (the letter is handed over), the delivery and the rewards.
##   --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=quest_probe --out=<folder>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): print("[chat] ", t))
	var out := String(viewer.args.get("out", "user://quest"))
	PlayerData.character["class_id"] = 54                       # Stalker
	PlayerData.level = 2
	PlayerData.quests = {}
	PlayerData.quests_done = {}
	var eng: QuestEngine = viewer.quests
	var ula := await _npc("Ula")
	viewer.player.global_position = ula.global_position + Vector3(0, 0.3, 8)
	viewer.player.face(atan2(-(ula.global_position.x - viewer.player.global_position.x), -(ula.global_position.z - viewer.player.global_position.z)))
	await get_tree().create_timer(2.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/quest_marker.png" % out)
	print("[quest] interact Ula: ", eng.on_interact(ula))
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/quest_offer.png" % out)
	eng.on_keyword(ula, "have time")
	eng.on_keyword(ula, "appreciate")
	print("[quest] active ", PlayerData.quests, " letter slot ", PlayerData.find_item("cq_letter_from_ula"))
	viewer.ui.journal.show_window()
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/quest_journal.png" % out)
	viewer.ui.npc_dialog.hide_window()
	viewer.ui.journal.position = Vector2(900, 300)
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/quest_journal2.png" % out)
	viewer.ui.show_guide("20818")
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/quest_guide.png" % out)
	viewer.ui.guide.hide_window()
	viewer.ui.journal.hide_window()
	var dir := await _npc("Dirmyg")
	var xp0 := PlayerData.xp
	var copper0 := PlayerData.total_copper()
	print("[quest] give letter: ", eng.on_give(dir, PlayerData.find_item("cq_letter_from_ula")))
	print("[quest] done ", PlayerData.quests_done, " active ", PlayerData.quests, " xp +", PlayerData.xp - xp0, " copper +", PlayerData.total_copper() - copper0)
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/quest_done.png" % out)
	get_tree().quit()


## Stand by the NPC so its view exists; returns its Npc.
func _npc(npc_name: String) -> Npc:
	for s in viewer.npcs.states:
		var st: NpcState = s
		if String(st.spawn.name) == npc_name:
			viewer.player.global_position = st.pos + Vector3(1.5, 0.3, 0)
			for i in 40:
				await get_tree().create_timer(0.1).timeout
				if st.view:
					return st.view
	print("[quest] no NPC ", npc_name)
	return null
