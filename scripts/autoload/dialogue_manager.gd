extends Node
## DialogueManager — plays JSON-driven branching dialogue graphs.
##
## Autoloaded as `DialogueManager`. A graph is a dictionary of node id -> node.
## Each node:
##   { "speaker": String, "text": String,
##     "next": String|null,                     # linear node; null ends the graph
##     "choices": [ {"text": String, "next": String, "set_flag": {..}} ],
##     "set_flag": { "flag_name": value } }      # applied when the node is entered
##
## UI (dialogue_box.gd) listens to these signals; it does not read the graph.

signal dialogue_started
signal line_shown(speaker: String, text: String, choices: Array)
signal dialogue_finished

var _graph: Dictionary = {}
var _current_id: String = ""
var is_active: bool = false


func start(path: String, start_id: String = "start") -> bool:
	var graph := _load_graph(path)
	if graph.is_empty():
		return false
	_graph = graph
	is_active = true
	dialogue_started.emit()
	_goto(start_id)
	return true


## Advance a linear node (no choices). Ignored while choices are pending.
func advance() -> void:
	if not is_active:
		return
	var node: Dictionary = _graph.get(_current_id, {})
	if node.has("choices") and not (node["choices"] as Array).is_empty():
		return  # waiting on choose()
	var next: Variant = node.get("next", null)
	if next == null:
		_finish()
	else:
		_goto(str(next))


## Pick choice `index` on a choice node.
func choose(index: int) -> void:
	if not is_active:
		return
	var node: Dictionary = _graph.get(_current_id, {})
	var choices: Array = node.get("choices", [])
	if index < 0 or index >= choices.size():
		return
	var choice: Dictionary = choices[index]
	_apply_flags(choice.get("set_flag", {}))
	_apply_journal(choice.get("discover_log", null))
	var next: Variant = choice.get("next", null)
	if next == null:
		_finish()
	else:
		_goto(str(next))


func _goto(id: String) -> void:
	if not _graph.has(id):
		push_error("DialogueManager: missing node '%s'." % id)
		_finish()
		return
	_current_id = id
	var node: Dictionary = _graph[id]
	_apply_flags(node.get("set_flag", {}))
	_apply_journal(node.get("discover_log", null))
	line_shown.emit(
		str(node.get("speaker", "")),
		str(node.get("text", "")),
		node.get("choices", [])
	)


func _apply_flags(dict: Dictionary) -> void:
	for key in dict:
		GameState.set_flag(str(key), dict[key])



func _apply_journal(raw: Variant) -> void:
	var journal := get_node_or_null("/root/Journal")
	if journal == null:
		return
	if typeof(raw) == TYPE_STRING and not raw.is_empty():
		journal.discover(raw)
	elif typeof(raw) == TYPE_ARRAY:
		for entry_id in raw:
			if typeof(entry_id) == TYPE_STRING and not entry_id.is_empty():
				journal.discover(entry_id)

func _finish() -> void:
	is_active = false
	_graph = {}
	_current_id = ""
	dialogue_finished.emit()


func _load_graph(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("DialogueManager: dialogue file not found: %s" % path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DialogueManager: dialogue file is not a JSON object: %s" % path)
		return {}
	return parsed
