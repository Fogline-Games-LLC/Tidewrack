extends Node
## Journal — discovered-logs system.

signal entry_added(id: String)
signal entries_changed

var _entries: Array[String] = []


func discover(id: String) -> void:
	if id.is_empty() or id in _entries:
		return
	_entries.append(id)
	entry_added.emit(id)
	entries_changed.emit()


func entries() -> Array[String]:
	return _entries.duplicate()


func has(id: String) -> bool:
	return id in _entries


func clear() -> void:
	if _entries.is_empty():
		return
	_entries.clear()
	entries_changed.emit()


func serialize() -> Dictionary:
	return {
		"entries": _entries.duplicate(),
	}


func deserialize(data: Variant) -> void:
	_entries.clear()
	if typeof(data) == TYPE_DICTIONARY:
		var raw_entries: Variant = data.get("entries", [])
		if typeof(raw_entries) == TYPE_ARRAY:
			for item in raw_entries:
				if typeof(item) == TYPE_STRING and not item.is_empty() and not (item in _entries):
					_entries.append(item)
	entries_changed.emit()
