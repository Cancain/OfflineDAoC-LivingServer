extends Node
## Debug (windowed): force the three quest rings on the Lethantis trainers and take a picture.
##   --screen 1 --skip-login --zone=8 --realm=alb --ui-test --probe=ring_force_shot --out=<folder>
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var out := String(viewer.args.get("out", "user://rings"))
	var p: Player = viewer.player
	p.global_position = Vector3(14134 * 0.025, 2292 * 0.025 + 0.3, 6483 * 0.025 - 6.0)
	p.char_yaw = PI
	p.cam_yaw = PI
	p.cam_pitch = -0.5
	p.cam_distance = 6.0
	var mk: QuestMarkers = viewer.ui.find_children("*", "QuestMarkers", true, false)[0]
	mk._tick = 999.0
	var kinds := ["available", "turnin", "progress"]
	var k := 0
	for s in viewer.npcs.states:
		var st: NpcState = s
		if st.spawn.name in ["Magus Oreal", "Master Qilith", "Mistress Trethia"]:
			mk._marked[st] = kinds[k % 3]
			k += 1
	mk._sync_decals()
	await get_tree().create_timer(2.0).timeout
	get_viewport().get_texture().get_image().save_png(out + "/rings_forced.png")
	get_tree().quit()
