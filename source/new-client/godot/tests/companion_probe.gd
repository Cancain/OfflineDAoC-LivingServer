extends Node
## Debug (bot plan phase 6): the companion system end to end at Shannon Estuary's roadside inn - the level-5 courier
## quest, the innkeeper's window, hiring (free, then the next costs), the companion at your side following you,
## fighting with you (aggressive), sharing a kill's experience, gear handed over (class rules), training, tactics,
## stances, its death and the healer bringing it back, dismiss / summon, release. Pictures into --out.
##   --screen 1 --skip-login --zone=202 --figure=cel_m --ui-test --probe=companion_probe --out=<folder>
var v: Node
var out := "user://companion_probe"


func shot(name: String) -> void:
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join(name + ".png"))


func _ready() -> void:
	v = get_tree().current_scene
	out = String(v.args.get("out", out))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(6.0).timeout
	var p: Player = v.player
	var comps: Companions = v.companions
	var lines := []
	PlayerData.message.connect(func(t, _k): lines.append(t))
	var inn: Dictionary = comps.inns.hib
	print("[comp] GameBots: ", WorldLink.bots != null)
	# level 5: the courier quest arrives whatever happens
	PlayerData.gain_xp(CombatRules.xp_for_level(6) - PlayerData.xp, false)
	await get_tree().create_timer(1.0).timeout
	print("[comp] level %d, quest 90001: %s, courier flag %s" % [PlayerData.level, PlayerData.quests.get("90001"), PlayerData.character.get("companion_courier")])
	await get_tree().create_timer(5.0).timeout
	await shot("01_courier")
	# to the inn: the arrival spot by the door
	p.global_position = Vector3(float(inn.arrive[0]), float(inn.arrive[1]) + 0.5, float(inn.arrive[2]))
	await get_tree().create_timer(2.0).timeout
	var keeper: Npc = null
	for k in v.npcs.active:
		var n: Npc = v.npcs.active[k]
		if is_instance_valid(n) and String(n.spawn.name) == String(inn.innkeeper):
			keeper = n
	print("[comp] innkeeper view: ", keeper != null)
	if keeper:
		p.global_position = keeper.global_position + Vector3(1.5, 0.3, 0)
		await get_tree().create_timer(0.5).timeout
		v.npcs.select(keeper)
		v.npcs.interact(keeper)
		await get_tree().create_timer(1.0).timeout
		print("[comp] quest after talking: ", PlayerData.quests.get("90001"))
		var iw: InnkeeperWindow = v.ui.windows["innkeeper"]
		print("[comp] innkeeper window open: ", iw.visible)
		iw.show_page(1)
		await shot("02_hire_page")
	# hire: a Hero (first is free)
	var classes := Companions.classes_for("hib", 0)
	print("[comp] Celt classes: ", classes.map(func(c): return c.name))
	var hero := 0
	for c in classes:
		if String(c.name) == "Hero":
			hero = int(c.id)
	var ok := comps.hire(0, 0, hero, "Probehero", CharacterFactory.random_look("cel_m", RandomNumberGenerator.new()), String(inn.innkeeper))
	print("[comp] hired: %s, roster %d, quest done %s, next cost %s" % [ok, Companions.roster().size(), PlayerData.quests_done.get("90001"), comps.hire_cost()])
	print("[comp] second hire problem: ", comps.hire_problem())
	var rec: Dictionary = Companions.roster()[0] if ok else {}
	var cid := int(Companions.info(rec).get("id", -1))
	await get_tree().create_timer(1.5).timeout
	var f = comps.foe(cid)
	if f == null:
		print("[comp] NOT IN THE WORLD - stopping")
		get_tree().quit()
		return
	print("[comp] in the world: %s, weapon %s, level %s, hp %s" % [f != null, rec.get("inventory"), f.call("level") if f else -1, (f.get("sheet") as CharacterState).hp if f else -1])
	print("[comp] group rows: ", PlayerData.group.map(func(m): return "%s L%d %d%%" % [m.name, m.level, int(m.hp * 100)]))
	await shot("03_hired")
	# walk: it follows (you step out of the inn and 15 m along)
	p.global_position = Vector3(float(inn.yard[0]), float(inn.yard[1]) + 0.5, float(inn.yard[2]))
	await get_tree().create_timer(4.0).timeout
	var start := p.global_position
	p.global_position += Vector3(12, 0, 8)
	p.global_position.y = v.zone.height_at(p.global_position.x, p.global_position.z) + 0.3
	await get_tree().create_timer(6.0).timeout
	var cp: Vector3 = WorldLink.bots.call("CompanionPos", cid)
	print("[comp] you moved %.1f m; companion %.1f m from you" % [p.global_position.distance_to(start), cp.distance_to(p.global_position)])
	await shot("04_following")
	# gear: a cloth cap is fine for a Hero; give it the player's starting shield
	var shield_slot := -1
	for s in PlayerData.inventory:
		if int(ItemDb.item(String(PlayerData.inventory[s].id)).get("object_type", 0)) == 42:
			shield_slot = int(s)
	if shield_slot >= 0:
		comps.give_item(cid, shield_slot, 11)
		print("[comp] shield handed over: ", (f.get("sheet") as CharacterState).item_at(11).get("name", "none"))
	# training, tactics, stance
	var sh: CharacterState = f.get("sheet")
	print("[comp] spec points %d, specs %s" % [sh.spec_points(), sh.specs])
	for key in sh.specs.keys():
		comps.train(cid, String(key))
		break
	var styles := ClassDb.styles_known(sh.class_id(), sh.specs)
	if not styles.is_empty():
		comps.add_tactic(cid, {"kind": "style", "id": int(styles[0].id), "name": String(styles[0].name)})
	print("[comp] tactics: ", Companions.info(rec).get("tactics"))
	comps.set_stance(cid, "aggressive")
	var cw: CompanionWindow = v.ui.windows["companion"]
	comps.manage(cid)
	await shot("05_window_gear")
	cw.show_page(2)
	await shot("06_window_tactics")
	cw.show_page(3)
	await shot("07_window_stance")
	cw.hide_window()
	# a fight: the nearest monster, attack mode on - the companion assists
	var mob: NpcState = null
	var bd := 1e9
	for s in v.npcs.states:
		var st: NpcState = s
		if st.alive and int(st.spawn.realm) == 0 and st.level <= PlayerData.level + 1 and st.pos.distance_to(p.global_position) < bd:
			bd = st.pos.distance_to(p.global_position)
			mob = st
	if mob:
		p.global_position = mob.pos + Vector3(2.0, 0.5, 0)
		await get_tree().create_timer(1.0).timeout
		for k in v.npcs.active:
			if v.npcs.active[k].state == mob:
				v.npcs.select(v.npcs.active[k])
		v.combat.set_attack_mode(true)
		var t0 := Time.get_ticks_msec()
		while mob.alive and Time.get_ticks_msec() - t0 < 30000:
			await get_tree().create_timer(0.5).timeout
		print("[comp] fight: %s (level %d) dead %s after %.1f s; companion events: %s" % [mob.spawn.name, mob.level, not mob.alive, (Time.get_ticks_msec() - t0) / 1000.0, lines.filter(func(l): return "experience" in l or "Probehero" in l).slice(-6)])
		await shot("08_fight")
	# death and the healer
	sh.set_hp(0)
	f.set("alive", false)
	await get_tree().create_timer(1.2).timeout
	print("[comp] after death: state %s" % Companions.info(rec).get("state"))
	PlayerData.set_copper(PlayerData.total_copper() + 100000)
	var revived := comps.revive(cid, String(inn.healer))
	await get_tree().create_timer(1.0).timeout
	print("[comp] revived: %s, state %s" % [revived, Companions.info(rec).get("state")])
	comps.dismiss(cid)
	print("[comp] dismissed: state %s, in world %s" % [Companions.info(rec).get("state"), comps.foe(cid) != null])
	comps.summon(cid)
	await get_tree().create_timer(1.0).timeout
	print("[comp] summoned: state %s, in world %s" % [Companions.info(rec).get("state"), comps.foe(cid) != null])
	await shot("09_summoned")
	print("[comp] chat tail:\n  " + "\n  ".join(lines.slice(-14)))
	get_tree().quit()
