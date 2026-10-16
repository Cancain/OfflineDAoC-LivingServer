class_name HeadlessZone
extends ZoneLoader
## A zone for the world host (bot plan phase 4): no graphics - only what the monsters' simulation (NpcManager /
## NpcState) asks a ZoneLoader for: the zone's info, its height grid and water (height_at, water_level_at, city).
## Its collision is the host's own (ZoneWorld blocks), in the same physics world this node sits in.

func load_headless(content_dir: String) -> void:
	dir = content_dir
	info = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("zone.json")))
	city = bool(info.get("city", false))
	_load_heights()
