extends Node
## Debug: patrols (PathID). Follows Darkness Falls patrollers for 20 s: point index, distance walked, height off floor.
##   --headless --skip-login --zone=249 --figure=cel_m --ui-test --probe=patrol_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var ps := []
	for s in viewer.npcs.states:
		if (s as NpcState).spawn.has("path"):
			ps.append(s)
	print("[patrol] ", ps.size(), " patrollers")
	var start := {}
	for p in ps:
		start[p] = (p as NpcState).pos
	var walked := {}
	var last := start.duplicate()
	for t in 20:
		await get_tree().create_timer(1.0).timeout
		for p in ps:
			walked[p] = float(walked.get(p, 0.0)) + (p as NpcState).pos.distance_to(last[p])
			last[p] = (p as NpcState).pos
	for p in ps.slice(0, 6):
		var st: NpcState = p
		print("[patrol] ", st.spawn.name, " type ", st.spawn.path.type, " points ", st.spawn.path.points.size(), " now at point ", st.path_i,
				" walked ", snappedf(float(walked[p]), 0.1), " m in 20 s, off floor ", snappedf(st.pos.y - viewer.npcs.ground_at(st.pos), 0.01), " running ", st.running)
	get_tree().quit()
