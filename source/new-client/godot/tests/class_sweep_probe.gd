extends Node
## Debug (headless): every advanced class at level 50 with every spec at 50 lands every spell of its lines once
## (straight through Casting's landing path, no cast times) on a tough monster / itself / its pet, and the sweep reports
## the spells that did nothing visible (no message other than the "You cast a X Spell!" fallback, no effect, no damage)
## and any script error. Pets are summoned first for classes that have them.
##   --headless --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=class_sweep_probe [--class=Druid]
var viewer: Node
var _msgs: Array = []


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.message.connect(func(t, _k): _msgs.append(String(t)))
	var combat: Combat = viewer.combat
	var cast: Casting = combat.casting
	var pets: Pets = combat.pets
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and st.level >= 10 and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	viewer.player.global_position = mob.pos + Vector3(10, 0.3, 0)
	await get_tree().create_timer(2.0).timeout
	var only := String(viewer.args.get("class", ""))
	var silent_by_type := {}
	var total := 0
	var silent := 0
	for k in ClassDb._classes:
		var c: Dictionary = ClassDb._classes[k]
		if bool(c.get("is_base", false)) or (only != "" and String(c.name) != only):
			continue
		PlayerData.level = 50
		PlayerData.character["class_id"] = int(c.id)
		PlayerData.specs = {}
		for e in ClassDb.trainable_specs(int(c.id), 50):
			PlayerData.specs[String(e.spec)] = 50
		PlayerData.recalc_max()
		pets.release_all()
		var spells := []
		for line in ClassDb.spell_lines(int(c.id), 50, PlayerData.specs):
			for sid in line.spells:
				spells.append(int(sid))
		# a pet first, for the classes with summons (the strongest one)
		for sid in spells:
			var sp := ClassDb.spell(sid)
			if String(sp.get("type", "")) in Pets.CONTROLLED and pets.pet == null:
				cast.ground_target = mob.pos + Vector3(4, 0, 0)
				pets.summon(sp, null)
		var c_silent := []
		for sid in spells:
			var sp := ClassDb.spell(sid)
			if sp.is_empty():
				continue
			mob.alive = true
			mob.max_hp = 1000000
			mob.hp = 1000000
			mob.spawn["realm"] = 0
			PlayerData.set_hp(PlayerData.max_hp)
			PlayerData.set_power(PlayerData.max_power)
			if mob.view:
				viewer.npcs.select(mob.view)
			var t := String(sp.get("target", "Enemy"))
			var kind := String(sp.get("type", ""))
			if kind.begins_with("Summon") or kind == "Charm":
				continue                                          # pets have their own probes
			_msgs.clear()
			var n_eff := cast.effects.size()
			var hp0 := mob.hp
			var php0 := PlayerData.hp
			var mode := ""
			var target: Variant = null
			if t == "Area":
				cast.ground_target = mob.pos
				mode = "area"
			elif t == "Pet":
				if pets.pet == null:
					continue
				mode = "pet"
			elif t == "Enemy":
				target = mob
				if int(sp.get("range", 0)) <= 0:
					mode = "pbaoe"
					viewer.player.global_position = mob.pos + Vector3(1.5, 0.3, 0)
			elif t in ["Corpse"]:
				continue
			cast._apply_spell(sp, mode, target)
			viewer.player.global_position = mob.pos + Vector3(10, 0.3, 0)
			cast.stop_pulse()
			total += 1
			var did := cast.effects.size() != n_eff or mob.hp != hp0 or PlayerData.hp != php0
			var said := _msgs.filter(func(m): return not String(m).begins_with("You cast a ")).size() > 0
			if not did and not said:
				silent += 1
				c_silent.append("%s(%s)" % [sp.get("name", "?"), kind])
				silent_by_type[kind] = int(silent_by_type.get(kind, 0)) + 1
			# clear lasting effects so the next spell starts clean
			for e in cast.effects:
				e.until = 0.0
			await get_tree().process_frame
		print("[sweep] ", c.name, ": ", spells.size(), " spells, silent ", c_silent.size(), " ", c_silent.slice(0, 12))
	print("[sweep] TOTAL ", total, " landed, silent ", silent, " by type ", silent_by_type)
	get_tree().quit()
