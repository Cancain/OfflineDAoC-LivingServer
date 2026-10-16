extends Node
## Debug (owner 2026-10-10: "make sure attack styles are in and working and act on next auto attack and their
## triggers and combos work"): an Armsman 20 with a sword on a tough monster -
##  1. Opal Slash (follows Uppercut) refused before Uppercut has landed; Uppercut queued -> used on the NEXT swing,
##     not at once; then Opal Slash accepted and landing;
##  2. positionals: Back Slash only from behind, Cross Slash only from the side.
##   --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=player_style_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var chat: Array = []
	PlayerData.message.connect(func(t, _k): chat.append(String(t)))
	var combat: Combat = viewer.combat
	PlayerData.level = 20
	PlayerData.specs["Slash"] = 20
	PlayerData.inventory[10] = {"id": "practice_sword"}      # a slashing sword in the right hand (object type 3)
	PlayerData.active_weapon = "standard"
	print("[pstyle] weapon: ", combat._weapon().get("name"), " object_type ", combat._weapon().get("object_type"))
	var mob: NpcState = null
	for s in viewer.npcs.states:
		var st: NpcState = s
		if int(st.spawn.realm) == 0 and st.alive and (mob == null or st.pos.distance_to(viewer.player.global_position) < mob.pos.distance_to(viewer.player.global_position)):
			mob = st
	mob.max_hp = 100000
	mob.hp = 100000
	mob.spawn["defense"] = [0, 0, 0, 0]
	var upper := ClassDb.style_by_game_id(58, 1)
	var opal := ClassDb.style_by_game_id(62, 1)
	var back := ClassDb.style_by_game_id(68, 1)
	var cross := ClassDb.style_by_game_id(57, 1)
	print("[pstyle] styles: ", upper.get("name"), " / ", opal.get("name"), " / ", back.get("name"), " / ", cross.get("name"))
	# 1. the chain
	combat.last_result = "hit"
	combat.last_style_id = 0
	print("[pstyle] Opal Slash allowed before Uppercut? ", combat._style_ok(opal, mob))
	var landed := false
	for i in 30:
		combat._player_blow(mob, upper)
		if combat.last_result == "style" and combat.last_style_id == 58:
			landed = true
			break
	print("[pstyle] Uppercut landed: ", landed, "  last_style_id ", combat.last_style_id)
	print("[pstyle] Opal Slash allowed right after Uppercut? ", combat._style_ok(opal, mob))
	combat._player_blow(mob, opal)
	print("[pstyle] Opal Slash result: ", combat.last_result, " id ", combat.last_style_id, "  chat: ", chat.slice(-2))
	# next swing: queue through the quickbar path, then watch the swing timer use it
	viewer.player.global_position = mob.pos + Vector3(1.2, 0.0, 0)
	viewer.npcs.select(mob.view) if mob.view else null
	combat.last_result = "hit"
	chat.clear()
	var to0: Vector3 = mob.pos - viewer.player.global_position
	viewer.player.face(atan2(-to0.x, -to0.z))
	await get_tree().process_frame
	PlayerData.use_skill.emit({"kind": "style", "id": int(upper.get("styleid", 0))})
	print("[pstyle] queued: next_style=", combat.next_style.get("name", "-"), "  same frame last_style_id=", combat.last_style_id, "  chat: ", chat)
	var t0 := Time.get_ticks_msec()
	while not combat.next_style.is_empty() and Time.get_ticks_msec() - t0 < 8000:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	print("[pstyle] used after %.1f s (on the next swing): last_result=%s id=%s  chat: %s" % [(Time.get_ticks_msec() - t0) / 1000.0,
			combat.last_result, combat.last_style_id, chat.slice(0, 4)])
	combat.set_attack_mode(false)
	# 2. positionals: the monster faces +Z; stand behind, beside and in front
	mob.yaw = 0.0
	var spots := {"behind": Vector3(0, 0, -1.2), "side": Vector3(1.2, 0, 0), "front": Vector3(0, 0, 1.2)}
	for k in spots:
		viewer.player.global_position = mob.pos + spots[k]
		var to: Vector3 = mob.pos - viewer.player.global_position
		viewer.player.face(atan2(-to.x, -to.z))
		await get_tree().process_frame
		print("[pstyle] from %-6s Back Slash ok=%s  Cross Slash ok=%s" % [k, combat._style_ok(back, mob), combat._style_ok(cross, mob)])
	get_tree().quit()
