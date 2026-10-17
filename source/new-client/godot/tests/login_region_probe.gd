extends Node
## Debug (seamless zones): with the loading screen (--with-loading), the neighbours in reach are built behind it
## (RegionWorld.load_around) - which zones are in when you see the world, and how the first seconds run.
##   --screen 1 --skip-login --zone=200 --figure=cel_m --with-loading --pos=500,140,1500 --probe=login_region_probe
func _ready() -> void:
	var v := get_tree().current_scene
	var t0 := Time.get_ticks_msec()
	var worst := 0.0
	var long := 0
	for i in 300:
		var a := Time.get_ticks_usec()
		await get_tree().process_frame
		var ms := (Time.get_ticks_usec() - a) / 1000.0
		worst = maxf(worst, ms)
		if ms > 34.0:
			long += 1
	print("[login] zones in the world: %s, first 300 frames after the loading screen: worst %.1f ms, over 34 ms: %d, fps %d" % [
			v.region.zones.keys() if v.region else [], worst, long, Engine.get_frames_per_second()])
	get_tree().quit()
