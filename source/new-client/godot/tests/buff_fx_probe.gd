extends Node
## Debug (owner 2026-10-14: druid buffs show only over the head; the original's are huge, over the whole body): the
## buff's landing effect (SpellFx.land, as a server SpellEffectAnimation lands it) on the player, pictures through its
## life (user://bufffx_<effect>_<n>.png) and the effect's nodes - where they sit, their size, the morph playing.
##   --skip-login --zone=200 --figure=elf_m --probe=buff_fx_probe [--fx=5001]
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await _wait(6.0)
	v.ui.visible = false
	var ce := int(String(v.args.get("fx", "5001")))
	var cam: Camera3D = v.player.camera
	v.player.face(PI)                                       # (the camera sees the front)
	await _wait(0.5)
	var on: Node3D = v.player
	if v.args.has("npc"):                                   # a race-figure NPC (a bot, a guard) instead of yourself
		for k in v.npcs.active:
			var n: Npc = v.npcs.active[k]
			if n.model is Fig3Figure and n.global_position.distance_to(v.player.global_position) < 40.0:
				on = n
				break
		print("[bufffx] on %s: size_of %.2f  model scale %s  height %s" % [on.name, SpellFx.size_of(on),
				(on.get("model") as Node3D).scale if on.get("model") else "-", on.get("height")])
		v.player.global_position = on.global_position + Vector3(0, 0, 5)
		v.player.face(0.0)
		await _wait(0.5)
	SpellFx.land(ce, on, float(on.get("height")) if on is Npc else 1.8, on.get("sounds"))
	var shots := int(String(v.args.get("fx_shots", "6")))
	for i in shots:
		await _wait(0.2 if i == 0 else float(String(v.args.get("fx_step", "0.3"))))
		var nodes := []
		for k in SpellFx._live:
			var n = SpellFx._live[k]
			if is_instance_valid(n) and on.is_ancestor_of(n):
				var aabb := AABB()
				var first := true
				for mi in (n as Node).find_children("*", "MeshInstance3D", true, false):
					var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
					aabb = b if first else aabb.merge(b)
					first = false
				for mi in (n as Node).find_children("morph_*", "MeshInstance3D", true, false):
					var m3 := mi as MeshInstance3D
					nodes.append("  %s visible %s at %s scale %s" % [m3.name, m3.is_visible_in_tree(),
							(m3.global_position - on.global_position).snapped(Vector3.ONE * 0.01),
							m3.global_basis.get_scale().snapped(Vector3.ONE * 0.01)])
				nodes.append("%s at %s scale %.2f mesh box y %.2f..%.2f width %.2f" % [n.name,
						((n as Node3D).global_position - on.global_position).snapped(Vector3.ONE * 0.01),
						(n as Node3D).global_basis.get_scale().y, aabb.position.y - on.global_position.y,
						aabb.end.y - on.global_position.y, aabb.size.x])
		print("[bufffx] %.1f s: %s" % [0.6 + i * 0.8, nodes])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://bufffx_%d_%d.png" % [ce, i])
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
