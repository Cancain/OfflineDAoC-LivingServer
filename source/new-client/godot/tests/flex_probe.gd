extends Node
func _ready() -> void:
	for drawn in [false, true]:
		var w := WeaponModels.make(862, drawn)
		add_child(w)
		var ap := w.find_children("*", "AnimationPlayer", true, false)
		var sk := w.find_children("*", "Skeleton3D", true, false)
		print("drawn=", drawn, " players=", ap.size(), " playing=", (ap[0] as AnimationPlayer).current_animation if ap.size() > 0 else "-",
				" skeleton bones=", (sk[0] as Skeleton3D).get_bone_count() if sk.size() > 0 else 0,
				" meshes=", w.find_children("*", "MeshInstance3D", true, false).size())
	get_tree().quit()
