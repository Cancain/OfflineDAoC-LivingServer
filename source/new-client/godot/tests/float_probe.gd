extends Node
## Debug (owner 2026-10-13: the shade opaque and too low, mylings not floating): you morph into the necromancer's
## shade (monsters.json 822); then the Ghost (902 - mylings), a Skeleton (25, cut-out) and a Pixie (603) one at a time
## where you stand, drawn the way the NPC views draw them (Npc.figure_look: skin alpha + hover), playing their idle.
## A 1 m post marks the ground beside each. Screenshots user://float_<model>.png.
##   --screen 1 -- --skip-login --zone=200 "--at=Mag Mell" --figure=elf_m --ui-test --probe=float_probe
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	v.ui.visible = false
	var mons = JSON.parse_string(FileAccess.get_file_as_string("res://content/monsters/monsters.json"))
	var p: Node3D = v.player
	var spot := p.global_position
	var post := MeshInstance3D.new()                       # 1 m tall, 0.6 m to the side: the ground and a metre
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 1.0, 0.05)
	post.mesh = bm
	p.get_parent().add_child(post)
	post.global_position = spot + p.global_basis.x * 0.9 + Vector3(0, 0.5, 0)
	var cam := Camera3D.new()
	p.get_parent().add_child(cam)
	cam.global_position = spot + p.global_basis.z * -4.5 + Vector3(0, 1.3, 0)
	cam.look_at(spot + Vector3(0, 1.1, 0), Vector3.UP)
	cam.current = true
	p.morph(mons["822"])
	await get_tree().create_timer(1.0).timeout
	var mm: Node3D = p.get("_morph")
	if mm:
		for mi in mm.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			var mat := g.mesh.surface_get_material(0) as BaseMaterial3D if g.mesh else null
			print("[float] shade mesh ", g.name, " visible ", g.is_visible_in_tree(), " aabb ", g.global_transform * g.get_aabb(),
					" transp ", mat.transparency if mat else -1, " tex ", mat.albedo_texture if mat else null)
		print("[float] shade at ", mm.global_position, " player ", p.global_position, " scale ", mm.scale)
	get_viewport().get_texture().get_image().save_png("user://float_shade.png")
	p.morph({})
	p.visible = false
	for id in ["902", "25", "603"]:
		var info: Dictionary = mons[id]
		var m := NpcManager._pack_model(String(info.gltf)).instantiate() as Node3D
		var holder := Node3D.new()
		p.get_parent().add_child(holder)
		holder.global_position = spot
		holder.rotation.y = p.rotation.y
		holder.add_child(m)
		m.scale *= float(info.get("scale", 1.0))
		var hover := Npc.figure_look(m, info, 7)
		m.position.y += hover
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		if aps.size() > 0 and (aps[0] as AnimationPlayer).has_animation("idle"):
			(aps[0] as AnimationPlayer).play("idle")
		print("[float] ", info.name, " hover ", snappedf(hover, 0.01), " m, alpha ", info.get("alpha", ""))
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png("user://float_%s.png" % id)
		holder.queue_free()
	get_tree().quit()
