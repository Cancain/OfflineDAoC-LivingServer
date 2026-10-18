extends Node
## Debug, local (owner 2026-10-17: the mantid stable master and its neighbours float): each of --models=<model,...>
## spawned on flat ground, and once its idle plays, how far its lowest foot / toe / leg bone is above (+) or below (-)
## the ground under it - a model drawn standing right is near 0. Runs once (90 s cap), prints only.
##   --skip-login --zone=100 --figure=nor_m --probe=feet_probe --models=684,647,413,846
var v: Node


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	await get_tree().create_timer(8.0).timeout
	var p: Player = v.player
	p.hold()
	var fwd := Vector3(sin(p.char_yaw), 0, cos(p.char_yaw))
	var at := p.global_position + fwd * 4.0
	at.y = v.zone.height_at(at.x, at.z)
	for ms in String(v.args.get("models", "684")).split(","):
		var s := {"id": "feet_" + ms, "name": "feet test", "guild": "", "level": 10, "realm": 0, "role": "", "trains": null,
				"class_type": "", "model": ms, "size": 50, "gender": 0, "pos": [at.x, at.y, at.z], "heading": 0,
				"aggro_level": 0, "aggro_range": 0, "roam": 0, "flags": 0, "speed": 200, "items": "", "equipment": "",
				"faction": 0, "body_type": 0, "template": 0, "stats": [0, 0, 0, 0], "damage_type": 1, "race": 0,
				"respawn": 0, "defense": [0, 0, 0, 0], "spells": [], "spell_scale": 1.0, "martial": 1.0, "abilities": [],
				"levels": [10], "models": [int(ms)], "sizes": [50], "tether": 0, "styles": []}
		var st: NpcState = v.npcs.add_spawn(s)
		st.wait = 1e9
		await get_tree().create_timer(2.5).timeout
		var view := st.view as Npc
		if view == null or view.model == null:
			print("[feet] ", ms, " no view")
			continue
		var low := INF
		var lowb := ""
		var anyb := INF
		for sk in view.model.find_children("*", "Skeleton3D", true, false):
			var skel := sk as Skeleton3D
			for i in skel.get_bone_count():
				var y := (skel.global_transform * skel.get_bone_global_pose(i)).origin.y
				anyb = minf(anyb, y)
				var n := skel.get_bone_name(i).to_lower()
				if ("foot" in n or "toe" in n or "leg" in n or "calf" in n) and y < low:
					low = y
					lowb = skel.get_bone_name(i)
		var ground := view.global_position.y
		print("[feet] %s %s: lowest leg bone %s %+.2f m from the ground, lowest bone %+.2f m (model lifted %.2f)" % [
				ms, String(st.info.get("name", "")), lowb, low - ground, anyb - ground, view.model.position.y])
		v.npcs.remove_spawn(st)
		await get_tree().create_timer(0.3).timeout
	get_tree().quit()
