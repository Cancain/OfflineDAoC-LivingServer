extends Node
## Debug: the journal's QUEST GUIDE button opens the guide for the highlighted quest (owner 2026-10-09).
##   --headless --skip-login --zone=8 --realm=alb --ui-test --probe=guide_probe
var viewer: Node


func _ready() -> void:
	viewer = get_tree().current_scene
	await get_tree().create_timer(5.0).timeout
	PlayerData.quests["20205"] = {"step": 1}
	var j = viewer.ui.journal
	j.show_window()
	j.selected = "20205"
	j.refresh()
	await get_tree().process_frame
	j._guide.pressed.emit()
	await get_tree().process_frame
	var g: ClassicWindow = viewer.ui.guide
	print("[guide] visible ", g.visible, " at ", g.position, " size ", g.size, " screen ", g.get_parent_area_size(),
			" above journal ", g.get_index() > j.get_index())
	print("[guide] title ", (g.get_node("Title") as Label).text)
	print("[guide] body ", (g.get_node("Body") as RichTextLabel).get_parsed_text().substr(0, 300))
	get_tree().quit()
