extends Node
## Debug (owner 2026-10-10: monster drops + auto loot): kills of a monster with item drops (as if killed) with auto loot
## on, then off (on the ground), picking one up, dropping a backpack item on the ground. --out: a picture of the ground.
##   --screen 1 --skip-login --zone=200 --figure=cel_m --ui-test --probe=loot_probe [--mob=young poacher] [--out=...]
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var lines := []
	PlayerData.message.connect(func(t, k):
		if k in ["loot", "system"]:
			lines.append(t))
	var want := String(v.args.get("mob", ""))
	var mob: NpcState = null
	for s in v.npcs.states:                                # a monster here with item drops
		var st: NpcState = s
		var d: Dictionary = (Loot.data().drops as Dictionary).get(String(st.spawn.name).to_lower(), {})
		if int(st.spawn.realm) == 0 and not (d.get("items", []) as Array).is_empty() and (want == "" or String(st.spawn.name) == want):
			mob = st
			break
	print("[loot] monster: ", mob.spawn.name, " level ", mob.level, " drops ", (Loot.data().drops as Dictionary).get(String(mob.spawn.name).to_lower()))
	v.player.global_position = mob.pos + Vector3(2.5, 0.5, 0)
	await get_tree().create_timer(1.5).timeout
	var c0 := PlayerData.total_copper()
	var used0 := PlayerData.inventory.size()
	Loot.set_autoloot(true)
	for i in 20:
		v.loot.on_kill(mob)
	print("[loot] auto loot ON, 20 kills: copper +", PlayerData.total_copper() - c0, " items +", PlayerData.inventory.size() - used0)
	for l in lines.slice(0, 8):
		print("   ", l)
	lines.clear()
	Loot.set_autoloot(false)
	for i in 3:
		v.loot.on_kill(mob)
	print("[loot] auto loot OFF, 3 kills: on the ground ", v.loot._ground.size())
	for g in v.loot._ground.slice(0, 3):
		var nd: Node3D = g.node
		print("[loot]   at ", nd.global_position, " visible ", nd.is_visible_in_tree(), " children ", nd.get_children().map(func(c): return c.get_class() + ":" + str(c.get_child_count())),
				" player ", v.player.global_position)
	var first: Node3D = v.loot._ground[0].node
	v.player.global_position = first.global_position + Vector3(2.0, 0.3, 0.0)
	v.player.char_yaw = PI * 0.5
	v.player.cam_yaw = PI * 0.5
	await get_tree().create_timer(1.0).timeout
	v.player.cam_distance = 2.5
	v.player.cam_pitch = -0.5
	await get_tree().create_timer(1.0).timeout
	if v.args.has("out"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(String(v.args.out) + "/ground_loot.png")
	# pick one up: click where it is on screen
	var g: Dictionary = v.loot._ground[0]
	var sp: Vector2 = v.player.camera.unproject_position((g.node as Node3D).global_position + Vector3(0, 0.2, 0))
	print("[loot] click on ", "coins" if String(g.id) == "" else String(g.id), ": ", v.loot.click(sp), " left ", v.loot._ground.size())
	# drop a backpack item
	var slot := -1
	for s in PlayerData.inventory:
		if PlayerData.is_backpack(s):
			slot = s
			break
	if slot >= 0:
		v.loot.drop_from_inventory(slot)
	print("[loot] after drop: on the ground ", v.loot._ground.size())
	for l in lines:
		print("   ", l)
	get_tree().quit()
