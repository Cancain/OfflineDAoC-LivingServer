extends Node
## Debug, local (owner 2026-10-16: shadows under big canopies - Domnann, Iarnwood - flicker as you move): the camera
## held still under the Domnann canopy (the 2026-10-15 spot) and the ground compared frame to frame, first with the
## game clock running (the sun turning a little every frame), then with it stopped - how much of the flicker is the
## sun moving. Then the same while the camera slides 5 cm a frame. Runs once (90 s cap).
##   --screen 1 --skip-login --zone=181 --figure=nor_m --probe=shadow_sun_probe
func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit())
	var v := get_tree().current_scene
	await get_tree().create_timer(8.0).timeout
	v.ui.visible = false
	if v.hud:
		v.hud.visible = false
	var at := Vector3(31147 * 0.025, 0, 51289 * 0.025)
	at.y = v.zone.height_at(at.x, at.z)
	v.player.global_position = at + Vector3(0, 0.5, 0)
	v.player.hold()
	v.player.visible = false
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.global_position = at + Vector3(0, 4.0, 6.0)
	cam.look_at(at)
	await get_tree().create_timer(3.0).timeout
	for run in [["clock running, still", 1.0, 0.0], ["clock stopped, still", 0.0, 0.0],
			["clock running, sliding", 1.0, 0.05], ["clock stopped, sliding", 0.0, 0.05]]:
		v.sky.time_scale = float(run[1])
		var base := at + Vector3(0, 4.0, 6.0)
		var prev: Image = null
		var jumps := 0.0
		var frames := 90
		for i in frames:
			cam.global_position = base + Vector3(float(run[2]) * i, 0, 0)
			cam.look_at(cam.global_position + (at - (at + Vector3(0, 4.0, 6.0))))
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.resize(160, 90, Image.INTERPOLATE_BILINEAR)
			if prev:
				var n := 0
				for y in range(45, 90):
					for x in 160:
						if absf(img.get_pixel(x, y).get_luminance() - prev.get_pixel(x, y).get_luminance()) > 0.06:
							n += 1
				jumps += n
			prev = img
		print("[sun] %s: %.1f of 7200 ground pixels jump a frame" % [run[0], jumps / float(frames - 1)])
	get_tree().quit()
