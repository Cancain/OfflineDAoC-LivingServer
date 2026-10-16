extends Node
## Debug, local (owner 2026-10-15: "the cloak being stuck in motion when the models have stopped"): your figure with a
## cloak runs 2 s (W held), stops; the clip and the centre cloak's lowest bone (height under the neck, distance
## behind) logged, and pictures from behind just after the stop and 3 s later. Runs once (hard stop 60 s).
##   --screen 1 --skip-login --zone=152 --figure=nor_m --probe=cloak_stop_probe --out=<folder>
var v: Node


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	var out := String(v.args.get("out", "user://cloak_stop"))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(6.0).timeout
	var p: Player = v.player
	var fig := p._model as Fig3Figure
	if fig == null:
		print("[cloak] no figure")
		get_tree().quit()
		return
	fig.set_armor({"cloak": [1, "cat_cloak"]}, {})
	p.cam_distance = 4.0
	await get_tree().create_timer(1.0).timeout
	_log(p, fig, "standing")
	_key(KEY_W, true)
	await get_tree().create_timer(2.0).timeout
	_log(p, fig, "running")
	_key(KEY_W, false)
	var waited := 0.0
	for t in [0.1, 0.4, 1.0, 3.0]:
		await get_tree().create_timer(t - waited).timeout
		waited = t
		_log(p, fig, "stopped +%.1f s" % t)
		if t in [0.4, 3.0]:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("stop_%.1f.png" % t))
	get_tree().quit()


func _log(p: Player, fig: Fig3Figure, what: String) -> void:
	var sk: Skeleton3D = fig.find_children("*", "Skeleton3D", true, false)[0]
	var tip := sk.find_bone("Bip01 C Cloak05")
	var neck := sk.find_bone("Bip01 Neck")
	var d := sk.get_bone_global_pose(tip).origin - sk.get_bone_global_pose(neck).origin
	print("[cloak] %-16s clip %-10s pos %.2f playing %s blend-tip below neck %.2f behind %.2f" % [what, p._anim.current_animation,
			p._anim.current_animation_position, p._anim.is_playing(), -d.y, d.z])


func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
