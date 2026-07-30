class_name TimeEchoArtLayoutCatalog
extends RefCounted

const LAYOUT_ROOT: String = "res://data/art_layouts"
const REQUIRED_MAPS: PackedStringArray = [
	"town", "inn-yard", "chapel-hill", "photo-lane", "archive-lane", "harbor",
	"player-room", "inn-lobby", "inn-upstairs", "clock-cabin", "chapel-interior",
	"chapel-belfry", "photo-studio", "archive-room", "harbor-control",
	"low-tide-cave", "clock-basement", "hidden-darkroom",
]

var layouts_by_id: Dictionary = {}
var errors: PackedStringArray = []


func load_catalog() -> bool:
	layouts_by_id.clear()
	errors.clear()
	for map_id: String in REQUIRED_MAPS:
		_load_layout(map_id)
	return errors.is_empty()


func get_layout(map_id: String) -> Dictionary:
	return layouts_by_id.get(map_id, {}) as Dictionary


func _load_layout(expected_map_id: String) -> void:
	var path: String = "%s/%s.json" % [LAYOUT_ROOT, expected_map_id]
	if not FileAccess.file_exists(path):
		errors.append("Missing art layout: %s" % path)
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Unable to open art layout: %s" % path)
		return
	var parser := JSON.new()
	var parse_error: Error = parser.parse(file.get_as_text())
	if parse_error != OK or typeof(parser.data) != TYPE_DICTIONARY:
		errors.append("Invalid art layout JSON %s:%d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return
	var layout: Dictionary = parser.data as Dictionary
	var map_id: String = str(layout.get("map_id", ""))
	if map_id != expected_map_id:
		errors.append("Art layout map_id mismatch: %s != %s" % [map_id, expected_map_id])
		return
	if int(layout.get("schema_version", 0)) != 1:
		errors.append("Unsupported art layout schema for %s" % map_id)
	var ids: Dictionary = {}
	for group: String in ["ground_shapes", "objects", "collision_rects", "lights", "zones"]:
		var values: Variant = layout.get(group, [])
		if typeof(values) != TYPE_ARRAY:
			errors.append("%s.%s must be an array" % [map_id, group])
			continue
		for value: Variant in values:
			if typeof(value) != TYPE_DICTIONARY:
				errors.append("%s.%s contains non-object data" % [map_id, group])
				continue
			var object_id: String = str((value as Dictionary).get("object_id", ""))
			if object_id.is_empty():
				errors.append("%s.%s object is missing stable object_id" % [map_id, group])
			elif ids.has(object_id):
				errors.append("Duplicate art object_id in %s: %s" % [map_id, object_id])
			else:
				ids[object_id] = true
	layouts_by_id[map_id] = layout

