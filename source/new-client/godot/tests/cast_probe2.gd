extends Node
## Debug: a monster casting with its own anim set's clips (monsters.json cast_clips): the clip it plays at the start,
## while holding the cast, and when the spell lands.
##   --headless -- --skip-login --zone=200 "--at=Mag Mell" --figure=cel_m --ui-test --probe=cast_probe2
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	var n: Npc = null
	for i in v.npcs.active:
		var a: Npc = v.npcs.active[i]
		if a.info.has("cast_clips") and a.anim and String(a.info.cast_clips.get("cast_bk_hand_start", "")).begins_with("cast_k_"):
			n = a
			break
	if n == null:
		print("[cast] no monster with cast clips nearby")
		get_tree().quit()
		return
	n.cast_start(["cast_bk_hand_start", "cast_bk_hand_mid", "cast_bk_hand_end"], 2.0)
	print("[cast] ", n.spawn.name, " maps: ", n.info.cast_clips.get("cast_bk_hand_start"), " start: ", n.anim.current_animation)
	await get_tree().create_timer(1.5).timeout
	print("[cast] holding: ", n.anim.current_animation)
	n.cast_end(true)
	print("[cast] landed: ", n.anim.current_animation)
	get_tree().quit()
