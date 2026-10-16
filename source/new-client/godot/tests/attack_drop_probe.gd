extends Node
## Debug (owner 2026-10-10, tested on the old client: attack mode drops by itself when your target dies): target the
## nearest monster, enter attack mode, kill it by a blow and (second round) by something else, check attack mode.
##   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --probe=attack_drop_probe
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var combat: Combat = v.combat
	PlayerData.inventory[10] = {"id": "practice_sword"}
	PlayerData.active_weapon = "standard"
	for how in ["your blow", "someone else"]:
		var mob: Npc = null
		for i in v.npcs.active:
			var n: Npc = v.npcs.active[i]
			if is_instance_valid(n) and n.state.alive and int(n.spawn.realm) == 0 and (mob == null
					or n.global_position.distance_to(v.player.global_position) < mob.global_position.distance_to(v.player.global_position)):
				mob = n
		v.npcs.select(mob)
		combat.set_attack_mode(true)
		await get_tree().process_frame
		var before: bool = combat.attack_mode
		if how == "your blow":
			mob.state.hp = 1
			combat._player_blow(mob.state, {})
			for k in 5:
				if mob.state.alive:
					combat._player_blow(mob.state, {})
		else:
			mob.state.hp = 0
			mob.state.die()
		for f in 3:
			await get_tree().process_frame
		print("[attack] killed by %s: attack mode before %s, target dead %s, attack mode after %s" % [how, before,
				not mob.state.alive, combat.attack_mode])
	get_tree().quit()
