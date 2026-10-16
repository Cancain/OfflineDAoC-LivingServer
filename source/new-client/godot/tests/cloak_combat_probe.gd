extends Node
## Debug, local (owner 2026-10-16: entering attack mode the cape clips through the player until they move): your
## figure in a cloak with a two-hander, pictures from behind-left: standing, attack mode on (from standing), then after
## a second of running back in attack mode. Runs once (40 s cap).
##   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --figure=nor_m --probe=cloak_combat_probe --weapon=7
var v: Node


func _ready() -> void:
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	var out := String(v.args.get("out", "user://cloak_combat"))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(7.0).timeout
	v.ui.visible = false
	if v.hud:
		v.hud.visible = false
	var p: Player = v.player
	p.hold()
	var weapon := int(v.args.get("weapon", "7"))
	var item_at := func(slot: int) -> Dictionary:
		if slot == 26:
			return {"model": 57, "color": 0}
		return {"model": weapon} if slot == 10 else {}
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.fov = 45.0
	var dress := func(combat: bool) -> void:
		for g in p._gear:
			if is_instance_valid(g):
				g.queue_free()
		p._gear = Player.dress(p._model, item_at, "standard", combat, true, {"hood": true})
		p.combat_stance = WeaponModels.stance(weapon)
		p.in_combat = combat
	var shot := func(name: String) -> void:
		var dir := Vector3(sin(p.char_yaw - 0.6), 0, cos(p.char_yaw - 0.6))
		cam.global_position = p.global_position + dir * 2.4 + Vector3(0, 1.3, 0)
		cam.look_at(p.global_position + Vector3(0, 0.6, 0))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("cloak_%s.png" % name))
		print("[cloak] ", name, " clip ", p._anim.current_animation)
	dress.call(false)
	await get_tree().create_timer(1.5).timeout
	await shot.call("1_standing")
	dress.call(true)
	await get_tree().create_timer(1.5).timeout
	await shot.call("2_attack_on")
	p.force_clip = "run"
	await get_tree().create_timer(1.0).timeout
	p.force_clip = ""
	await get_tree().create_timer(1.5).timeout
	await shot.call("3_after_moving")
	get_tree().quit()
