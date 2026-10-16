extends SceneTree
## Debug: a Troll figure loaded the game's way (Fig3Figure: figure.scn, RESET track, deterministic mixer) playing idle,
## then the spell's cast start (0.1 s crossfade, as Player._one_shot) and the mid loop - the root's and the feet's
## heights in the world, step by step (owner 2026-10-11: a troll's legs kick out and lock straight when he casts).
##   Godot --headless --path godot -s res://tests/cast_root_probe.gd -- tro_m cast_bk_hand

var fig: Fig3Figure
var skel: Skeleton3D
var t := 0.0
var phase := 0
var clips := []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix: String = args[0] if args.size() > 0 else "tro_m"
	var style: String = args[1] if args.size() > 1 else "cast_bk_hand"
	clips = [style + "_start", style + "_mid", style + "_end"]
	fig = Fig3Figure.new()
	get_root().add_child(fig)
	fig.load_figure(prefix)
	skel = fig.find_children("*", "Skeleton3D", true, false)[0]
	fig.anim.play("idle")


func _y(bone: String) -> float:
	return (skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone))).origin.y


func _process(_delta: float) -> bool:
	var dt := 1.0 / 30.0
	fig.anim.advance(dt)
	t += dt
	if phase == 0 and t > 0.5:
		phase = 1
		t = 0.0
		fig.anim.play(clips[0], 0.1)
		fig.anim.seek(0.0, true)
	elif phase == 1 and t > fig.anim.get_animation(clips[0]).length:
		phase = 2
		t = 0.0
		fig.anim.play(clips[1], 0.15)
	elif phase == 2 and t > 1.0:
		phase = 3
		t = 0.0
		fig.anim.play(clips[2], 0.1)
		fig.anim.seek(0.0, true)
	elif phase == 3 and t > fig.anim.get_animation(clips[2]).length:
		quit()
		return true
	print("[cast] %d %-22s t %.2f  root %.2f  L foot %.2f  R foot %.2f" % [phase, fig.anim.current_animation, t,
			_y("Bip01"), _y("Bip01 L Foot"), _y("Bip01 R Foot")])
	return false
