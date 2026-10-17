extends Node
## Debug (bot plan phase 3, the zone handover): with a test world host running (--world-dir), the game takes this
## zone's bots, draws them, a click targets one (nameplate white, "You target [...]"), Ctrl+F11's inspect text, the
## map's green dots; pictures near a bot.
##   host:  Godot_mono --headless --path godot res://game/world_host/world_host.tscn -- --world-dir=<T> --total=30
##   game:  Godot_mono --path godot --screen 1 -- --skip-login --zone=<Z> --figure=cel_m --with-loading --with-bots
##          --world-dir=<T> --probe=bot_handover_probe --out=<dir>
func _ready() -> void:
	var v := get_tree().current_scene
	var chat: Array = []
	PlayerData.message.connect(func(t, _k): chat.append(String(t)))
	for i in 60:
		await get_tree().create_timer(1.0).timeout
		if WorldLink.bots and int(WorldLink.bots.get("Count")) > 0:
			break
	var gb: Node = WorldLink.bots
	print("[handover] GameBots %s, bots in the game: %d" % ["present" if gb else "MISSING", int(gb.get("Count")) if gb else 0])
	if gb == null or int(gb.get("Count")) == 0:
		get_tree().quit()
		return
	var views: Array = v.zone.get_children().filter(func(c): return c is BotView)
	var view: Node3D = views[0]
	print("[handover] first bot: %s (%s) at %s" % [view.call("display_name"), String(view.get("record").realm), view.global_position.snapped(Vector3.ONE * 0.1)])
	# stand by it, look at it, click it
	var to := view.global_position
	v.player.global_position = to + Vector3(3, 0.5, 3)
	v.player.hold()
	await get_tree().create_timer(2.0).timeout
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	to = view.global_position
	cam.global_position = to + Vector3(3.5, 2.0, 3.5)
	cam.look_at(to + Vector3(0, 1.0, 0))
	await get_tree().create_timer(0.3).timeout
	to = view.global_position                              # where it is now (it keeps running)
	var picked: Node3D = WorldLink.pick_bot(cam, cam.unproject_position(to + Vector3(0, 1.0, 0)))
	print("[handover] click on it picks: ", picked.call("display_name") if picked else "nothing")
	if picked:
		WorldLink.target_bot(picked)
	await get_tree().create_timer(0.5).timeout
	WorldLink.inspect_target()
	print("[handover] map dots: ", WorldLink.bot_dots().size())
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(String(v.args.get("out", "user://")).path_join("bot_near.png"))
	await get_tree().create_timer(6.0).timeout
	print("[handover] after 6 s the bot is at %s, state %s" % [view.global_position.snapped(Vector3.ONE * 0.1), view.get("_state")])
	for line in chat:
		if line.begins_with("You target") or line.begins_with("[BOT]"):
			print("[handover] chat: ", line)
	get_tree().quit()
