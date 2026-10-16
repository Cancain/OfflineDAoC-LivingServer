extends Node
## Debug, local (owner 2026-10-15: the Bonedancer sub pets - bonehealer, bone diviner - "just glow their hands and stand
## there"; bone archers swing a sword at range): spawns the pet templates (--tids, default bonehealer 74, bone diviner
## 57, bone archer 79), casts on each as the server's SpellCastAnimation would, and logs the clip playing and how far the
## hand bones move. Runs once, quits (hard stop 40 s).
##   --skip-login --zone=200 "--at=Mag Mell" --figure=elf_m --ui-test --probe=subpet_cast_probe
var viewer: Node


func _ready() -> void:
	if get_tree().root.has_meta("subpet_cast_ran"):
		return
	get_tree().root.set_meta("subpet_cast_ran", true)
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit())
	viewer = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var pets: Pets = viewer.combat.pets
	var ids := String(viewer.args.get("tids", "74,57,79")).split(",")
	var base: Vector3 = viewer.player.global_position + Vector3(0, 0, -5)
	var made := []
	for i in ids.size():
		var t := Pets.template(int(ids[i]))
		var at := base + Vector3((i - 1) * 2.5, 0, 0)
		at.y = viewer.npcs.ground_at(at)
		made.append(pets._make(t, 40, at, {}))
	for w in 30:                                                    # their views are made in the background
		if made.all(func(s): return s.view != null):
			break
		await get_tree().create_timer(0.5).timeout
	await get_tree().create_timer(1.0).timeout
	for st in made:
		var n: Npc = st.view
		if n == null:
			print("[sub] %s: no view" % st.spawn.name)
			continue
		var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0] if not n.find_children("*", "Skeleton3D", true, false).is_empty() else null
		var hand := sk.find_bone("Bip01 R Hand") if sk else -1
		var before: Vector3 = sk.get_bone_global_pose(hand).origin if hand >= 0 else Vector3.ZERO
		n.cast_start(["cast_upraised_start", "cast_upraised_mid", "cast_upraised_end"], 2.5)
		var log := []
		for k in 6:
			await get_tree().create_timer(0.3).timeout
			var p: Vector3 = sk.get_bone_global_pose(hand).origin if hand >= 0 else Vector3.ZERO
			log.append("%s %.2f moved %.3f" % [n.anim.current_animation if n.anim else "-", n.anim.current_animation_position if n.anim and n.anim.current_animation != "" else -1.0, p.distance_to(before)])
		print("[sub] %s model %s: anim %s, skeleton %s, hand bone %d, clips %s" % [st.spawn.name, st.spawn.model, n.anim != null, sk != null, hand,
				n.info.get("cast_clips", {}).get("cast_upraised_start", "?")])
		print("[sub]   ", " | ".join(log))
		print("[sub]   weapons: slots %s, stance '%s', has bow clips: %s" % [n.get("_weapon_slots"), n.combat_stance,
				n.anim.has_animation("bow_fire") if n.anim else false])
	var archer: Npc = made[2].view if made.size() > 2 else null
	if archer:
		archer.state.fighting = true
		archer.state.mode = NpcState.Mode.FIGHT
		archer.set_weapon_slots(0x33)
		await get_tree().create_timer(0.3).timeout
		archer.bow_draw()
		var seen := []
		for k in 8:
			await get_tree().create_timer(0.25).timeout
			seen.append(archer.anim.current_animation)
		archer.bow_release()
		await get_tree().create_timer(0.2).timeout
		seen.append(archer.anim.current_animation)
		print("[sub] archer stance '%s', draw -> %s" % [archer.combat_stance, " ".join(seen)])
	get_tree().quit()
