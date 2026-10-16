extends Node
## Debug (owner 2026-10-10: swimming in shallow water, the swimmer under the surface): the player's height, the water
## level and the ground under him, whether he swims, and in the swim clip where the head / neck / pelvis sit against
## the feet (origin).   --screen 1 --skip-login --zone=57 --figure=cel_m --probe=swim_probe [--pos=..]
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(7.0).timeout
	var p: Node3D = v.player
	var g: float = v.zone.height_at(p.global_position.x, p.global_position.z)
	var w: float = v.zone.water_level_at(p.global_position.x, p.global_position.z)
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3(0, 5, 0), p.global_position - Vector3(0, 20, 0), ZoneLoader.LAYER_FLOOR)
	var hit := space.intersect_ray(q)
	print("[swim] player y ", snappedf(p.global_position.y, 0.01), " water ", snappedf(w, 0.01), " height_at ", snappedf(g, 0.01),
			" floor ray ", hit.get("position", Vector3.ZERO).y if not hit.is_empty() else "-", " swimming ", p.swimming)
	var anim: AnimationPlayer = p._anim
	p.force_clip = "swim"
	await get_tree().create_timer(0.6).timeout
	var sk: Skeleton3D = p._model.find_children("*", "Skeleton3D", true, false)[0]
	for b in ["Bip01 Head", "Bip01 Neck", "Bip01 Spine2", "Bip01 Pelvis", "Bip01 L Foot"]:
		var i := sk.find_bone(b)
		if i >= 0:
			var gp := (sk.global_transform * sk.get_bone_global_pose(i)).origin
			print("[swim] swim clip: ", b, " ", snappedf(gp.y - p.global_position.y, 0.01), " m above the feet")
	p.force_clip = ""
	await get_tree().create_timer(0.6).timeout
	var hi := sk.find_bone("Bip01 Head")
	print("[swim] idle: head ", snappedf((sk.global_transform * sk.get_bone_global_pose(hi)).origin.y - p.global_position.y, 0.01))
	get_tree().quit()
