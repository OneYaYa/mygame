class_name TimeEchoArtCatalog
extends RefCounted

const MANIFEST_PATH: String = "res://data/art_manifest.json"
const ATLAS_SEMANTICS_PATH: String = "res://data/art_atlas_semantics.json"
const VALID_CATEGORIES: PackedStringArray = [
	"building", "character", "furniture", "decoration", "landmark",
	"architecture", "wall_decoration",
	"ground_texture", "path_texture", "water_texture", "wall_texture",
	"floor_texture", "effect", "ui", "concept_only",
]

var assets_by_id: Dictionary = {}
var tile_semantics_by_asset: Dictionary = {}
var errors: PackedStringArray = []
var _textures: Dictionary = {}
var _atlas_tiles: Dictionary = {}


func load_catalog() -> bool:
	assets_by_id.clear()
	tile_semantics_by_asset.clear()
	errors.clear()
	_textures.clear()
	_atlas_tiles.clear()
	var document: Dictionary = _read_json(MANIFEST_PATH)
	if document.is_empty():
		return false
	if int(document.get("schema_version", 0)) != 1:
		errors.append("Unsupported art manifest schema_version")
	var values: Variant = document.get("assets", [])
	if typeof(values) != TYPE_ARRAY:
		errors.append("art_manifest.assets must be an array")
		return false
	for value: Variant in values:
		if typeof(value) != TYPE_DICTIONARY:
			errors.append("art_manifest contains a non-object entry")
			continue
		var entry: Dictionary = value as Dictionary
		var asset_id: String = str(entry.get("asset_id", ""))
		if asset_id.is_empty():
			errors.append("art_manifest entry is missing asset_id")
			continue
		if assets_by_id.has(asset_id):
			errors.append("Duplicate art asset_id: %s" % asset_id)
			continue
		var category: String = str(entry.get("category", ""))
		if category not in VALID_CATEGORIES:
			errors.append("Invalid art category for %s: %s" % [asset_id, category])
		var display_size: Variant = entry.get("recommended_display_size", [])
		if typeof(display_size) != TYPE_ARRAY or (display_size as Array).size() != 2:
			errors.append("Invalid recommended_display_size for %s" % asset_id)
		if entry.has("tile_size") or entry.has("atlas_grid"):
			_validate_atlas_metadata(asset_id, entry)
		var runtime_path: String = str(entry.get("runtime_path", ""))
		if bool(entry.get("enabled", true)) and not runtime_path.is_empty() and not ResourceLoader.exists(runtime_path):
			errors.append("Missing enabled art resource %s: %s" % [asset_id, runtime_path])
		assets_by_id[asset_id] = entry
	_load_atlas_semantics()
	return errors.is_empty()


func get_asset(asset_id: String) -> Dictionary:
	return assets_by_id.get(asset_id, {}) as Dictionary


func get_texture(asset_id: String) -> Texture2D:
	if asset_id.is_empty():
		return null
	if _textures.has(asset_id):
		return _textures[asset_id] as Texture2D
	var entry: Dictionary = get_asset(asset_id)
	var texture: Texture2D = null
	if not entry.is_empty() and bool(entry.get("enabled", true)):
		var path: String = str(entry.get("runtime_path", ""))
		if ResourceLoader.exists(path):
			texture = load(path) as Texture2D
		else:
			_append_unique_error("Unable to load art texture %s: %s" % [asset_id, path])
	_textures[asset_id] = texture
	return texture


func display_size(asset_id: String) -> Vector2i:
	var values: Array = get_asset(asset_id).get("recommended_display_size", [24, 24]) as Array
	return Vector2i(int(values[0]), int(values[1])) if values.size() == 2 else Vector2i(24, 24)


func tile_size(asset_id: String) -> Vector2i:
	var values: Array = get_asset(asset_id).get("tile_size", []) as Array
	return Vector2i(int(values[0]), int(values[1])) if values.size() == 2 else Vector2i.ZERO


func atlas_grid(asset_id: String) -> Vector2i:
	var values: Array = get_asset(asset_id).get("atlas_grid", []) as Array
	return Vector2i(int(values[0]), int(values[1])) if values.size() == 2 else Vector2i.ZERO


func tile_count(asset_id: String) -> int:
	var grid: Vector2i = atlas_grid(asset_id)
	return grid.x * grid.y


func get_atlas_tile(asset_id: String, tile_index: int) -> Texture2D:
	var key: String = "%s:%d" % [asset_id, tile_index]
	if _atlas_tiles.has(key):
		return _atlas_tiles[key] as Texture2D
	var size: Vector2i = tile_size(asset_id)
	var grid: Vector2i = atlas_grid(asset_id)
	if size == Vector2i.ZERO or grid == Vector2i.ZERO or tile_index < 0 or tile_index >= grid.x * grid.y:
		_append_unique_error("Invalid atlas tile %s[%d]" % [asset_id, tile_index])
		return null
	var texture: Texture2D = get_texture(asset_id)
	if texture == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2i(Vector2i(tile_index % grid.x, tile_index / grid.x) * size, size)
	_atlas_tiles[key] = atlas
	return atlas


func tile_index(asset_id: String, tile_name: String) -> int:
	var atlas: Dictionary = tile_semantics_by_asset.get(asset_id, {}) as Dictionary
	var tiles: Dictionary = atlas.get("tiles", {}) as Dictionary
	if not tiles.has(tile_name):
		_append_unique_error("Unknown atlas semantic %s.%s" % [asset_id, tile_name])
		return -1
	return int(tiles[tile_name])


func get_named_tile(asset_id: String, tile_name: String) -> Texture2D:
	var index: int = tile_index(asset_id, tile_name)
	return get_atlas_tile(asset_id, index) if index >= 0 else null


func get_named_tile_image(asset_id: String, tile_name: String) -> Image:
	var index: int = tile_index(asset_id, tile_name)
	var size: Vector2i = tile_size(asset_id)
	var grid: Vector2i = atlas_grid(asset_id)
	var texture: Texture2D = get_texture(asset_id)
	if index < 0 or size == Vector2i.ZERO or grid == Vector2i.ZERO or texture == null:
		return null
	var atlas_image: Image = texture.get_image()
	if atlas_image == null or atlas_image.is_empty():
		_append_unique_error("Unable to read atlas image: %s" % asset_id)
		return null
	var origin := Vector2i(index % grid.x, floori(float(index) / float(grid.x))) * size
	return atlas_image.get_region(Rect2i(origin, size))


func get_atlas_semantics(asset_id: String) -> Dictionary:
	return tile_semantics_by_asset.get(asset_id, {}) as Dictionary


func is_tile_marked_unsafe(asset_id: String, tile_name: String) -> bool:
	var index: int = tile_index(asset_id, tile_name)
	if index < 0:
		return true
	var atlas: Dictionary = get_atlas_semantics(asset_id)
	var values: Array = atlas.get("unsafe_tiles", []) as Array
	for value: Variant in values:
		if int(value) == index:
			return true
	return false


func _validate_atlas_metadata(asset_id: String, entry: Dictionary) -> void:
	var size_values: Variant = entry.get("tile_size", [])
	var grid_values: Variant = entry.get("atlas_grid", [])
	if typeof(size_values) != TYPE_ARRAY or (size_values as Array).size() != 2:
		errors.append("Invalid tile_size for %s" % asset_id)
		return
	if typeof(grid_values) != TYPE_ARRAY or (grid_values as Array).size() != 2:
		errors.append("Invalid atlas_grid for %s" % asset_id)
		return
	var size := Vector2i(int((size_values as Array)[0]), int((size_values as Array)[1]))
	var grid := Vector2i(int((grid_values as Array)[0]), int((grid_values as Array)[1]))
	if size.x <= 0 or size.y <= 0 or grid.x <= 0 or grid.y <= 0:
		errors.append("Non-positive atlas metadata for %s" % asset_id)
		return
	var expected: Vector2i = size * grid
	var display_values: Array = entry.get("recommended_display_size", []) as Array
	if display_values.size() == 2 and expected != Vector2i(int(display_values[0]), int(display_values[1])):
		errors.append("Atlas size mismatch for %s: %s != %s" % [asset_id, expected, display_values])


func _load_atlas_semantics() -> void:
	var document: Dictionary = _read_json(ATLAS_SEMANTICS_PATH)
	if document.is_empty():
		return
	if int(document.get("schema_version", 0)) != 1:
		errors.append("Unsupported art atlas semantics schema_version")
	var atlases_value: Variant = document.get("atlases", {})
	if typeof(atlases_value) != TYPE_DICTIONARY:
		errors.append("art_atlas_semantics.atlases must be an object")
		return
	for asset_value: Variant in (atlases_value as Dictionary).keys():
		var asset_id: String = str(asset_value)
		if not assets_by_id.has(asset_id):
			errors.append("Atlas semantics references unknown asset: %s" % asset_id)
			continue
		var atlas: Dictionary = (atlases_value as Dictionary)[asset_value] as Dictionary
		var manifest_size: Vector2i = tile_size(asset_id)
		var manifest_grid: Vector2i = atlas_grid(asset_id)
		var size_values: Array = atlas.get("tile_size", []) as Array
		var grid_values: Array = atlas.get("grid", []) as Array
		if size_values.size() != 2 or Vector2i(int(size_values[0]), int(size_values[1])) != manifest_size:
			errors.append("Atlas semantic tile_size mismatch: %s" % asset_id)
		if grid_values.size() != 2 or Vector2i(int(grid_values[0]), int(grid_values[1])) != manifest_grid:
			errors.append("Atlas semantic grid mismatch: %s" % asset_id)
		var tiles_value: Variant = atlas.get("tiles", {})
		if typeof(tiles_value) != TYPE_DICTIONARY:
			errors.append("Atlas semantic tiles must be an object: %s" % asset_id)
			continue
		for name_value: Variant in (tiles_value as Dictionary).keys():
			var index: int = int((tiles_value as Dictionary)[name_value])
			if index < 0 or index >= tile_count(asset_id):
				errors.append("Atlas semantic index out of range: %s.%s=%d" % [asset_id, name_value, index])
		tile_semantics_by_asset[asset_id] = atlas


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		errors.append("Missing art catalog: %s" % path)
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Unable to open art catalog: %s" % path)
		return {}
	var parser := JSON.new()
	var result: Error = parser.parse(file.get_as_text())
	if result != OK or typeof(parser.data) != TYPE_DICTIONARY:
		errors.append("Invalid JSON in %s at line %d: %s" % [path, parser.get_error_line(), parser.get_error_message()])
		return {}
	return parser.data as Dictionary


func _append_unique_error(message: String) -> void:
	if message not in errors:
		errors.append(message)
