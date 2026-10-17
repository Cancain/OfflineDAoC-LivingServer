extends Node
## Debug (owner 2026-10-14: floating weapons on the invisible body, model 667): on a test server run, beside an animate
## svard (region 150): its equipment from the server, the weapons hung on it, a close shot user://animate_weapon.png;
## then the window closes itself.
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await _wait(8.0)
	if int(Server.entry.get("region", 0)) != 150:
		Server.command("/jump to 38900 46193 15604 150")
		await _wait(18.0)
		return                                             # (a new scene: its own probe carries on)
	await _wait(6.0)
	var sw: ServerWorld = v.npcs
	var mob: NpcState = null
	var names := {}
	for st in sw.by_oid.values():
		var s: NpcState = st
		if String(s.spawn.name).begins_with("animate"):
			names[String(s.spawn.name)] = int(names.get(String(s.spawn.name), 0)) + 1
			if s.view and (mob == null or s.pos.distance_to(v.player.global_position) < mob.pos.distance_to(v.player.global_position)):
				mob = s
	print("[weapon] animated weapons in view: ", names)
	var shown := 0
	for st in sw.by_oid.values():
		var s: NpcState = st
		if String(s.spawn.name).begins_with("animate") and shown < 4:
			shown += 1
			print("[weapon]   %s model %s at %.0f m view %s info %s equipment %s" % [s.spawn.name, s.spawn.get("model"),
					s.pos.distance_to(v.player.global_position), s.view != null, s.info.keys(),
					sw.data.get("equipment", {}).get(String(s.spawn.get("equipment", "")), [])])
	if mob == null:                                         # all beyond the view range: walk up to the nearest
		var near: NpcState = null
		for st in sw.by_oid.values():
			var s: NpcState = st
			if String(s.spawn.name).begins_with("animate svard") and (near == null or
					s.pos.distance_to(v.player.global_position) < near.pos.distance_to(v.player.global_position)):
				near = s
		if near:
			var d: Vector3 = near.pos - v.player.global_position
			d.y = 0.0
			v.player.global_position = near.pos - d.normalized() * 4.0 + Vector3(0, 0.5, 0)
			for _i in 30:
				await _wait(0.5)
				if near.view:
					break
			mob = near if near.view else null
	if mob == null:
		print("[weapon] still no view")
		get_tree().quit()
		return
	var n: Npc = mob.view
	var eq: Array = sw.data.get("equipment", {}).get(String(mob.spawn.get("equipment", "")), [])
	print("[weapon] %s at %.1f m: server equipment %s  weapons hung %d" % [mob.spawn.name,
			mob.pos.distance_to(v.player.global_position), eq, n._weapon_nodes.filter(func(w): return is_instance_valid(w)).size()])
	for w in n._weapon_nodes:
		if is_instance_valid(w):
			var meshes: Array = (w as Node).find_children("*", "MeshInstance3D", true, false)
			var mi: MeshInstance3D = meshes[0] if meshes.size() > 0 else null
			print("[weapon]   attach %s bone %s at %s (npc at %s)  meshes %d  first mesh at %s visible %s scale %s aabb %s" % [
					w.name, (w as BoneAttachment3D).bone_name if w is BoneAttachment3D else "-", (w as Node3D).global_position,
					n.global_position, meshes.size(), mi.global_position if mi else "-", mi.is_visible_in_tree() if mi else "-",
					mi.global_basis.get_scale() if mi else "-", mi.get_aabb().size if mi else "-"])
	var to: Vector3 = n.global_position - v.player.global_position
	to.y = 0.0
	v.player.global_position = n.global_position - to.normalized() * 3.0 + Vector3(0, 0.5, 0)
	v.player.face(atan2(-to.x, -to.z))
	await _wait(2.5)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://animate_weapon.png")
	get_tree().quit()


func _wait(sec: float) -> Signal:
	return get_tree().create_timer(sec).timeout
