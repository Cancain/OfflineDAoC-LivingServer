extends Node
## Debug (owner 2026-10-14: "a piece of water texture or something sticking out of the ground" near West Svealand loc
## 12915 51372 4274): every drawn mesh whose bounds cover the player's spot (within --r metres), with its owner path
## and material, and a screenshot user://mesh_at.png.
##   --skip-login --zone=102 --pos=322.9,107.5,1284.3 --figure=cel_m --probe=mesh_at_probe [--r=15] [--yaw=deg]
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	var r := 15.0
	var yaw := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--r="):
			r = float(a.get_slice("=", 1))
		elif a.begins_with("--yaw="):
			yaw = float(a.get_slice("=", 1))
	await get_tree().create_timer(10.0).timeout
	v.player.face(deg_to_rad(yaw))
	var p: Vector3 = v.player.global_position
	print("[mesh] player at ", p, "  ground ", v.zone.height_at(p.x, p.z), "  water level ", v.zone.water_level_at(p.x, p.z))
	for n in v.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.visible or not g.is_visible_in_tree():
			continue
		var bb: AABB = g.global_transform * g.get_aabb()
		if bb.size.length() > 3000.0:
			continue
		if p.x < bb.position.x - r or p.x > bb.end.x + r or p.z < bb.position.z - r or p.z > bb.end.z + r:
			continue
		if p.y < bb.position.y - 20.0 or p.y > bb.end.y + 20.0:
			continue
		var mat = g.material_override
		if mat == null and g is MeshInstance3D and (g as MeshInstance3D).mesh and (g as MeshInstance3D).mesh.get_surface_count() > 0:
			mat = (g as MeshInstance3D).mesh.surface_get_material(0)
		var what := ""
		if mat is ShaderMaterial and (mat as ShaderMaterial).shader:
			what = "shader " + (mat as ShaderMaterial).shader.resource_path
		elif mat is StandardMaterial3D:
			what = "standard tex " + (str((mat as StandardMaterial3D).albedo_texture.resource_path) if (mat as StandardMaterial3D).albedo_texture else "none")
		print("[mesh] ", v.get_path_to(g), "  ", g.get_class(), "  aabb ", bb, "  ", what)
	for w in v.ui.windows.values():                       # (windows left open by earlier runs)
		if w is Control:
			(w as Control).visible = false
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://mesh_at.png")
	get_tree().quit()
