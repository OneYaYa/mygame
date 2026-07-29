extends Node

const SAVE_PATH: String = "user://time-echo-save-v1.json"
const ENDINGS_PATH: String = "user://time-echo-endings-v1.json"
const CURRENT_VERSION: int = 1


func has_save() -> bool:
	if FileAccess.file_exists(SAVE_PATH):
		return true
	return _import_legacy_web_save()


func save_game(state: Dictionary) -> bool:
	var payload: Dictionary = state.duplicate(true)
	payload["version"] = CURRENT_VERSION
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		var message: String = "无法写入存档：%s" % error_string(FileAccess.get_open_error())
		push_error(message)
		EventBus.save_failed.emit(message)
		return false
	file.store_string(JSON.stringify(payload, "\t", false))
	file.close()
	EventBus.save_completed.emit(SAVE_PATH)
	return true


func load_game() -> Dictionary:
	var raw: Dictionary = _load_json(SAVE_PATH)
	if raw.is_empty():
		return {}
	return _migrate(raw)


func record_ending(ending_id: String, loop_count: int) -> void:
	var endings: Array = load_endings()
	endings.append({
		"id": ending_id,
		"unix_time": int(Time.get_unix_time_from_system()),
		"loops": loop_count,
	})
	if endings.size() > 12:
		endings = endings.slice(endings.size() - 12)
	var file: FileAccess = FileAccess.open(ENDINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(endings, "\t", false))


func load_endings() -> Array:
	if not FileAccess.file_exists(ENDINGS_PATH):
		return []
	var file: FileAccess = FileAccess.open(ENDINGS_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Array if typeof(parsed) == TYPE_ARRAY else []


func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		push_error("存档 JSON 无效：%s" % path)
		return {}
	return parser.data as Dictionary


func _migrate(raw: Dictionary) -> Dictionary:
	var version: int = int(raw.get("version", 0))
	if version <= 0:
		raw["version"] = CURRENT_VERSION
	elif version > CURRENT_VERSION:
		push_warning("存档版本 %d 高于当前支持版本 %d，将以兼容模式读取" % [version, CURRENT_VERSION])
	return raw


func _import_legacy_web_save() -> bool:
	if not OS.has_feature("web"):
		return false
	var legacy: Variant = JavaScriptBridge.eval("localStorage.getItem('time-echo-save-v1') || ''", true)
	if typeof(legacy) != TYPE_STRING or str(legacy).is_empty():
		return false
	var parsed: Variant = JSON.parse_string(str(legacy))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("检测到旧 localStorage 存档，但 JSON 无效，未导入")
		return false
	var imported: Dictionary = _migrate(parsed as Dictionary)
	if save_game(imported):
		print("已把浏览器 localStorage 存档导入 user://")
		return true
	return false
