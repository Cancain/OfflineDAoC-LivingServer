extends Node
## Debug: a fresh level 1 Celt Guardian (starter sword) hitting an annoying lucradan (L0) - damage per blow and how many
## blows to kill (owner's old-client log: 7, 8, 5 -> dead).
##   --headless --skip-login --zone=200 --figure=cel_m --ui-test --probe=guardian_dmg_probe
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var combat = v.combat
	PlayerData.message.connect(func(t, _k):
		if "hit for" in t or "dies" in t or "miss" in t: print("[dmg] ", t))
	print("[dmg] weapon ", PlayerData.item_at(10).get("name", ""), " dps ", PlayerData.item_at(10).get("dps_af", ""), " spd ", PlayerData.item_at(10).get("spd_abs", ""), " specs ", PlayerData.specs)
	var luc: NpcState = null
	for s in v.npcs.states:
		if String((s as NpcState).spawn.name) == "annoying lucradan" and (s as NpcState).alive:
			luc = s
			break
	print("[dmg] lucradan level ", luc.level, " hp ", luc.max_hp, " stats ", luc.stats)
	var hits := []
	for i in 40:
		var st: NpcState = luc
		st.hp = st.max_hp
		st.alive = true
		st.health = 1.0
		combat._player_blow(st, {})
	get_tree().quit()
