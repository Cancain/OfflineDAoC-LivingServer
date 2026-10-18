extends Node
## Debug, local (owner 2026-10-16: terror birds / low giant cicadas sunk halfway into the ground, cold lights not
## hovering): each of --models=<model,...> spawned next to you with no gear, pictures from the front and the side.
## Runs once (60 s cap).
##   --screen 1 --skip-login --zone=100 --figure=nor_m --probe=monster_height_probe --models=846,824,118,912 [--flags=1] --out=<folder>
var v: Node
const EQUIP := []


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	var out := String(v.args.get("out", "user://spirit_champion"))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(8.0).timeout
	v.ui.visible = false
	if v.hud:
		v.hud.visible = false
	var p: Player = v.player
	p.hold()
	p.visible = v.args.has("show_player")          # (hidden: it stood in the side picture)
	var all_eq: Dictionary = v.npcs.data.get("equipment", {})
	all_eq["probe_spirit"] = EQUIP
	v.npcs.data["equipment"] = all_eq
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	var fwd := Vector3(sin(p.char_yaw), 0, cos(p.char_yaw))
	var at := p.global_position + fwd * 3.0
	for ms in String(v.args.get("models", "145")).split(","):
		var s := {"id": "probe_spirit_" + ms, "name": "height test", "guild": "", "level": 40, "realm": 2, "role": "pet",
				"trains": null, "class_type": "pet", "model": ms, "size": 50, "gender": 0, "pos": [at.x, at.y, at.z],
				"heading": 0, "aggro_level": 0, "aggro_range": 0, "roam": 0, "flags": int(v.args.get("flags", "0")), "speed": 200,
				"items": "", "equipment": "probe_spirit", "faction": 0, "body_type": 11, "template": 0, "stats": [0, 0, 0, 0],
				"damage_type": 1, "race": 2009, "respawn": 0, "defense": [0, 0, 0, 0], "spells": [], "spell_scale": 1.0,
				"martial": 1.0, "abilities": [], "levels": [40], "models": [int(ms)], "sizes": [50], "tether": 0, "styles": []}
		var st: NpcState = v.npcs.add_spawn(s)
		st.wait = 1e9
		await get_tree().create_timer(2.5).timeout
		print("[spirit] ", ms, " view ", st.view != null)
		var face := Vector3(sin(st.yaw), 0, cos(st.yaw))
		for view in [["front", face], ["side", face.rotated(Vector3.UP, PI * 0.5)]]:
			cam.global_position = st.pos + (view[1] as Vector3) * float(v.args.get("dist", "5.0")) + Vector3(0, 0.6, 0)
			cam.look_at(st.pos + Vector3(0, 0.7, 0))
			await get_tree().create_timer(0.4).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("spirit_%s_%s.png" % [ms, view[0]]))
		v.npcs.remove_spawn(st)
		await get_tree().create_timer(0.5).timeout
	get_tree().quit()
