extends SceneTree
## Debug: the Catacombs figure's attach bones (back / hip / hand / shield) - rest position and axes in figure space.
func _initialize() -> void:
	var fig := preload("res://game/fig3_figure.gd").new()
	root.add_child(fig)
	for prefix in ["cel_m", "bri_m", "tro_m", "lur_m"]:
		if not fig.load_figure(prefix):
			continue
		var sk: Skeleton3D = fig.find_children("*", "Skeleton3D", true, false)[0]
		var spine := sk.get_bone_global_rest(sk.find_bone("Bip01 Spine2") if sk.find_bone("Bip01 Spine2") >= 0 else sk.find_bone("Bip01 Spine1"))
		print("== ", prefix, " spine2 at ", spine.origin.snapped(Vector3.ONE * 0.1))
		for i in sk.get_bone_count():
			var n := sk.get_bone_name(i)
			if n.contains("Back") or n.contains("Hip") or n.contains("Shield") or n.contains("Weapon") or n.ends_with("Hand") or n.contains("Bow"):
				var g := sk.get_bone_global_rest(i)
				print("  %-20s at %s  x %s  y %s  z %s" % [n, g.origin.snapped(Vector3.ONE * 0.1), g.basis.x.snapped(Vector3.ONE * 0.01), g.basis.y.snapped(Vector3.ONE * 0.01), g.basis.z.snapped(Vector3.ONE * 0.01)])
		for c in fig.get_children():
			c.free()
	quit()
