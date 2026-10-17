extends Node
## Debug, local (owner 2026-10-15: corpse lights look wrong): the six corpse light effects (monsters 907-912, effect-only
## models) side by side in front of the camera, as the NPC views attach them (NifScene copies) -
## user://corpselights_<tag>.png. Runs once, hard limit 40 s.
##   --screen 1 -- --skip-login --zone=200 "--at=Mag Mell" --figure=elf_m --ui-test --probe=corpselight_probe --tag=before
func _ready() -> void:
	if get_tree().root.has_meta("corpse_probe_ran"):
		return
	get_tree().root.set_meta("corpse_probe_ran", true)
	get_tree().create_timer(40.0).timeout.connect(func(): get_tree().quit())
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	v.ui.visible = false
	var p: Node3D = v.player
	p.visible = false
	var spot := p.global_position
	var fwd := -p.global_basis.z
	var right := p.global_basis.x
	var cam := Camera3D.new()
	p.get_parent().add_child(cam)
	cam.global_position = spot - fwd * 1.0 + Vector3(0, 1.6, 0)
	cam.look_at(spot + fwd * float(String(v.args.get("dist", "6.0"))) + Vector3(0, 1.5, 0), Vector3.UP)
	cam.current = true
	var names := ["corpselight_dkblu", "corpselight_dkred", "corpselight_grnface", "corpselight_redskull", "corpselight_torch", "corpselight_whtprp"]
	for i in names.size():
		var path := "res://content/monsters/effects/%s/model.gltf" % names[i]
		var n := NifScene.new()
		n.timeline = true
		if not n.load_scene(path):
			continue
		p.get_parent().add_child(n)
		n.global_position = spot + fwd * float(String(v.args.get("dist", "6.0"))) + right * ((i - 2.5) * float(String(v.args.get("gap", "1.6")))) + Vector3(0, 1.4, 0)
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://corpselights_%s.png" % String(v.args.get("tag", "x")))
	get_tree().quit()
