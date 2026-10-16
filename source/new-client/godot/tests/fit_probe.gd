extends Node
## Debug (headless): how many of a zone's NPCs stand on a floor (city / dungeon frame check), and where the rest are.
##   --headless --skip-login --zone=221 --figure=cel_m --ui-test --probe=fit_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var zone: ZoneLoader = viewer.zone
	var on := 0
	var off := []
	var dy := []
	for s in viewer.npcs.states:
		var st: NpcState = s
		var g := zone.height_at(st.pos.x, st.pos.z, st.pos.y + 0.5)
		if absf(g - st.pos.y) < 0.5:
			on += 1
		else:
			dy.append(snappedf(st.pos.y - g, 0.1))
			if off.size() < 6:
				off.append([st.spawn.name, snappedf(st.pos.y - g, 0.01)])
	dy.sort()
	print("[fit] zone ", zone.info.id, " ", zone.info.name, " city ", zone.city, " npcs ", viewer.npcs.states.size(), " on a floor ", on,
			" median off ", dy[dy.size() / 2] if not dy.is_empty() else 0.0, " off: ", off)
	get_tree().quit()
