extends Node

const WORLD_PATH: String = "res://data/world.json"
const MAPS_PATH: String = "res://data/maps.json"
const REQUIRED_SCENES: PackedStringArray = [
	"town", "inn-yard", "chapel-hill", "photo-lane", "archive-lane", "harbor",
	"clock-basement", "hidden-darkroom", "low-tide-cave"
]
const REQUIRED_NPCS: PackedStringArray = [
	"arthur", "beatrice", "conrad", "dorothea", "elias", "florence", "ada"
]

var world: Dictionary = {}
var maps: Dictionary = {}
var npcs_by_id: Dictionary = {}
var items_by_id: Dictionary = {}
var evidence_by_id: Dictionary = {}
var scenes_by_id: Dictionary = {}
var validation_errors: PackedStringArray = []
var loaded: bool = false


func _ready() -> void:
	load_all()


func load_all() -> bool:
	validation_errors.clear()
	world = _read_json(WORLD_PATH)
	maps = _read_json(MAPS_PATH)
	if world.is_empty() or maps.is_empty():
		loaded = false
		return false
	_index_content()
	_validate_world()
	_validate_maps()
	loaded = validation_errors.is_empty()
	if loaded:
		EventBus.data_loaded.emit()
	else:
		for message: String in validation_errors:
			push_error("TIME ECHO data: %s" % message)
	return loaded


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		validation_errors.append("资源不存在：%s" % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		validation_errors.append("无法打开：%s" % path)
		return {}
	var parser := JSON.new()
	var error: Error = parser.parse(file.get_as_text())
	if error != OK:
		validation_errors.append("JSON 解析失败 %s:%d：%s" % [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		validation_errors.append("JSON 根节点必须是对象：%s" % path)
		return {}
	return parser.data as Dictionary


func _index_content() -> void:
	npcs_by_id = _index_array(world.get("npcs", []), "world.npcs")
	items_by_id = _index_array(world.get("items", []), "world.items")
	evidence_by_id = _index_array(world.get("evidence", []), "world.evidence")
	var all_scenes: Array = []
	all_scenes.append_array(maps.get("regions", []))
	all_scenes.append_array(maps.get("places", []))
	scenes_by_id = _index_array(all_scenes, "maps scenes")


func _index_array(values: Variant, label: String) -> Dictionary:
	var result: Dictionary = {}
	if typeof(values) != TYPE_ARRAY:
		validation_errors.append("%s 必须是数组" % label)
		return result
	for raw: Variant in values:
		if typeof(raw) != TYPE_DICTIONARY:
			validation_errors.append("%s 含有非对象成员" % label)
			continue
		var value: Dictionary = raw as Dictionary
		var id: String = str(value.get("id", ""))
		if id.is_empty():
			validation_errors.append("%s 中有对象缺少稳定 id" % label)
		elif result.has(id):
			validation_errors.append("%s 中 id 重复：%s" % [label, id])
		else:
			result[id] = value
	return result


func _validate_world() -> void:
	if int(world.get("schemaVersion", 0)) != 1:
		validation_errors.append("world.json schemaVersion 不是受支持的 1")
	var game: Variant = world.get("game")
	if typeof(game) != TYPE_DICTIONARY:
		validation_errors.append("world.game 缺失")
	for npc_id: String in REQUIRED_NPCS:
		if not npcs_by_id.has(npc_id):
			validation_errors.append("缺少 NPC：%s" % npc_id)
	for npc_value: Variant in npcs_by_id.values():
		var npc: Dictionary = npc_value as Dictionary
		for field: String in ["name", "displayName", "role", "knowledge"]:
			if not npc.has(field):
				validation_errors.append("NPC %s 缺少字段 %s" % [npc.get("id", "?"), field])


func _validate_maps() -> void:
	if int(maps.get("schemaVersion", 0)) != 1:
		validation_errors.append("maps.json schemaVersion 不是受支持的 1")
	for scene_id: String in REQUIRED_SCENES:
		if not scenes_by_id.has(scene_id):
			validation_errors.append("缺少关键地点：%s" % scene_id)
	for scene_value: Variant in scenes_by_id.values():
		var scene: Dictionary = scene_value as Dictionary
		for field: String in ["width", "height", "name"]:
			if not scene.has(field):
				validation_errors.append("地点 %s 缺少字段 %s" % [scene.get("id", "?"), field])
		for portal_value: Variant in scene.get("portals", []):
			if typeof(portal_value) != TYPE_DICTIONARY:
				continue
			var portal: Dictionary = portal_value as Dictionary
			var target: String = str(portal.get("targetPlaceId", ""))
			if target.is_empty() or not scenes_by_id.has(target):
				validation_errors.append("传送点 %s 引用无效地点 %s" % [portal.get("id", "?"), target])
			if typeof(portal.get("spawn")) != TYPE_DICTIONARY:
				validation_errors.append("传送点 %s 缺少 spawn" % portal.get("id", "?"))


func get_scene_data(scene_id: String) -> Dictionary:
	return scenes_by_id.get(scene_id, {}) as Dictionary


func get_npc(npc_id: String) -> Dictionary:
	return npcs_by_id.get(npc_id, {}) as Dictionary


func get_item(item_id: String) -> Dictionary:
	return items_by_id.get(item_id, {}) as Dictionary


func get_evidence(evidence_id: String) -> Dictionary:
	return evidence_by_id.get(evidence_id, {}) as Dictionary


func get_game_config() -> Dictionary:
	return world.get("game", {}) as Dictionary


func get_story_context() -> Dictionary:
	return world.get("storyContext", {}) as Dictionary

