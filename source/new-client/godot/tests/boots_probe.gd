extends Node
## Debug, local (owner 2026-10-16: an Avalonian elementalist's starting boots - white notches at the boot tops): your
## figure in its starter clothes, close on the boots from the front and the side; which meshes are drawn near the
## ankles. Runs once (60 s cap).   --screen 1 --skip-login --zone=1 --figure=ava_f --probe=boots_probe --out=<folder>
var v: Node


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	var out := String(v.args.get("out", "user://boots"))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(6.0).timeout
	v.ui.visible = false
	if v.hud:
		v.hud.visible = false
	var p: Player = v.player
	p.hold()
	var fig := p._model as Fig3Figure
	var gear := {}                                          # --gear=23:249,27:140 - worn items (slot:model)
	for pair in String(v.args.get("gear", "")).split(",", false):
		gear[int(pair.get_slice(":", 0))] = int(pair.get_slice(":", 1))
	if not gear.is_empty():
		Player.dress(fig, func(slot: int) -> Dictionary: return {"model": gear[slot]} if gear.has(slot) else {}, "standard", false, true, {})
		await get_tree().create_timer(0.5).timeout
	var shown := []
	for mi in fig.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).is_visible_in_tree():
			shown.append(String(mi.name))
	print("[boots] drawn: ", shown)
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	for view in [["front", 0.0], ["side", PI * 0.5], ["back", PI]]:
		var dir := Vector3(sin(p.char_yaw + PI + float(view[1])), 0, cos(p.char_yaw + PI + float(view[1])))
		cam.global_position = p.global_position + dir * 1.5 + Vector3(0, 0.45, 0)
		cam.look_at(p.global_position + Vector3(0, 0.3, 0))
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("boots_%s.png" % view[0]))
	get_tree().quit()
