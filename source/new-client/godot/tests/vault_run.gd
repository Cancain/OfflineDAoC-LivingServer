extends Node
## Debug (vault_probe): in Tir na Nog - each keeper right-clicked; the vault window, its slot range and the items the
## server sent. Hard limit 90 s; a proper /quit at the end.
func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit())
	PlayerData.message.connect(func(t, _k): print("[vault] chat: ", t))
	var first := get_tree().current_scene
	var s: Node = null
	for i in 80:
		await get_tree().create_timer(0.25).timeout
		s = get_tree().current_scene
		if s != first and s and s.get("npcs") and Server.playing:
			break
	await get_tree().create_timer(6.0).timeout
	for keeper in ["Bhreagar Hylvian", "Giorny"]:
		var view: Npc = null
		for t in 40:
			for st in s.npcs.states:
				if String(st.spawn.get("name", "")) == keeper and st.view:
					view = st.view
			if view:
				break
			await get_tree().create_timer(0.5).timeout
		if view == null:
			var near := []
			for st in s.npcs.states:
				if String(st.spawn.get("name", "")).to_lower().contains(keeper.split(" ")[0].to_lower().substr(0, 4)):
					near.append("%s (drawn %s)" % [st.spawn.name, st.view != null])
			print("[vault] %s not drawn; %d states, similar: %s; you at %s" % [keeper, s.npcs.states.size(), near,
					Server.to_region(int(Server.entry.get("zone", 0)), s.player.global_position)])
			continue
		s.ui.vault.visible = false
		s.npcs.select(view)
		s.npcs.interact(view)
		await get_tree().create_timer(2.5).timeout
		var w = s.ui.vault
		var held := 0
		for k in PlayerData.inventory:
			if int(k) >= w.first_slot and int(k) < w.first_slot + w.slot_count:
				held += 1
		print("[vault] %s: window open %s, title %s, slots %d-%d, %d items there, page label %s" % [keeper, w.visible,
				w._title.text, w.first_slot, w.first_slot + w.slot_count - 1, held, w._page_label.text])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://vault_%s.png" % keeper.split(" ")[0])
	Server.quit_world(true)
