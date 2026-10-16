extends Node
## Debug, local (owner 2026-10-16: "a screenshot of the custom Sluaghbinder armor set ... for their lv 50 epic quest"):
## your figure in the whole Dubh Sluagh set (SluaghbinderEpicArmor.cs: helm 4831, hauberk 4826, vambraces 4828,
## gauntlets 4829, greaves 4827, sabatons 4830, mantle 4832) with the mace 4834 and shield 4833 drawn, then the scythe
## 4835; pictures from the front, back and side. Runs once (60 s cap).
##   --screen 1 --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --probe=sluagh_set_probe --out=<folder>
var v: Node
const SET := {21: 4831, 22: 4829, 23: 4830, 25: 4826, 26: 4832, 27: 4827, 28: 4828, 10: 4834, 11: 4833, 12: 4835}


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit())
	v = get_tree().current_scene
	var out := String(v.args.get("out", "user://sluagh_set"))
	DirAccess.make_dir_recursive_absolute(out)
	await get_tree().create_timer(7.0).timeout
	v.ui.visible = false
	if v.hud:
		v.hud.visible = false
	var p: Player = v.player
	p.hold()
	var item_at := func(slot: int) -> Dictionary:
		if not SET.has(slot):
			return {}
		return {"model": SET[slot], "object_type": 42 if slot == 11 else 0}
	var cam := Camera3D.new()
	v.add_child(cam)
	cam.current = true
	cam.fov = 40.0
	var sheathed: bool = v.args.has("sheathed")               # --sheathed: weapons put away (belt / back), no scythe pass
	for set_name in (["standard"] if sheathed else ["standard", "twohand"]):
		for g in p._gear:
			if is_instance_valid(g):
				g.queue_free()
		p._gear = Player.dress(p._model, item_at, set_name, not sheathed, true, {})
		p.in_combat = v.args.has("combat")                  # --combat: the combat stance (weapons raised)
		await get_tree().create_timer(0.5).timeout
		var views := [["front", 0.0], ["back", PI], ["side", PI * 0.5]] if set_name == "standard" else [["front", 0.0], ["side", -PI * 0.5]]
		for view in views:
			var dir := Vector3(sin(p.char_yaw + PI + float(view[1])), 0, cos(p.char_yaw + PI + float(view[1])))
			var k: float = float(v.args.get("cam", "1"))         # --cam=<k>: farther / higher for tall races
			cam.global_position = p.global_position + dir * 3.6 * k + Vector3(0, 1.3 * k, 0)
			cam.look_at(p.global_position + Vector3(0, 1.0 * k, 0))
			await get_tree().create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out.path_join("sluagh_%s_%s.png" % [set_name, view[0]]))
	get_tree().quit()
