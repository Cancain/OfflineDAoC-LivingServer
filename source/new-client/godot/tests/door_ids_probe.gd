extends Node
## Debug (owner 2026-10-14, keep sieges): the zone's doors and the client door ids they got (ZoneLoader._make_doors:
## zone x 1,000,000 + fixture x 100 + door group number) - compare with the server's Door table.
##   --skip-login --zone=15 --probe=door_ids_probe


func _ready() -> void:
	await get_tree().create_timer(6.0).timeout
	var v := get_tree().current_scene
	var z: ZoneLoader = v.zone
	var ids: Array = z.door_by_id.keys()
	ids.sort()
	print("[doors] zone %d: %d door leaves, %d door ids" % [int(z.info.id), z.doors.size(), ids.size()])
	print("[doors] ids: ", ids.slice(0, 40))
	get_tree().quit()
