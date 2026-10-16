extends Node
## Debug: frames per second each second for --secs (default 20) after the zone is up, standing still.
func _ready() -> void:
	var v: Node = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var line := ""
	for i in int(v.args.get("secs", "20")):
		await get_tree().create_timer(1.0).timeout
		line += "%d " % Engine.get_frames_per_second()
	print("[fps] ", line)
	get_tree().quit()
