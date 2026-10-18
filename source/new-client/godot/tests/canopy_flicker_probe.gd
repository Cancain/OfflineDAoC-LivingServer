extends Node
## Debug, local (owner 2026-10-16: shadows flicker under big canopies - Domnann, Iarnwood - as you move; not the sun's
## motion: tests/shadow_sun_probe.gd). The camera runs a straight line under the Domnann canopy at running pace,
## behind-and-above like the game camera, once per variant; a pixel "flickers" when its brightness goes up then down
## (or down then up) over three frames by more than a step - a plain slide changes pixels steadily, a flicker toggles.
## Variants switch one suspect off at a time. Runs once (170 s cap).
##   --screen 1 --skip-login --zone=181 --figure=nor_m --probe=canopy_flicker_probe [--only=<variant>]
var v: Node
const FRAMES := 70
const STEP_M := 0.12                          # ~7 m/s at 60 frames a second


func _ready() -> void:
	get_tree().create_timer(170.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	await get_tree().create_timer(8.0).timeout
	v.ui.visible = false
	if v.hud:
		v.hud.visible = false
	v.sky.time_scale = 0.0
	var at := Vector3(31147 * 0.025, 0, 51289 * 0.025)
	at.y = v.zone.height_at(at.x, at.z)
	v.player.global_position = at + Vector3(0, 0.5, 0)
	v.player.hold()
	v.player.visible = false
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.fov = 70.0
	await get_tree().create_timer(2.0).timeout
	var sun: DirectionalLight3D = v.sky.sun
	var env: Environment = v.sky.environment
	var base := {"shadow": sun.shadow_enabled, "ssao": env.ssao_enabled, "blur": sun.shadow_blur,
			"dist": sun.directional_shadow_max_distance, "blend": sun.directional_shadow_blend_splits}
	var variants := [
		["as is", func(): pass],
		["no sun shadow", func(): sun.shadow_enabled = false],
		["no SSAO", func(): env.ssao_enabled = false],
		["shadow max 60 m", func(): sun.directional_shadow_max_distance = 60.0],
		["no split blend", func(): sun.directional_shadow_blend_splits = false],
		["blur 0", func(): sun.shadow_blur = 0.0],
		["blur 5", func(): sun.shadow_blur = 5.0],
	]
	var only := String(v.args.get("only", ""))
	for var_ in variants:
		if only != "" and String(var_[0]) != only:
			continue
		sun.shadow_enabled = base.shadow
		env.ssao_enabled = base.ssao
		sun.shadow_blur = base.blur
		sun.directional_shadow_max_distance = base.dist
		sun.directional_shadow_blend_splits = base.blend
		(var_[1] as Callable).call()
		await get_tree().create_timer(0.5).timeout
		var lums: Array = []
		for i in FRAMES:
			var p := at + Vector3(-4.0 + STEP_M * i, 0, 0)
			p.y = v.zone.height_at(p.x, p.z)
			cam.global_position = p + Vector3(0, 2.2, 4.0)
			cam.look_at(p + Vector3(0, 1.0, 0))
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.resize(192, 108, Image.INTERPOLATE_BILINEAR)
			var row := PackedFloat32Array()
			row.resize(192 * 108)
			for y in 108:
				for x in 192:
					row[y * 192 + x] = img.get_pixel(x, y).get_luminance()
			lums.append(row)
		var toggles := 0
		for i in range(1, FRAMES - 1):
			var a: PackedFloat32Array = lums[i - 1]
			var b: PackedFloat32Array = lums[i]
			var c: PackedFloat32Array = lums[i + 1]
			for k in a.size():
				var d1 := b[k] - a[k]
				var d2 := c[k] - b[k]
				if absf(d1) > 0.05 and absf(d2) > 0.05 and signf(d1) != signf(d2):
					toggles += 1
		print("[canopy] %-16s %.1f flickering pixels a frame (of %d)" % [var_[0], toggles / float(FRAMES - 2), 192 * 108])
	get_tree().quit()
