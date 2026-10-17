extends Node
## Debug: monsters' ambient lines (MobXAmbientBehaviour). Fires each trigger of a few Lough Derg monsters 40 times
## with the player beside them and prints what the chat got.
##   --headless --skip-login --zone=200 --figure=cel_m --ui-test --probe=ambient_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var lines := {}
	PlayerData.message.connect(func(t, k): lines[str(k) + ": " + str(t)] = int(lines.get(str(k) + ": " + str(t), 0)) + 1)
	var amb: Dictionary = viewer.npcs.data.get("ambient", {})
	print("[ambient] names with lines here: ", amb.keys())
	for name in amb.keys():
		var st: NpcState = null
		for s in viewer.npcs.states:
			if String((s as NpcState).spawn.name).to_lower() == name:
				st = s
				break
		if st == null:
			continue
		var at := st.pos + Vector3(2, 0, 0)
		at.y = viewer.zone.height_at(at.x, at.z) + 0.3
		viewer.player.global_position = at
		for a in amb[name]:
			for i in 40:
				viewer.npcs.ambient(st, String(a.trigger), PlayerData.display_name(), true)
	for k in lines.keys():
		print("[ambient] x", lines[k], " ", k)
	get_tree().quit()
