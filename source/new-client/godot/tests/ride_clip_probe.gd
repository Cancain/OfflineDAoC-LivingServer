extends Node
## Debug: the player figure in each riding clip, side view.   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --probe=ride_clip_probe --out=<dir>
var v: Node


func _ready() -> void:
	v = get_tree().current_scene
	await get_tree().create_timer(6.0).timeout
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	var p: Node3D = v.player
	var anim: AnimationPlayer = p._anim
	for clip in ["ride_horse", "ride_griffon", "ride_amphitere", "ride_dragonfly"]:
		p.riding = true
		p.ride_clip = clip
		await get_tree().create_timer(1.0).timeout
		var fwd := Vector3(-sin(p.char_yaw), 0, -cos(p.char_yaw))
		cam.global_position = p.global_position + fwd.cross(Vector3.UP) * 3.2 + Vector3(0, 1.0, 0)
		cam.look_at(p.global_position + Vector3(0, 0.9, 0))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/clip_%s.png" % [String(v.args.get("out", "user://")), clip])
		print("[clip] ", clip, " playing ", anim.current_animation, " phys ", p.is_physics_processing(), " riding ", p.riding, " has ", anim.has_animation(clip), " hold ", p.hold_frames, " dead ", p.dead, " list ", anim.get_animation_list().size(), " libs ", anim.get_animation_library_list(), " sample ", Array(anim.get_animation_list()).slice(0, 8), " model ", p._model.scene_file_path if p._model else "-", " ", p._model.get_class() if p._model else "")
	get_tree().quit()
