extends Node
## Debug: the animated siege copies load (WeaponModels.make_animated) - their clips.
func _ready() -> void:
	for m in [2602, 2604, 2605, 2607, 2645]:
		var path := WeaponModels.anim_path_of(m)
		var node := WeaponModels.make_animated(m)
		var ap: Array = node.find_children("*", "AnimationPlayer", true, false) if node else []
		print("[model] %d %s -> %s clips %s" % [m, path, node != null, (ap[0] as AnimationPlayer).get_animation_list() if ap.size() > 0 else []])
	get_tree().quit()
