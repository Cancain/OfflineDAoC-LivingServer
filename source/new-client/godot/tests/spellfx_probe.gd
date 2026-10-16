extends Node
## Debug: an Elf Magician casts Gleam Ray at a badger cub (as in the owner's old-client clip, 2026-10-10) - the casting
## clips, gather effects, the ray, the hit puff and the spell sounds (SpellFx). Windowed with --out=<folder>: a frame
## every 0.15 s from the cast start to after the hit (f_000.png ...), camera behind the caster like the clip.
##   --skip-login --zone=200 --figure=elf_m --ui-test --probe=spellfx_probe [--target=badger cub] [--out=...]
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.character["base"] = "ELF-MAGI"
	PlayerData.character.erase("class_id")
	PlayerData.level = 5
	PlayerData.recalc_max()
	PlayerData.set_power(PlayerData.max_power)
	var p: Player = v.player
	var want := String(v.args.get("target", "badger cub"))
	var mob: NpcState = null
	for s in v.npcs.states:
		if want in String((s as NpcState).spawn.name):
			mob = s
			break
	var at := mob.pos + Vector3(float(v.args.get("dist", "14")), 0, 0)
	at.y = v.zone.height_at(at.x, at.z) + 0.3
	p.global_position = at
	await get_tree().create_timer(2.0).timeout
	mob = v.npcs.states[v.npcs.states.find(mob)]
	v.npcs.target = mob.view
	PlayerData.set_target({"npc": mob.view})
	p.char_yaw = atan2(-(mob.pos.x - p.global_position.x), -(mob.pos.z - p.global_position.z))
	p.cam_yaw = p.char_yaw + (PI * 0.5 if v.args.has("side") else 0.0)
	p.cam_distance = float(v.args.get("cam", "4.5"))
	p.cam_pitch = -0.25
	v.ui.visible = false
	await get_tree().create_timer(0.5).timeout
	var sp := ClassDb.spell(4101)
	print("[fx] ", want, " size ", mob.spawn.get("size"), " fx scale ", SpellFx.size_of(mob.view), " gleam ray cast ", sp.get("casttime"))
	v.combat.casting._begin(sp)
	var out := String(v.args.get("out", ""))
	for i in 34:
		await get_tree().create_timer(0.15).timeout
		if out != "":
			get_viewport().get_texture().get_image().save_png(out + "/f_%03d.png" % i)
		if i == 4:
			print("[fx] casting: ", not v.combat.casting.casting.is_empty(), " clip ", p._anim.current_animation,
					" gather effects ", v.combat.casting._gather.size())
			for g in v.combat.casting._gather:
				for n in (g as Node).find_children("*", "GPUParticles3D", true, false):
					print("[fx]   gather sprite ", (n as GPUParticles3D).draw_pass_1.size, " world scale ", (n as Node3D).global_basis.get_scale().x)
	print("[fx] player sounds: ", p.sounds.play_log.filter(func(r): return String(r[0]).begins_with("spell")))
	get_tree().quit()
