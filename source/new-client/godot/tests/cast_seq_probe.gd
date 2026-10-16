extends Node
## Debug: a full cast (start, the held loop for the cast time, the release when it lands) on your character and on a
## race-figure NPC - the clip playing every 0.25 s. --clips=cast_z (the casting style prefix)
##   --headless -- --skip-login --zone=200 "--at=Mag Mell" --figure=elf_m --ui-test --probe=cast_seq_probe
func _ready() -> void:
	var v := get_tree().current_scene
	var style := "cast_z"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			style = a.get_slice("=", 1)
	await get_tree().create_timer(5.0).timeout
	var npc: Npc = null
	for i in v.npcs.active:
		var a: Npc = v.npcs.active[i]
		if a.model is Fig3Figure:
			npc = a
			break
	var clips := [style + "_start", style + "_mid", style + "_end"]
	var p: Player = v.player
	p.cast_start(clips)
	if npc:
		npc.cast_start(clips, 2.5)
	var t := 0.0
	while t < 3.6:
		await get_tree().create_timer(0.25).timeout
		t += 0.25
		if is_equal_approx(t, 2.5):
			p.cast_end(true)
			if npc:
				npc.cast_end(true)
		print("[seq] t=%.2f player=%s npc=%s" % [t, p._anim.current_animation if p._anim else "-",
				npc.anim.current_animation if npc else "-"])
	get_tree().quit()
