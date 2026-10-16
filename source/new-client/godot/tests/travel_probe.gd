extends Node
## Debug: zone exits. In Tir na Nog it walks into the Lough Derg gate box; the scene reloads into Lough Derg (the
## probe runs again there) and prints where the player arrived, then walks back the other way.
##   --skip-login --zone=209 --figure=cel_m --ui-test --probe=travel_probe --out=<folder>
var viewer: Node
static var hops := 0


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var zid := int(viewer.zone.info.id)
	var p: Vector3 = viewer.player.global_position
	print("[travel] in zone ", zid, " ", viewer.zone.info.name, " at ", p, " location ", PlayerData.character.get("location"))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/travel_%d.png" % [String(viewer.args.get("out", "user://")), hops])
	hops += 1
	if hops > 2:
		get_tree().quit()
		return
	var exits: Array = viewer.zone.info.get("exits", [])
	var e: Dictionary = exits[0]
	for x in exits:
		if int(x.get("to_zone", 0)) in [200, 209]:
			e = x
	print("[travel] walking into ", e.name, " -> zone ", e.get("to_zone"))
	var lo: Array = e.min
	var hi: Array = e.max
	viewer.player.global_position = Vector3(lo[0] - 25.0, lo[1] + 1.0, lo[2] - 25.0)
	await get_tree().create_timer(0.5).timeout                     # standing outside arms the exits
	viewer.player.global_position = Vector3((lo[0] + hi[0]) * 0.5, lo[1] + 1.0, (lo[2] + hi[2]) * 0.5)
	await get_tree().create_timer(3.0).timeout
	print("[travel] still here after 3 s (no reload)")
	get_tree().quit()
