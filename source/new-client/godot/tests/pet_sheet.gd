extends Node
## Debug (the server's 1.65 pet sheet, owner 2026-10-13): the necromancer / bonedancer pet models in a row, dressed the
## way the NPC views dress them (Player.dress on the model, the active set drawn, the items' weapon effects), idling,
## in front of a camera. user://pet_sheet.png
##   --screen 1 -- --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=pet_sheet
const PETS := [
	["110", {}, ""], ["467", {}, ""], ["106", {}, ""], ["440", {}, ""],
	["653", {12: [6, 30]}, "twohand"],
	["952", {12: [572, 0]}, "twohand"], ["952", {10: [319, 0]}, "standard"],
	["920", {10: [321, 0]}, "standard"], ["920", {13: [564, 0], 10: [311, 0]}, "ranged"],
	["920", {12: [327, 0]}, "twohand"],
]


func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	v.ui.visible = false
	var mons = JSON.parse_string(FileAccess.get_file_as_string("res://content/monsters/monsters.json"))
	var p: Node3D = v.player
	p.visible = false
	var side := p.global_basis.x
	var fwd := -p.global_basis.z
	var n := PETS.size()
	for i in n:
		var info: Dictionary = mons[PETS[i][0]]
		var m := NpcManager._pack_model(String(info.gltf)).instantiate() as Node3D
		var holder := Node3D.new()
		p.get_parent().add_child(holder)
		holder.global_position = p.global_position + side * (1.5 * (i - (n - 1) / 2.0)) + fwd * 4.0
		holder.look_at(holder.global_position - fwd, Vector3.UP)
		holder.add_child(m)
		m.rotation.y = PI
		m.scale *= float(info.get("scale", 1.0))
		Npc.figure_look(m, info, i)
		var slots: Dictionary = PETS[i][1]
		var item_at := func(slot: int) -> Dictionary:
			return {} if not slots.has(slot) else {"model": int(slots[slot][0]), "effect": int(slots[slot][1])}
		Player.dress(m, item_at, String(PETS[i][2]) if PETS[i][2] != "" else "standard", true, false)
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		if aps.size() > 0 and (aps[0] as AnimationPlayer).has_animation("idle"):
			(aps[0] as AnimationPlayer).play("idle")
	var cam := Camera3D.new()
	p.get_parent().add_child(cam)
	cam.global_position = p.global_position + fwd * -4.0 + Vector3(0, 1.6, 0)
	cam.look_at(p.global_position + fwd * 4.0 + Vector3(0, 1.0, 0), Vector3.UP)
	cam.fov = 70.0
	cam.current = true
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("user://pet_sheet.png")
	for h in p.get_parent().get_children():               # side views: every pet turned a quarter
		if h is Node3D and h.get_child_count() == 1 and h.get_child(0).find_children("*", "Skeleton3D", true, false).size() > 0 				and h != p:
			(h as Node3D).rotate_y(PI / 2.0)
	await get_tree().create_timer(0.5).timeout
	get_viewport().get_texture().get_image().save_png("user://pet_sheet_side.png")
	get_tree().quit()
