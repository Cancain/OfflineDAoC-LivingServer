extends Node
## Debug (seamless zones): does releasing a neighbour give its memory back? Stands in the middle of Lough Derg (no
## neighbour in reach), then builds and releases Silvermine three times, printing video / static memory each step.
##   --screen 1 --skip-login --zone=200 --figure=cel_m --probe=zone_mem_probe
var v: Node


func _mem(label: String) -> void:
	for i in 30:
		await get_tree().process_frame
	print("[mem] %-22s video %5d MB, textures %5d MB, buffers %4d MB, static %5d MB, nodes %d, objects %d" % [label,
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576,
			Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576,
			OS.get_static_memory_usage() / 1048576, Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_COUNT)])


func _ready() -> void:
	v = get_tree().current_scene
	var region: RegionWorld = v.region
	var p: Player = v.player
	p.global_position = Vector3(820, region.height_at(820, 700) + 0.5, 700)
	await get_tree().create_timer(4.0).timeout
	region.set_process(false)                             # nothing streams by itself
	await _mem("start")
	for k in 3:
		region._start_build(201)
		while region._task >= 0 and not WorkerThreadPool.is_task_completed(region._task):
			await get_tree().process_frame
		WorkerThreadPool.wait_for_task_completion(region._task)
		region._task = -1
		region._place_built()
		await _mem("Silvermine loaded %d" % (k + 1))
		region._release(201)
		await get_tree().create_timer(1.0).timeout
		await _mem("released %d" % (k + 1))
	get_tree().quit()
