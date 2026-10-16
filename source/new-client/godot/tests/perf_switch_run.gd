extends Node
## Debug (perf_switch_probe): in the new world, the frame rate and the governor's state each second - at the 60 fps
## target, with the target OFF (brute force), then at 60 again - and what the NPC views do (shadows cast, poses a
## frame); then a proper /quit.


func _ready() -> void:
	var first := get_tree().current_scene
	for i in 60:
		await get_tree().create_timer(0.5).timeout
		var s := get_tree().current_scene
		if s != first and s and s.get("player") and Server.playing:
			break
	await get_tree().create_timer(8.0).timeout
	for phase in [[60, 12], [0, 12], [60, 20]]:
		Perf.set_option("target_fps", phase[0])
		print("[perf] -- target %d" % phase[0])
		for k in int(phase[1]):
			await get_tree().create_timer(1.0).timeout
			_line()
	Server.quit_world(true)


func _line() -> void:
	var s := get_tree().current_scene
	var npcs = s.get("npcs") if s else null
	var shadows := 0
	var drawn := 0
	if npcs is NpcManager:
		drawn = (npcs.active as Dictionary).size()
		for k in npcs.active:
			var lod = (npcs.active[k] as Npc).get("_lod")
			if lod and bool(lod.get("_casting_shadow")):
				shadows += 1
	print("[perf] fps %3.0f  brute %s  cpu %.2f gpu %.2f  gpu %.1f ms  effects %d  npcs %d (shadow %d)  anim range %.2f budget %d  voices %d" % [
			Engine.get_frames_per_second(), Perf.brute, Perf.cpu_level, Perf.gpu_level, Perf.gpu_ms, SpellFx._live.size(),
			drawn, shadows, Perf.anim_range, Perf.anim_budget, Perf.voices])
