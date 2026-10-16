extends Node
## Debug, on the running server with Claude's test account (owner 2026-10-15: "i spawned in a skald, was walking with it
## from town, and everytime i would stop its cloak was stuck flowing"): /spawn skald, walk 4 s, stop; every 0.5 s the
## companion's move packets (speed, destination, target), its state and clip, and its cloak (centre tip under the neck
## / behind). Runs once, quits (90 s cap).
##   server_session.tscn -- --server=127.0.0.1 --account=<a> --password=<p> --char=<c> --probe=companion_stop_probe
var v: Node
var sw: ServerWorld
var helper := 0
var last_move := {}


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func():
		Server.quit_world(true)
		get_tree().create_timer(5.0).timeout.connect(func(): get_tree().quit()))
	v = get_tree().current_scene
	PlayerData.message.connect(func(t, _k):
		if String(t).to_lower().contains("skald") or String(t).contains("joined"):
			print("[chat] ", t))
	await get_tree().create_timer(8.0).timeout
	sw = v.npcs
	var before := sw.by_oid.keys()
	Server.world.connect(func(kind: String, d: Dictionary):
		var oid := int(d.get("oid", -1))
		if helper == 0 and kind == "npc" and not before.has(oid) and String(d.get("name", "")) != "" \
				and int(d.get("level", 0)) & 0x7F > 0:
			helper = oid
		if oid == helper and kind == "move":
			last_move = {"speed": int(d.speed), "tx": int(d.tx), "ty": int(d.ty), "target": int(d.target), "flags": int(d.flags)})
	Server.command("/spawn skald")
	await get_tree().create_timer(12.0).timeout
	_log("after spawn")
	_key(KEY_W, true)
	for i in 8:
		await get_tree().create_timer(0.5).timeout
		_log("walking %.1f" % ((i + 1) * 0.5))
	_key(KEY_W, false)
	for i in 14:
		await get_tree().create_timer(0.5).timeout
		_log("stopped %.1f" % ((i + 1) * 0.5))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(String(v.args.get("out", "user://")).path_join("companion_stop.png"))
	Server.quit_world(true)


func _log(what: String) -> void:
	var st: NpcState = sw.by_oid.get(helper)
	if st == null:
		print("[comp] %s no helper (%d)" % [what, helper])
		return
	var mv: Dictionary = sw._mover.get(st, {})
	var line := "[comp] %-12s %s mode %d running %s fighting %s mover speed %s dest %s | last packet %s" % [what,
			st.spawn.name, st.mode, st.running, st.fighting, mv.get("speed"), mv.get("dest") != null, last_move]
	var n := st.view as Npc
	if n and n.anim and n.model is Fig3Figure:
		var sk: Skeleton3D = n.model.find_children("*", "Skeleton3D", true, false)[0]
		var tip := sk.find_bone("Bip01 C Cloak05")
		var neck := sk.find_bone("Bip01 Neck")
		var d := sk.get_bone_global_pose(tip).origin - sk.get_bone_global_pose(neck).origin
		line += " | clip %s @%.2f action %.2f cast %s | cloak under neck %.1f behind %.1f" % [n.anim.current_animation,
				n.anim.current_animation_position, n._action_left, n.casting_spell, -d.y, d.z]
	print(line)


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
