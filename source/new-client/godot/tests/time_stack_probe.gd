extends Node
## Debug (owner 2026-10-14: the time of day jumped 11:00 -> 19:00; bots stood on each other / up a tree). On a test
## server run: your class back to the Animist (an earlier test left it a bonedancer); every Time packet against the
## sky's clock; then a jump to another region (time_stack_run.gd) - the new world's clock before and after the
## server's Time, and every drawn NPC's height over the floor under it for 30 s.


func _ready() -> void:
	var v := get_tree().current_scene
	Server.world.connect(func(k: String, d: Dictionary):
		if k == "time":
			var s := get_tree().current_scene
			var sky = s.get("sky") if s else null
			var ld = s.get("loading") if s else null
			print("[ts] Time packet: %.2f h, increment %d  (sky was %.2f h, loading screen %s)" % [int(d.time) / 3600000.0,
					int(d.increment), sky.hour() if sky else -1.0, "UP" if ld and is_instance_valid(ld) else "gone"]))
	await get_tree().create_timer(8.0).timeout
	Server.client.call("Target", Server.me_oid, 0x6000)
	await get_tree().create_timer(1.0).timeout
	Server.command("/player class 55")
	await get_tree().create_timer(3.0).timeout
	print("[ts] here: sky %.2f h, server clock %.2f h" % [v.sky.hour(), Server.game_hour()])
	var helper := Node.new()
	helper.set_script(load("res://tests/time_stack_run.gd"))
	get_tree().root.add_child(helper)
	var in_tnn := int(Server.entry.get("region", 0)) == 201
	Server.command("/jump to 319488 450560 5728 200" if in_tnn else "/jump to 29825 33165 7920 201")
