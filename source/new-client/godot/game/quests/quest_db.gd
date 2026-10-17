class_name QuestDb
extends RefCounted
## The classic quests (pipeline/build_quests.py -> content/quests/quests.json): the old OfflineDAoC project's vetted
## DataQuest rows with their classic-quests.json additions (markers, custom steps, event monsters, the walkthroughs'
## keyword dialogue) and the owner's QUEST GUIDE texts. Data only - QuestEngine runs them.

const FILE := "res://content/quests/quests.json"

static var _data := {}
static var _by_giver := {}


static func _load() -> void:
	if not _data.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
	_data = parsed if parsed is Dictionary else {"quests": {}, "chat": {}, "guides": {}, "items": {}}
	for id in _data.quests:
		var q: Dictionary = _data.quests[id]
		var g := String(q.giver).to_lower()
		if not _by_giver.has(g):
			_by_giver[g] = []
		_by_giver[g].append(q)


static func quest(id: Variant) -> Dictionary:
	_load()
	return _data.quests.get(str(int(id)), {})


static func all() -> Dictionary:
	_load()
	return _data.quests


## A quest made in play (the companions' courier quest: Companions) - by its id, as the data's own.
static func add_runtime(q: Dictionary) -> void:
	_load()
	_data.quests[str(int(q.id))] = q


## The quests an NPC gives (by name, as DataQuest StartName).
static func by_giver(npc_name: String) -> Array:
	_load()
	return _by_giver.get(npc_name.to_lower(), [])


## The walkthroughs' keyword dialogue for an NPC: {keyword: reply}.
static func chat(npc_name: String) -> Dictionary:
	_load()
	for k in _data.chat:
		if String(k).to_lower() == npc_name.to_lower():
			return _data.chat[k]
	return {}


## The QUEST GUIDE text of a quest (period Allakhazam walkthrough): {source, updated, lines}.
static func guide(quest_name: String) -> Dictionary:
	_load()
	return _data.guides.get(quest_name, {})


## A quest item (letters, kill-task tokens, rewards) - ItemDb looks here after its own lists.
static func item(id: String) -> Dictionary:
	_load()
	return _data.items.get(id, {})


static func has_item(id: String) -> bool:
	_load()
	return _data.items.has(id)
