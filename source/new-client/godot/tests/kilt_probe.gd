extends Node
## Debug (owner 2026-10-10: white kilts on Camelot Hills weapon merchants): pictures of two armoured Highlander NPCs.
##   --screen 1 --skip-login --zone=0 --pos=320.5,60,679.1 --probe=kilt_probe --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(7.0).timeout
	var cam := Camera3D.new()
	v.add_child(cam)
	var i := 0
	for st in v.npcs.states:
		var s: NpcState = st
		if String(s.spawn.name) in ["Grannis Ynos", "Bedamor Routh"] and s.view:
			var n: Node3D = s.view
			var fwd := -n.global_transform.basis.z
			cam.global_position = n.global_position + Vector3(0, 1.2, 0) + n.global_transform.basis.z * -2.6
			cam.look_at(n.global_position + Vector3(0, 0.9, 0))
			cam.current = true
			await get_tree().create_timer(1.0).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/kilt_%d.png" % [String(v.args.get("out", "user://")), i])
			print("[kilt] ", s.spawn.name, " model ", s.spawn.model)
			i += 1
	get_tree().quit()
