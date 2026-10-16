extends Node
## Debug (owner 2026-10-14: make sure the vault works on the server): a jump to Tir na Nog's vault keepers, then
## vault_run.gd right-clicks the Vault Keeper and the Account Vault Keeper. Runs once (the jump rebuilds the scene).
func _ready() -> void:
	if get_tree().root.has_meta("vault_probe_ran"):
		return
	get_tree().root.set_meta("vault_probe_ran", true)
	await get_tree().create_timer(8.0).timeout
	var helper := Node.new()
	helper.set_script(load("res://tests/vault_run.gd"))
	get_tree().root.add_child(helper)
	Server.command("/jump to 33330 31730 8000 201")
