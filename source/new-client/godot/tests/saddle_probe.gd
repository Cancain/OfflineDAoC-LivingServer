extends Node
## Debug: where the horse's saddle bone is relative to the horse (rider seat).
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var h: Node3D = viewer.npcs.instance_model("res://content/monsters/horse01__horse_black/model.gltf")
	add_child(h)
	h.global_position = Vector3(500, 100, 500)
	await get_tree().process_frame
	var sk: Skeleton3D = h.find_children("*", "Skeleton3D", true, false)[0]
	var b := sk.find_bone("saddle")
	var names := []
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
	print("[saddle] bones ", names)
	var sn: Node = h.find_child("saddle*", true, false)
	print("[saddle] node ", sn, " ", (sn as Node3D).global_position - h.global_position if sn is Node3D else "")
	print("[saddle] bone ", b, " skeleton global ", sk.global_transform, " model root children ", h.get_children().map(func(c): return c.name))
	var g := sk.global_transform * sk.get_bone_global_pose(b)
	print("[saddle] seat - horse ", g.origin - h.global_position, " pelvis ", (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Bip01 Pelvis"))).origin - h.global_position)
	for bn in ["Bip01 Pelvis", "Bip01 Spine", "Bip01 Spine1", "Bip01 Spine2", "Bip01 Neck", "Bip01 Head", "Bip01 L Thigh", "Bip01 L UpperArm"]:
		var bi := sk.find_bone(bn)
		if bi >= 0:
			print("[saddle] ", bn, " ", (sk.global_transform * sk.get_bone_global_pose(bi)).origin - h.global_position)
	var p = viewer.player
	if p._anim and p._anim.has_animation("ride_horse"):
		p._anim.play("ride_horse")
		p._anim.seek(0.1, true)
		await get_tree().process_frame
		var ps: Skeleton3D = p.find_children("*", "Skeleton3D", true, false)[0]
		var pel := ps.find_bone("Bip01 Pelvis")
		print("[saddle] rider pelvis above its origin while riding ", (ps.global_transform * ps.get_bone_global_pose(pel)).origin - p.global_position,
				" model rot ", p._model.rotation)
	get_tree().quit()
