extends Node
## Debug: the player's footstep contact times (CharacterSounds._find_contacts) - still found from the compressed
## clips in the packed figures (tools/pack_scenes.gd)?  --skip-login --zone=200 --figure=cel_m --ui-test --probe=steps_probe
func _ready() -> void:
	await get_tree().create_timer(3.0).timeout
	var v := get_tree().current_scene
	print("[steps] ", v.player.sounds.contacts_text() if v.player.sounds else "no sounds")
	get_tree().quit()
