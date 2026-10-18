extends Node
## Debug, local (owner 2026-10-17: ghost NPCs - a frost spectre, the ice giant model 1384 with the GHOST flag - still
## flicker in the game's light): the ghost spawned --dist m away (default 15), the camera still; its screen box's
## brightness frame by frame - a steady ghost changes a little with its idle, a flickering one jumps up and down.
## Variants change one suspect each. Runs once (120 s cap).
##   --screen 1 --skip-login --zone=100 --figure=nor_m --probe=ghost_flicker_probe [--model=1384] [--dist=15] [--hour=0]
##   [--storm] [--torch]
var v: Node
const FRAMES := 60


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	await get_tree().create_timer(8.0).timeout
	v.ui.visible = false
	if v.hud:
		v.hud.visible = false
	var p: Player = v.player
	p.hold()
	p.visible = false
	if v.args.has("hour"):                                    # --hour=0: night, --storm: snow / rain, --torch: lit
		v.sky.game_seconds = float(v.args.hour) * 3600.0
	v.sky.time_scale = 0.0
	if v.args.has("storm"):
		v.sky.storm_forced = 1.0
		v.sky.storm = 1.0
	if v.args.has("torch"):
		p.set_torch(true)
	var ms := String(v.args.get("model", "1384"))
	var dist := float(v.args.get("dist", "15"))
	var fwd := Vector3(sin(p.char_yaw), 0, cos(p.char_yaw))
	var at := p.global_position + fwd * dist
	at.y = v.zone.height_at(at.x, at.z)                       # (both on the ground: a --pos start can be under it)
	var eye := p.global_position
	eye.y = v.zone.height_at(eye.x, eye.z) + 2.0
	var s := {"id": "probe_ghost", "name": "ghost test", "guild": "", "level": 40, "realm": 0, "role": "", "trains": null,
			"class_type": "", "model": ms, "size": 50, "gender": 0, "pos": [at.x, at.y, at.z], "heading": 0,
			"aggro_level": 0, "aggro_range": 0, "roam": 0, "flags": Npc.FLAG_GHOST, "speed": 200, "items": "",
			"equipment": "", "faction": 0, "body_type": 0, "template": 0, "stats": [0, 0, 0, 0], "damage_type": 1,
			"race": 0, "respawn": 0, "defense": [0, 0, 0, 0], "spells": [], "spell_scale": 1.0, "martial": 1.0,
			"abilities": [], "levels": [40], "models": [int(ms)], "sizes": [50], "tether": 0, "styles": []}
	var st: NpcState = v.npcs.add_spawn(s)
	st.wait = 1e9
	# --crowd=<n>: n more of them around it, wandering (owner 2026-10-17 clips: a dozen frost spectres walking about a
	# keep, overlapping - the flicker shows there, one standing ghost never did)
	for k in int(v.args.get("crowd", "0")):
		var s2 := s.duplicate(true)
		s2["id"] = "probe_ghost_%d" % k
		var off := Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		var q := at + off
		q.y = v.zone.height_at(q.x, q.z)
		s2["pos"] = [q.x, q.y, q.z]
		s2["roam"] = 400
		var st2: NpcState = v.npcs.add_spawn(s2)
		st2.wait = randf_range(0.0, 1.0)
	await get_tree().create_timer(3.0).timeout
	var view := st.view as Npc
	print("[ghost] view ", view != null, " height ", view.height if view else 0.0)
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.global_position = eye
	cam.look_at(at + Vector3(0, view.height * 0.5 if view else 1.5, 0))
	await get_tree().create_timer(0.5).timeout
	var variants := [
		["as is", func(): pass],
		["no glow overlay", func():
			for mi in view.find_children("*", "MeshInstance3D", true, false):
				(mi as MeshInstance3D).material_overlay = null],
		["no AnimLod (anim off)", func():
			if view.anim:
				view.anim.pause()],
	]
	for var_ in variants:
		(var_[1] as Callable).call()
		await get_tree().create_timer(0.3).timeout
		var vals := PackedFloat32Array()
		var r := Rect2i()
		for i in FRAMES:
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			if v.args.has("out") and i < 16 and String(var_[0]) == "as is":   # --out=<folder>: the first frames, to look at
				DirAccess.make_dir_recursive_absolute(String(v.args.out))
				img.save_png(String(v.args.out).path_join("ghost_%02d.png" % i))
			if i == 0:
				var c := cam.unproject_position(at + Vector3(0, view.height * 0.5, 0))
				r = Rect2i(Vector2i(c) - Vector2i(40, 60), Vector2i(80, 120)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
			var sum := 0.0
			for y in range(r.position.y, r.end.y, 2):
				for x in range(r.position.x, r.end.x, 2):
					sum += img.get_pixel(x, y).get_luminance()
			vals.append(sum / float((r.size.x / 2) * (r.size.y / 2)))
		var jumps := 0
		var big := 0.0
		for i in range(1, FRAMES - 1):
			var d1 := vals[i] - vals[i - 1]
			var d2 := vals[i + 1] - vals[i]
			if signf(d1) != signf(d2) and absf(d1) > 0.004 and absf(d2) > 0.004:
				jumps += 1
				big = maxf(big, minf(absf(d1), absf(d2)))
		var lo := 1.0
		var hi := 0.0
		for x in vals:
			lo = minf(lo, x)
			hi = maxf(hi, x)
		print("[ghost] %-22s brightness %.3f..%.3f, %d up-down flips in %d frames (biggest %.3f)" % [var_[0], lo, hi, jumps, FRAMES, big])
	get_tree().quit()
