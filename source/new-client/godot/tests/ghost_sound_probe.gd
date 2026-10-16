extends Node
## Debug, local (owner 2026-10-14: spirit pets lack their white glow; mylings in the ground; no combat sounds at all).
##   --screen 1 -- --skip-login --zone=200 "--at=Mag Mell" --figure=elf_m --ui-test --probe=ghost_sound_probe
## 1. voices: 60 sounds on an NPC whose view is then parked (disabled, as ServerWorld._park) - the voices come back and
##    new sounds still play; 2. the combat sound rows (swing, weapon hit, pain, death) asked of a player and an NPC;
## 3. the ghost look (Npc.ghost_look) on your figure and the myling (929) floating beside a 1 m post -
##    user://ghost_<n>.png.
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	v.ui.visible = false
	var p: Node3D = v.player
	var npc: Npc = null
	for k in v.npcs.active:
		var n: Npc = v.npcs.active[k]
		if n.sounds and (npc == null or n.global_position.distance_to(p.global_position) < npc.global_position.distance_to(p.global_position)):
			npc = n
	print("[gs] npc ", npc.name if npc else "-", " voices at start ", CharacterSounds._voice_ends.size())
	if npc:
		npc.global_position = p.global_position + p.global_basis.z * -3.0
		for i in 60:
			npc.sounds.event("pain_heavy")
		npc.process_mode = Node.PROCESS_MODE_DISABLED       # parked mid-sound (ServerWorld._park)
		print("[gs] after 60 sounds + parked: voices ", CharacterSounds._voice_ends.size())
		await get_tree().create_timer(4.0).timeout
		print("[gs] 4 s later: voices ", CharacterSounds._voice_ends.size(), "  players left on the npc ",
				npc.sounds.find_children("*", "AudioStreamPlayer3D", false, false).size())
		npc.process_mode = Node.PROCESS_MODE_INHERIT
	# the combat rows
	var psnd: CharacterSounds = p.get("sounds")
	for who in [["you", psnd], ["npc", npc.sounds if npc else null]]:
		var s: CharacterSounds = who[1]
		if s == null:
			print("[gs] ", who[0], ": no sounds")
			continue
		var before := s.play_log.size()
		s.weapon(1, "use")
		s.event("attack")
		s.weapon(1, "hit_medium")
		s.weapon(19, "hit_light")
		s.event("pain_light")
		s.event("pain_heavy")
		s.event("death")
		s.event("evade")
		await get_tree().create_timer(0.2).timeout
		print("[gs] ", who[0], " sounds played: ", s.play_log.slice(before))
	# the ghost look and the myling
	var spot := p.global_position
	var post := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 1.0, 0.05)
	post.mesh = bm
	p.get_parent().add_child(post)
	post.global_position = spot + p.global_basis.x * 1.2 + Vector3(0, 0.5, 0)
	var cam := Camera3D.new()
	p.get_parent().add_child(cam)
	cam.global_position = spot + p.global_basis.z * -4.5 + Vector3(0, 1.4, 0)
	cam.look_at(spot + Vector3(0, 1.1, 0), Vector3.UP)
	cam.current = true
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("user://ghost_0.png")
	Npc.ghost_look(p.get("_model"))
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("user://ghost_1.png")
	p.visible = false
	var mons = JSON.parse_string(FileAccess.get_file_as_string("res://content/monsters/monsters.json"))
	var info: Dictionary = mons["929"]
	var m := NpcManager._pack_model(String(info.gltf)).instantiate() as Node3D
	var holder := Node3D.new()
	p.get_parent().add_child(holder)
	holder.global_position = spot
	holder.add_child(m)
	m.scale *= float(info.get("scale", 1.0))
	var hover := Npc.figure_look(m, info, 7)
	m.position.y += hover
	var aps := m.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0 and (aps[0] as AnimationPlayer).has_animation("idle"):
		(aps[0] as AnimationPlayer).play("idle")
	var aabb := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	print("[gs] myling (929 %s): hover %.2f m, mesh from %.2f to %.2f m over the ground" % [info.name, hover,
			aabb.position.y - spot.y, aabb.end.y - spot.y])
	await get_tree().create_timer(0.8).timeout
	get_viewport().get_texture().get_image().save_png("user://ghost_2.png")
	get_tree().quit()
