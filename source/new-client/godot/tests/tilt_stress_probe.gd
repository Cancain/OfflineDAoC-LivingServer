extends Node
## Debug (owner 2026-10-10: the idle tilt is intermittent - "most noticeable when you make a new character without
## moving"): 16 rounds of spawn-like events (drops from 0-6 m, a run stopped short, a jump, sit / stand, a swing, a
## re-held spawn), then 2 s settled in idle: the pelvis / spine angles from vertical and the clip. A tilted round
## shows a pelvis angle above ~2 degrees or a clip other than idle.
var v: Node


func _angles(p: Node3D) -> String:
	var model: Node3D = p.get("_model")
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var out := ""
	for b in ["Bip01 Pelvis", "Bip01 Spine1", "Bip01 Neck"]:
		var i := sk.find_bone(b)
		var g := sk.global_transform * sk.get_bone_global_pose(i)
		out += "%s %.1f  " % [b.trim_prefix("Bip01 "), rad_to_deg(g.basis.x.normalized().angle_to(Vector3.UP))]
	return out


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var p: Node3D = v.player
	var home: Vector3 = p.global_position
	var anim: AnimationPlayer = p.get("_anim")
	print("[tilt] start  clip=", anim.current_animation, "  ", _angles(p))
	for r in 16:
		var kind := r % 8
		match kind:
			0, 1, 2:                                         # a drop like a zone arrival / spawn
				p.global_position = home + Vector3(0, [0.3, 2.5, 6.0][kind], 0)
				p.hold()
			3:                                               # a run stopped short
				p.set("autorun", true)
				await get_tree().create_timer(0.35).timeout
				p.set("autorun", false)
			4:                                               # a jump
				Input.action_press("jump")
				await get_tree().create_timer(0.1).timeout
				Input.action_release("jump")
			5:                                               # sit, then stand
				p.sit(true)
				await get_tree().create_timer(1.5).timeout
				p.sit(false)
			6:                                               # a swing / one-shot
				p.swing("")
			7:                                               # re-held in place (zone entry)
				p.hold()
		await get_tree().create_timer(2.5).timeout
		print("[tilt] round %d (%s) clip=%s  speed=%.2f  %s" % [r, ["drop0.3", "drop2.5", "drop6", "run", "jump", "sit", "swing", "hold"][kind],
				anim.current_animation, anim.speed_scale, _angles(p)])
		p.global_position = home
		p.hold()
		await get_tree().create_timer(0.5).timeout
	get_tree().quit()
