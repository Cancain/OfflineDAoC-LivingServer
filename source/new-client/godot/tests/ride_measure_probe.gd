extends Node
## Debug: during a real horse ride, where the rider's pelvis sits against the horse's saddle node and spine.
##   --headless --skip-login --zone=200 --figure=cel_m --ui-test --probe=ride_measure_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	for s in viewer.npcs.states:
		if String((s as NpcState).spawn.name) == "Rumdor":
			var at: Vector3 = (s as NpcState).pos + Vector3(2, 0, 0)
			at.y = viewer.zone.height_at(at.x, at.z) + 0.3
			viewer.player.global_position = at
	await get_tree().create_timer(0.5).timeout
	PlayerData.buy("HS_MagMell_ParthenonFarm", "Rumdor")
	var hr: Node = viewer.find_children("*", "HorseRoutes", true, false)[0]
	for i in 3:
		await get_tree().create_timer(2.5).timeout
		var horse: Node3D = hr.horse
		var p: Node3D = viewer.player
		var sk: Skeleton3D = horse.find_children("*", "Skeleton3D", true, false)[0]
		var fwd := horse.global_transform.basis.z.normalized()        # the horse model faces +Z
		var seat: Vector3 = hr._seat()
		var ps: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
		var pel := (ps.global_transform * ps.get_bone_global_pose(ps.find_bone("Bip01 Pelvis"))).origin
		var sp1 := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 Spine1"))).origin
		var hpel := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 Pelvis"))).origin
		print("[ride] t=%d anim=%s rider_anim=%s | along horse (m, + = toward head): seat %.2f, rider pelvis %.2f, player origin %.2f, horse spine1 %.2f, horse pelvis %.2f | heights: seat %.2f rider pelvis %.2f" % [
				i, hr._horse_anim.current_animation if hr._horse_anim else "-", p._anim.current_animation if p._anim else "-",
				(seat - horse.global_position).dot(fwd), (pel - horse.global_position).dot(fwd), (p.global_position - horse.global_position).dot(fwd),
				(sp1 - horse.global_position).dot(fwd), (hpel - horse.global_position).dot(fwd), seat.y - horse.global_position.y, pel.y - horse.global_position.y])
		print("[ride] rider facing vs horse: ", snappedf(rad_to_deg(p._model.global_transform.basis.z.signed_angle_to(fwd, Vector3.UP)), 1.0), " deg")
	get_tree().quit()
