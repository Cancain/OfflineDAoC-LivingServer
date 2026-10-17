extends Node
## Debug (owner 2026-10-14: tendrils are vine effects on an invisible body): on a test server run, beside a tendril
## (Aegirhamn): the vine effect nodes on it as the server's Tangling Vines (5206) come, their size, and a close shot
## (ground clutter hidden) user://tendril.png; then the window closes itself.
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await _wait(8.0)
	if get_tree().current_scene.get("zone") and int(Server.entry.get("region", 0)) != 151:
		Server.command("/jump to 273718 350738 4464 151")
		await _wait(18.0)
		return                                             # (a new scene: its own probe carries on)
	await _wait(6.0)
	var sw: ServerWorld = v.npcs
	var mob: NpcState = null
	for st in sw.by_oid.values():
		var s: NpcState = st
		if String(s.spawn.name) == "tendril" and s.view and (mob == null or
				s.pos.distance_to(v.player.global_position) < mob.pos.distance_to(v.player.global_position)):
			mob = s
	if mob == null:
		print("[tendril] none in view")
		get_tree().quit()
		return
	var n: Npc = mob.view
	print("[tendril] at %.1f m, size %s, model scale %s, SpellFx.size_of %.2f" % [mob.pos.distance_to(v.player.global_position),
			mob.spawn.get("size"), n.model.scale if n.model else "-", SpellFx.size_of(n)])
	if v.clutter:
		v.clutter.visible = false
	for i in 8:
		await _wait(0.5)
		var fx := []
		for k in SpellFx._live:
			var node = SpellFx._live[k]
			if is_instance_valid(node) and n.is_ancestor_of(node):
				fx.append("%s scale %.2f" % [node.name, (node as Node3D).global_basis.get_scale().y])
		if not fx.is_empty():
			print("[tendril] effect nodes on it: ", fx)
			break
	# stand 3 m from it, facing it
	var to: Vector3 = n.global_position - v.player.global_position
	to.y = 0.0
	v.player.global_position = n.global_position - to.normalized() * 3.0 + Vector3(0, 0.5, 0)
	v.player.face(atan2(-to.x, -to.z))
	await _wait(2.5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://tendril.png")
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
