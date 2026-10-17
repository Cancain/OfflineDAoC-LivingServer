extends Node
## Debug (owner 2026-10-15: check the flex weapons' swings - stances 9 / 10 / 11 played with canims' small / medium /
## large flex columns): a Briton male per weapon (rows: chain 857 stance 9, flail 861 stance 10, whip 859 stance 11)
## and per swing set (columns: attack_fws_high, attack_fwm_high, attack_fwl_high), the weapon's chain swinging with
## it, frozen at three moments of the swing - user://flex/flex_<percent>.png. Quits by itself (hard stop 60 s).
##   --path godot --screen 1 -- --skip-login --zone=1 --figure=bri_m --probe=flex_clip_shots
const WEAPONS := [[857, "chain"], [861, "flail"], [859, "whip"]]
const SETS := ["fws", "fwm", "fwl"]
const MOMENTS := [0.35, 0.55, 0.75]


func _ready() -> void:
	if get_tree().root.has_meta("flex_shots_ran"):
		return
	get_tree().root.set_meta("flex_shots_ran", true)
	get_tree().create_timer(60.0).timeout.connect(get_tree().quit)
	var v := get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	v.ui.visible = false
	if v.hud:
		v.hud.visible = false
	v.player.visible = false
	var P = load("res://game/player.gd")
	DirAccess.make_dir_recursive_absolute("user://flex")
	var root3 := Node3D.new()                               # far above the zone: only the figures in view
	v.add_child(root3)
	root3.global_position = v.player.global_position + Vector3(0, 400, 0)
	var cam := Camera3D.new()
	cam.fov = 35
	root3.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	root3.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.45, 0.55)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	root3.add_child(env)
	var cells := []                                         # [figure, clip]
	for r in WEAPONS.size():
		for c in SETS.size():
			var f := Fig3Figure.new()
			root3.add_child(f)
			if not f.load_figure("bri_m"):
				print("[flex] no bri_m figure")
				get_tree().quit()
				return
			f.position = Vector3(c * 2.4, 0, -r * 2.6)
			f.rotation.y = -PI / 4                           # three-quarter view: the swing's arc shows
			var item := {"model": int(WEAPONS[r][0])}
			P.dress(f, func(s: int) -> Dictionary: return item if s == 10 else {}, "standard", true)
			var clip := "attack_%s_high" % SETS[c]
			if not f.anim.has_animation(clip):
				print("[flex] %s: figure has no %s" % [WEAPONS[r][1], clip])
			cells.append([f, clip, "%s / %s" % [WEAPONS[r][1], SETS[c]]])
	cam.position = Vector3(2.4, 4.2, 5.2)
	cam.current = true
	cam.look_at(root3.to_global(Vector3(2.4, 0.6, -2.6)))
	for k in 20:
		await get_tree().process_frame
	for m in MOMENTS:
		for cell in cells:
			var f: Fig3Figure = cell[0]
			var clip: String = cell[1]
			if not f.anim.has_animation(clip):
				continue
			var len := f.anim.get_animation(clip).length
			f.anim.play(clip)
			f.anim.seek(len * m, true)
			f.anim.pause()
			WeaponModels.flex_swing(f, clip)                # the weapon's own chain clip, at the same moment
			for ap in f.find_children("*", "AnimationPlayer", true, false):
				var p := ap as AnimationPlayer
				if p != f.anim and p.current_animation != "":
					var cl := p.get_animation(p.current_animation).length
					p.seek(minf(len * m, cl), true)
					p.pause()
		for k in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://flex/flex_%d.png" % int(m * 100))
		print("[flex] saved flex_%d.png" % int(m * 100))
	get_tree().quit()
