extends Node
## Debug (windowed): the vault window with its coin strip.   --screen 1 --skip-login --zone=200 --figure=cel_m --ui-test --probe=vault_shot --out=<folder>
func _ready() -> void:
	var v := get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	v.ui.vault.open_for("Vault Keeper")
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(String(v.args.get("out", "user://")) + "/vault.png")
	get_tree().quit()
