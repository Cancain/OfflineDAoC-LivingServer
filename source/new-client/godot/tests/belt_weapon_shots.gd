extends SceneTree
## Debug (owner 2026-10-11: a one-hander hangs straight down on the male Celt's hip, angled on the female): every race
## figure in its idle with a sword at the belt, seen from the side; prints how far each blade tilts from vertical.
##   --path godot --screen 1 -s res://tests/belt_weapon_shots.gd -- --out=<folder> [--races=cel,nor]
func _initialize() -> void:
	await process_frame                                     # the autoloads first (player.gd needs PlayerData)
	var P = load("res://game/player.gd")
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var races := String(args.get("races", "cel,bri,ava,hig,sar,inc,nor,tro,dwa,kob,val,fir,elf,lur,syl")).split(",")
	var out := String(args.get("out", "user://belt"))
	DirAccess.make_dir_recursive_absolute(out)
	var root3 := Node3D.new()
	get_root().add_child(root3)
	var cam := Camera3D.new()
	cam.fov = 30
	root3.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 60, 0)
	root3.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.45, 0.55)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root3.add_child(env)
	var sword := {}
	for id in ["practice_sword"]:
		sword = ItemDb.item(id)
	var item_at := func(s: int) -> Dictionary: return sword if s == 10 else {}
	var figs := []
	var x := 0.0
	for r in races:
		for g in ["m", "f"]:
			var f := Fig3Figure.new()
			root3.add_child(f)
			if not f.load_figure("%s_%s" % [r, g]):
				f.queue_free()
				continue
			f.position = Vector3(x, 0, 0)
			f.rotation.y = -PI / 2                           # its left side (the belt sword) toward the camera
			P.dress(f, item_at, "standard", false)
			f.play(String(args.get("clip", "idle")))
			figs.append([f, "%s_%s" % [r, g]])
			x += 1.1
	cam.position = Vector3((x - 1.1) * 0.5, 0.95, 1.6 + x * 0.48)   # close on the hips
	cam.look_at(Vector3((x - 1.1) * 0.5, 0.85, 0))
	for k in 40:
		await process_frame
	# each blade's tilt: the weapon mesh's longest axis in world space vs straight down
	for fg in figs:
		var f: Fig3Figure = fg[0]
		var mi: MeshInstance3D = null
		for m in f.find_children("*", "MeshInstance3D", true, false):
			if (m as Node).get_parent() and String((m as Node).get_path()).contains("Weapon_"):
				mi = m
				break
		if mi == null:
			print("[blade] %s: no weapon mesh" % fg[1])
			continue
		var bb := mi.get_aabb()
		var ax := 0
		for i in 3:
			if bb.size[i] > bb.size[ax]:
				ax = i
		var long := (mi.global_transform.basis * Vector3([1, 0, 0][ax], [0, 1, 0][ax], [0, 0, 1][ax])).normalized()
		print("[blade] %s: tilt from vertical %.0f deg  (axis %s)" % [fg[1], rad_to_deg(acos(absf(long.y))), long.snapped(Vector3.ONE * 0.01)])
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(out.path_join("belt_%s_%s.png" % [String(args.get("races", "all")).replace(",", "_"), String(args.get("clip", "idle"))]))
	quit()
