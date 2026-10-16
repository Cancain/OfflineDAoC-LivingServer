extends Node
## Debug: which posing paths make BoneAttachment3D log "The caller thread can't call set_transform()" when a figure is
## posed on a worker thread (AnimLod.threaded). One nor_f figure with a sword, its view in a sub-thread group.
##   --headless res://tests/thread_attach_probe.tscn -- --case=<n>
## case 1: worker advance only; 2: + main-thread advance every frame (pose_now); 3: + main-thread transform read;
## 4: + attachment re-made from the worker (call_deferred)

class View extends Node3D:
	var anim: AnimationPlayer
	var redress := false
	var fig: Fig3Figure
	var lod: AnimLod
	func _process(delta: float) -> void:
		anim.advance(delta)
		if lod and Engine.get_process_frames() % 10 == 0:
			lod.refresh_shadow()
		if get_meta("bad", false):
			(get_parent() as Node).set_meta("x", 1)
			get_parent().get_child(0).name = "x"
		if redress and Engine.get_process_frames() % 30 == 0:
			_rehang.call_deferred()
	func _rehang() -> void:
		for at in fig.model.find_children("*", "BoneAttachment3D", true, false):
			at.queue_free()
		WeaponModels.attach(fig.model, "Bip01 R Hand", 1)

var view: View
var case_n := 1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--case="):
			case_n = int(a.get_slice("=", 1))
	view = View.new()
	var f := Fig3Figure.new()
	view.add_child(f)
	f.load_figure("nor_f")
	view.fig = f
	print("[probe] attach ", WeaponModels.attach(f.model, "Bip01 R Hand", 1))
	view.anim = f.anim
	f.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	f.anim.play("walk" if f.anim.has_animation("walk") else "idle")
	view.process_thread_group = Node.PROCESS_THREAD_GROUP_SUB_THREAD
	view.process_thread_group_order = 100
	view.redress = case_n == 4
	if case_n == 7:
		view.set_meta("bad", true)
	add_child(view)
	if case_n == 8 or case_n == 9:                     # a spell effect on a bone: the attachment (8) / the effect (9) on main
		var skel := f.model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var at := BoneAttachment3D.new()
		at.bone_name = "Bip01 R Hand"
		skel.add_child(at)
		var fx := MeshInstance3D.new()
		fx.mesh = BoxMesh.new()
		at.add_child(fx)
		AnimLod.keep_on_main(at if case_n == 8 else fx)
		view.lod = AnimLod.new(view, f, null)
	print("[probe] case ", case_n, " start")


func _process(delta: float) -> void:
	if case_n == 2:
		if Engine.get_process_frames() % 20 == 0:
			view.anim.play("idle" if view.anim.current_animation != "idle" else "walk")
		view.anim.advance(0.0)
	elif case_n == 5:
		view.anim.advance(0.016)
	elif case_n == 6:
		view.anim.play(view.anim.current_animation)
		view.anim.seek(fmod(Engine.get_process_frames() * 0.05, 1.0), true)
	elif case_n == 3:
		var _x = view.fig.model.find_children("*", "BoneAttachment3D", true, false)[0].global_transform
	if Engine.get_process_frames() > 240:
		print("[probe] case ", case_n, " done")
		get_tree().quit()
