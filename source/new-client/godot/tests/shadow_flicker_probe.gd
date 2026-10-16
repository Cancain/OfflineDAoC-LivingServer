extends Node
## Debug, local (owner 2026-10-15: Grove of Domnann loc 31147 51289 5952 - the ground's shadows flicker over the whole
## area while you move): a camera above the spot stepped 5 cm at a time; how much the ground half of the picture
## changes from frame to frame (a smooth move changes it a little everywhere, popping shadows a lot in places), with
## the sun's shadow pancake as given (--pancake=<m>, default the light's own). Runs once, quits (hard stop 60 s).
func _ready() -> void:
	if get_tree().root.has_meta("shadow_flicker_ran"):
		return
	get_tree().root.set_meta("shadow_flicker_ran", true)
	get_tree().create_timer(170.0).timeout.connect(func(): get_tree().quit())
	var v := get_tree().current_scene
	await get_tree().create_timer(8.0).timeout
	v.ui.visible = false
	if v.hud:
		v.hud.visible = false
	var sun: DirectionalLight3D = v.sky.sun
	if v.args.has("pancake"):
		sun.directional_shadow_pancake_size = float(String(v.args.pancake))
	var at := Vector3(31147 * 0.025, 0, 51289 * 0.025)
	at.y = v.zone.height_at(at.x, at.z) if v.zone else 5952 * 0.025
	v.player.global_position = at + Vector3(0, 0.5, 0)
	v.player.hold()
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	await get_tree().create_timer(3.0).timeout
	# the shadow alone: each step drawn with and without the sun's shadow; their ratio is the shadow term, which should
	# change smoothly as the camera slides - its jumps are the flicker. Configurations compared in one run.
	var configs := [["as is", 4, true, 140.0, 2.5, [0.1, 0.2, 0.5]], ["2 splits", 2, true, 140.0, 2.5, [0.1, 0.2, 0.5]],
			["4 @.2/.4/.7", 4, true, 140.0, 2.5, [0.2, 0.4, 0.7]], ["4 @.15/.3/.6", 4, true, 140.0, 2.5, [0.15, 0.3, 0.6]],
			["4 @.06/.15/.4", 4, true, 140.0, 2.5, [0.06, 0.15, 0.4]]]
	for c in configs:
		sun.directional_shadow_split_1 = float(c[5][0])
		sun.directional_shadow_split_2 = float(c[5][1])
		sun.directional_shadow_split_3 = float(c[5][2])
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if int(c[1]) == 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_blend_splits = bool(c[2])
		sun.directional_shadow_max_distance = float(c[3])
		sun.shadow_blur = float(c[4])
		var jumps := []
		var sharp := []
		var prev := PackedFloat32Array()
		for i in 20:
			var step := float(String(v.args.get("step", "0.05")))
			cam.global_position = at + Vector3(-4.0 + i * step, 3.0, 6.0)
			cam.look_at(at + Vector3(i * step, 0, 0))
			var shots := []
			for on in [true, false]:
				sun.shadow_enabled = on
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				img = img.get_region(Rect2i(0, img.get_height() / 2, img.get_width(), img.get_height() / 2))
				img.resize(160, 45)
				shots.append(img)
			var term := PackedFloat32Array()
			term.resize(7200)
			for y in 45:
				for x in 160:
					var lit := maxf((shots[1] as Image).get_pixel(x, y).get_luminance(), 0.02)
					term[y * 160 + x] = clampf((shots[0] as Image).get_pixel(x, y).get_luminance() / lit, 0.0, 1.5)
			var g := 0.0
			for y in 44:
				for x in 159:
					g += absf(term[y * 160 + x] - term[y * 160 + x + 1]) + absf(term[y * 160 + x] - term[(y + 1) * 160 + x])
			sharp.append(g / 7000.0)
			if not prev.is_empty():
				var n := 0
				for k in 7200:
					if absf(term[k] - prev[k]) > 0.15:
						n += 1
				jumps.append(n)
			prev = term
		sun.shadow_enabled = true
		print("[sf] %-14s jumping >0.15 per step: mean %.1f max %d (of 7200)   edge sharpness %.4f" % [c[0],
				float(jumps.reduce(func(a, b): return a + b, 0)) / jumps.size(), jumps.max(), float(sharp.reduce(func(a, b): return a + b, 0.0)) / sharp.size()])
	get_viewport().get_texture().get_image().save_png("user://shadow_flicker_%d.png" % int(sun.directional_shadow_pancake_size))
	get_tree().quit()
