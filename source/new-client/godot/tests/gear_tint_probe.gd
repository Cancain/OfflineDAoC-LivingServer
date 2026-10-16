extends Node
## and texture each visible cloak / hat surface gets.
func _ready() -> void:
	await get_tree().process_frame
	var f := Fig3Figure.new()
	add_child(f)
	f.load_figure("cel_m")
	var items := {26: {"model": 57, "color": 20}, 21: {"model": 1279, "color": 10}, 25: {"model": 378, "color": 22}}
	var item_at := func(slot: int) -> Dictionary: return items.get(slot, {})
	Player.dress(f, item_at, "standard", false, true, {"hood": false})
	await get_tree().process_frame
	for k in [1, 2, 3]:
		for mi in f._parts("cloak_%d" % k):
			var m = (mi as MeshInstance3D).material_override
			print("cloak_%d visible=%s tint=%s mode=%s" % [k, mi.visible, m.get_shader_parameter("tint") if m else "-", m.get_shader_parameter("tint_mode") if m else "-"])
	for mi in f.find_children("*", "MeshInstance3D", true, false):
		var p := String(mi.get_path())
		if p.contains("Weapon") or p.contains("BoneAttachment"):
			for si in (mi as MeshInstance3D).mesh.get_surface_count():
				var mat = (mi as MeshInstance3D).get_active_material(si)
				print("helm surface ", si, " albedo=", mat.albedo_color if mat is BaseMaterial3D else "?", " tex=", mat.albedo_texture.resource_path if mat is BaseMaterial3D and mat.albedo_texture else "-")
	get_tree().quit()
