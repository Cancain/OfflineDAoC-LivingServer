extends Node
## Debug, headless (owner 2026-10-15: cloaks stay flung out behind once you stop): a figure plays run, then idle as
## Player._play does; are the run-only cloak controls (idle keys Control01 only) skeleton bones the RESET covers?
##   Godot --headless --path godot res://tests/cloak_reset_check.tscn


func _ready() -> void:
	var f := Fig3Figure.new()
	add_child(f)
	if not f.load_figure(OS.get_environment("FIG") if OS.get_environment("FIG") != "" else "nor_m"):
		print("[cloak] no figure")
		get_tree().quit()
		return
	var anim: AnimationPlayer = f.anim
	var sk: Skeleton3D = f.find_children("*", "Skeleton3D", true, false)[0]
	var bones := []
	for i in sk.get_bone_count():
		if sk.get_bone_name(i).to_lower().contains("cloak"):
			bones.append(sk.get_bone_name(i))
	print("[cloak] skeleton cloak bones: ", bones)
	var nodes := []
	for n in f.find_children("*Cloak*", "", true, false):
		nodes.append("%s(%s)" % [n.name, n.get_class()])
	print("[cloak] cloak nodes: ", nodes)
	var run: Animation = anim.get_animation("run")
	var paths := []
	for t in run.get_track_count():
		var p := String(run.track_get_path(t))
		if p.to_lower().contains("control0"):
			paths.append(p)
	print("[cloak] run control tracks: ", paths.slice(0, 6))
	var b := sk.find_bone("C Cloak Control01")
	if b >= 0:
		anim.play("run")
		for i in 30:
			anim.advance(1.0 / 30.0)
		var run_q := sk.get_bone_pose_rotation(b)
		anim.play("idle", 0.15)
		for i in 60:
			anim.advance(1.0 / 30.0)
		var rest_q := sk.get_bone_rest(b).basis.get_rotation_quaternion()
		print("[cloak] Control01 after idle %.1f deg from rest (run %.1f)" % [rad_to_deg(sk.get_bone_pose_rotation(b).angle_to(rest_q)), rad_to_deg(run_q.angle_to(rest_q))])
	get_tree().quit()
