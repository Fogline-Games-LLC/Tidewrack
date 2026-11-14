extends Node
## GameState — global save/load and story flags.
##
## Autoloaded as `GameState`. Holds the narrative flags set by dialogue
## choices and persists them (along with Journal state) to user://save.json.

signal state_changed

const SAVE_PATH := "user://save.json"
const SAVE_TMP_PATH := "user://save.json.tmp"
const SAVE_BAK_PATH := "user://save.json.bak"
const SAVE_VERSION := 2
const DEFAULT_SCENE := "res://scenes/game.tscn"

## Story flags set during play, e.g. {"trusted_edith": true}.
var flags: Dictionary = {}
## Path of the scene the player should resume into.
var current_scene: String = DEFAULT_SCENE


func set_flag(name: String, value: Variant) -> void:
	flags[name] = value
	state_changed.emit()


func get_flag(name: String, default: Variant = false) -> Variant:
	return flags.get(name, default)


func new_game() -> void:
	flags.clear()
	current_scene = DEFAULT_SCENE
	var journal := get_node_or_null("/root/Journal")
	if journal != null:
		journal.clear()
	state_changed.emit()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or FileAccess.file_exists(SAVE_BAK_PATH)


func save_game() -> bool:
	var journal := get_node_or_null("/root/Journal")
	var journal_data: Dictionary = journal.serialize() if journal != null else {"entries": []}
	var payload := {
		"version": SAVE_VERSION,
		"scene": current_scene,
		"flags": flags.duplicate(true),
		"journal": journal_data,
	}

	var file := FileAccess.open(SAVE_TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameState: could not open temp save file for writing.")
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file.close()

	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(SAVE_BAK_PATH):
			DirAccess.remove_absolute(SAVE_BAK_PATH)
		DirAccess.rename_absolute(SAVE_PATH, SAVE_BAK_PATH)

	var err := DirAccess.rename_absolute(SAVE_TMP_PATH, SAVE_PATH)
	if err != OK:
		push_error("GameState: failed to finalize save file (err %d)." % err)
		return false
	return true


func load_game() -> bool:
	var data := _read_save_dict(SAVE_PATH)
	if data.is_empty() and FileAccess.file_exists(SAVE_BAK_PATH):
		push_warning("GameState: primary save unreadable, falling back to backup.")
		data = _read_save_dict(SAVE_BAK_PATH)
	if data.is_empty():
		return false

	var version := int(data.get("version", 1))
	var loaded_scene: Variant = data.get("scene", DEFAULT_SCENE)
	if typeof(loaded_scene) == TYPE_STRING and ResourceLoader.exists(loaded_scene):
		current_scene = loaded_scene
	else:
		current_scene = DEFAULT_SCENE

	var loaded_flags: Variant = data.get("flags", {})
	flags = loaded_flags.duplicate(true) if typeof(loaded_flags) == TYPE_DICTIONARY else {}

	var journal := get_node_or_null("/root/Journal")
	if journal != null:
		if version < 2:
			journal.clear()
		else:
			journal.deserialize(data.get("journal", {}))

	state_changed.emit()
	return true


func delete_save() -> void:
	for path in [SAVE_PATH, SAVE_TMP_PATH, SAVE_BAK_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _read_save_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
