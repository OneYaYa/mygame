class_name TimeEchoArtTileLayerBuilder
extends RefCounted

var warnings: PackedStringArray = []
var generated_tile_count: int = 0
var _catalog: TimeEchoArtCatalog
var _parents: Dictionary = {}
var _scene: Dictionary = {}
var _layout: Dictionary = {}
var _cell_size := Vector2i(32, 32)


func rebuild(scene: Dictionary, layout: Dictionary, catalog: TimeEchoArtCatalog, parents: Dictionary) -> PackedStringArray:
	warnings.clear()
	generated_tile_count = 0
	_scene = scene
	_layout = layout
	_catalog = catalog
	_parents = parents
	_clear_generated_nodes()
	var config: Dictionary = layout.get("atlas_tile_art", {}) as Dictionary
	if config.is_empty():
		return warnings
	_cell_size = _vector2i(config.get("cell_size", [32, 32]), Vector2i(32, 32))
	var occupied := {}
	for value: Variant in config.get("terrain_masks", []):
		var entry: Dictionary = value as Dictionary
		var mask: Dictionary = _mask_from_entry(entry)
		occupied.merge(mask, true)
	for value: Variant in config.get("water_masks", []):
		var entry: Dictionary = value as Dictionary
		var mask: Dictionary = _mask_from_entry(entry)
		occupied.merge(mask, true)
	_build_base(config.get("base_fill", {}) as Dictionary, occupied)
	for value: Variant in config.get("water_masks", []):
		_build_water(value as Dictionary)
	for value: Variant in config.get("terrain_masks", []):
		_build_terrain(value as Dictionary)
	for value: Variant in config.get("shore_stamps", []):
		var stamp: Dictionary = value as Dictionary
		if stamp.has("position"):
			_add_pixel_tile(str(stamp.get("layer", "ShoreTiles")), str(stamp.get("asset_id", "")), str(stamp.get("tile", "")), _vector2i(stamp.get("position", [0, 0]), Vector2i.ZERO), _color(stamp.get("tint", "#ffffff"), Color.WHITE))
		else:
			_add_cell_tile(str(stamp.get("layer", "ShoreTiles")), str(stamp.get("asset_id", "")), str(stamp.get("tile", "")), _vector2i(stamp.get("cell", [0, 0]), Vector2i.ZERO), _color(stamp.get("tint", "#ffffff"), Color.WHITE))
	_build_interior(config.get("interior_shell", {}) as Dictionary)
	return warnings


func _clear_generated_nodes() -> void:
	for parent_value: Variant in _parents.values():
		var parent: Node2D = parent_value as Node2D
		if parent == null:
			continue
		for child: Node in parent.get_children():
			child.free()


func _build_base(config: Dictionary, occupied: Dictionary) -> void:
	if config.is_empty():
		return
	var asset_id: String = str(config.get("asset_id", ""))
	var base_tiles: Array = config.get("base_tiles", []) as Array
	var variation_tiles: Array = config.get("variation_tiles", []) as Array
	if base_tiles.is_empty():
		warnings.append("Base tile list is empty: %s" % asset_id)
		return
	var columns: int = ceili(float(_scene.get("width", 768)) / float(_cell_size.x))
	var rows: int = ceili(float(_scene.get("height", 480)) / float(_cell_size.y))
	var normal_ratio: float = clampf(float(config.get("variation_ratio", 0.10)), 0.0, 1.0)
	var edge_ratio: float = clampf(float(config.get("edge_variation_ratio", normal_ratio)), 0.0, 1.0)
	var avoid_radius: int = maxi(0, int(config.get("avoid_radius", 1)))
	var seed: String = str(config.get("seed", _scene.get("id", "map")))
	for y: int in range(rows):
		for x: int in range(columns):
			var cell := Vector2i(x, y)
			var near_feature: bool = _is_near_mask(cell, occupied, avoid_radius)
			var map_edge: bool = x < 2 or y < 2 or x >= columns - 2 or y >= rows - 2
			var ratio: float = 0.0 if near_feature else (edge_ratio if map_edge else normal_ratio)
			var names: Array = variation_tiles if not variation_tiles.is_empty() and _unit_roll(seed, cell, "variation") < ratio else base_tiles
			var tile_name: String = str(names[_roll(seed, cell, "choice") % names.size()])
			_add_cell_tile("BaseTiles", asset_id, tile_name, cell)


func _build_terrain(config: Dictionary) -> void:
	var asset_id: String = str(config.get("asset_id", ""))
	var layer: String = str(config.get("layer", "PathTiles"))
	var mask: Dictionary = _mask_from_entry(config)
	var seed: String = str(config.get("seed", config.get("mask_id", asset_id)))
	var centers: Array = config.get("center_tiles", ["center_a"]) as Array
	for cell_value: Variant in mask.keys():
		var cell: Vector2i = cell_value as Vector2i
		var zone: Dictionary = _terrain_zone_for_cell(config, cell)
		var cell_centers: Array = zone.get("center_tiles", centers) as Array
		var tile_name: String = _terrain_semantic(mask, cell, cell_centers, seed)
		var prefix: String = str(zone.get("semantic_prefix", ""))
		if not prefix.is_empty() and tile_name != "center_a" and not tile_name.begins_with("center_"):
			tile_name = "%s_%s" % [prefix, tile_name]
		var tint: Color = _color(zone.get("tint", config.get("tint", "#ffffff")), Color.WHITE)
		_add_cell_tile(layer, asset_id, tile_name, cell, tint)
	var edge_distribution: Dictionary = config.get("edge_distribution", {}) as Dictionary
	if not edge_distribution.is_empty():
		_build_terrain_edge_details(config, mask, edge_distribution, seed, layer, asset_id)
		return
	var intrusion: Dictionary = config.get("grass_intrusion", {}) as Dictionary
	if intrusion.is_empty():
		return
	var density: float = clampf(float(intrusion.get("density", 0.10)), 0.0, 1.0)
	var intrusion_asset: String = str(intrusion.get("asset_id", "grass_path_edge_set"))
	var intrusion_seed: String = str(intrusion.get("seed", "%s:intrusion" % seed))
	for cell_value: Variant in mask.keys():
		var cell: Vector2i = cell_value as Vector2i
		if _unit_roll(intrusion_seed, cell, "density") >= density:
			continue
		var directions: Array[String] = _outside_cardinals(mask, cell)
		if directions.is_empty():
			continue
		var direction: String = directions[_roll(intrusion_seed, cell, "side") % directions.size()]
		_add_cell_tile(layer, intrusion_asset, "intrusion_%s" % direction.left(1), cell)


func _terrain_zone_for_cell(config: Dictionary, cell: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	for value: Variant in config.get("material_zones", []):
		var zone: Dictionary = value as Dictionary
		for rect_value: Variant in zone.get("rects", []):
			var values: Array = rect_value as Array
			if values.size() != 4:
				continue
			var rect := Rect2i(int(values[0]), int(values[1]), int(values[2]), int(values[3]))
			if rect.has_point(cell):
				result = zone
	return result


func _build_terrain_edge_details(config: Dictionary, mask: Dictionary, distribution: Dictionary, seed: String, layer: String, asset_id: String) -> void:
	var clean_ratio: float = clampf(float(distribution.get("clean", 0.60)), 0.0, 1.0)
	var grass_ratio: float = clampf(float(distribution.get("grass", 0.25)), 0.0, 1.0)
	var broken_ratio: float = clampf(float(distribution.get("broken", 0.10)), 0.0, 1.0)
	var special_ratio: float = clampf(float(distribution.get("special", 0.05)), 0.0, 1.0)
	var total: float = maxf(0.001, clean_ratio + grass_ratio + broken_ratio + special_ratio)
	clean_ratio /= total
	grass_ratio /= total
	broken_ratio /= total
	var grass_asset: String = str(distribution.get("grass_asset", "grass_path_edge_set"))
	var detail_seed: String = str(distribution.get("seed", "%s:edge-details" % seed))
	for cell_value: Variant in mask.keys():
		var cell: Vector2i = cell_value as Vector2i
		var directions: Array[String] = _outside_cardinals(mask, cell)
		if directions.is_empty():
			continue
		var direction: String = directions[_roll(detail_seed, cell, "side") % directions.size()]
		var value: float = _unit_roll(detail_seed, cell, "style")
		if value < clean_ratio:
			continue
		if value < clean_ratio + grass_ratio:
			_add_cell_tile(layer, grass_asset, "intrusion_%s" % direction.left(1), cell)
		elif value < clean_ratio + grass_ratio + broken_ratio:
			_add_cell_tile(layer, asset_id, "broken_edge_%s" % direction.left(1), cell)
		else:
			# The special five percent stays sparse: alternate grass tips and a
			# broken lip without introducing a per-cell rhythm.
			if _roll(detail_seed, cell, "special") % 2 == 0:
				_add_cell_tile(layer, grass_asset, "intrusion_%s" % direction.left(1), cell)
			else:
				_add_cell_tile(layer, asset_id, "broken_edge_%s" % direction.left(1), cell)


func _build_water(config: Dictionary) -> void:
	var asset_id: String = str(config.get("asset_id", "water_shallow_deep_set"))
	var mask: Dictionary = _mask_from_entry(config)
	var seed: String = str(config.get("seed", config.get("mask_id", asset_id)))
	var shallow: Array = config.get("shallow_tiles", ["shallow_a", "shallow_b", "shallow_c", "shallow_d"]) as Array
	var deep: Array = config.get("deep_tiles", ["deep_a", "deep_b", "deep_c", "deep_d"]) as Array
	var highlights: Array = config.get("highlight_tiles", ["deep_highlight_a", "deep_highlight_b", "deep_highlight_c", "deep_highlight_d"]) as Array
	var use_transitions: bool = bool(config.get("use_transitions", false))
	var transition_asset: String = str(config.get("transition_asset", asset_id))
	var boundary_asset: String = str(config.get("boundary_asset", asset_id))
	var boundary_tiles: Array = config.get("boundary_tiles", shallow) as Array
	var deep_intrusion_ratio: float = clampf(float(config.get("deep_intrusion_ratio", 0.0)), 0.0, 1.0)
	var highlight_ratio: float = clampf(float(config.get("highlight_ratio", 0.06)), 0.0, 1.0)
	if not str(config.get("polygon_shape_id", "")).is_empty():
		_build_polygon_water(config, mask, asset_id, shallow, deep, highlights, highlight_ratio, seed)
		if bool(config.get("auto_shore", false)):
			_build_shore(config, mask)
		return
	for cell_value: Variant in mask.keys():
		var cell: Vector2i = cell_value as Vector2i
		var outside: Array[String] = _water_outside_cardinals(mask, cell, config)
		var boundary: bool = not outside.is_empty()
		var tile_name: String
		var tile_asset: String = asset_id
		if boundary:
			tile_asset = boundary_asset
			tile_name = str(boundary_tiles[_roll(seed, cell, "boundary") % boundary_tiles.size()])
		elif use_transitions:
			var transition_directions: Array[String] = _transition_directions(mask, cell, config)
			if transition_directions.size() >= 2:
				var corner: String = _corner_suffix(transition_directions)
				if not corner.is_empty():
					tile_asset = transition_asset
					tile_name = "shallow_to_deep_outer_%s" % corner
				else:
					tile_name = str(deep[_roll(seed, cell, "deep") % deep.size()])
			elif transition_directions.size() == 1:
				tile_asset = transition_asset
				var direction: String = transition_directions[0].left(1)
				var variant: String = "a" if _roll(seed, cell, "transition_variant") % 2 == 0 else "b"
				tile_name = "shallow_to_deep_%s_%s" % [direction, variant]
			else:
				if deep_intrusion_ratio > 0.0 and _unit_roll(seed, cell, "deep_intrusion") < deep_intrusion_ratio:
					tile_asset = transition_asset
					tile_name = "deep_intrusion_%s" % ("a" if _roll(seed, cell, "deep_intrusion_variant") % 2 == 0 else "b")
				else:
					tile_name = str(deep[_roll(seed, cell, "deep") % deep.size()])
		else:
			tile_name = str(deep[_roll(seed, cell, "deep") % deep.size()])
		if tile_asset == asset_id and not boundary and not tile_name.begins_with("shallow_to_deep_") and not tile_name.begins_with("transition_corner_") and not highlights.is_empty() and _unit_roll(seed, cell, "highlight") < highlight_ratio:
			tile_name = str(highlights[_roll(seed, cell, "highlight_choice") % highlights.size()])
		_add_cell_tile(str(config.get("layer", "WaterTiles")), tile_asset, tile_name, cell, _color(config.get("tint", "#ffffff"), Color.WHITE))
	if bool(config.get("auto_shore", true)):
		_build_shore(config, mask)


func _build_polygon_water(config: Dictionary, mask: Dictionary, asset_id: String, shallow: Array, deep: Array, highlights: Array, highlight_ratio: float, seed: String) -> void:
	var width: int = int(_scene.get("width", 768))
	var height: int = int(_scene.get("height", 480))
	var columns: int = ceili(float(width) / float(_cell_size.x))
	var rows: int = ceili(float(height) / float(_cell_size.y))
	var shallow_composed := Image.create(columns * _cell_size.x, rows * _cell_size.y, false, Image.FORMAT_RGBA8)
	var deep_composed := Image.create(columns * _cell_size.x, rows * _cell_size.y, false, Image.FORMAT_RGBA8)
	shallow_composed.fill(Color(0, 0, 0, 0))
	deep_composed.fill(Color(0, 0, 0, 0))
	for y: int in range(rows):
		for x: int in range(columns):
			var cell := Vector2i(x, y)
			var shallow_name: String = str(shallow[_roll(seed, cell, "shallow") % shallow.size()])
			var deep_name: String = str(deep[_roll(seed, cell, "deep") % deep.size()])
			var shallow_image: Image = _catalog.get_named_tile_image(asset_id, shallow_name)
			var deep_image: Image = _catalog.get_named_tile_image(asset_id, deep_name)
			if shallow_image == null or shallow_image.is_empty() or deep_image == null or deep_image.is_empty():
				warnings.append("Unable to compose named water tile: %s.%s/%s" % [asset_id, shallow_name, deep_name])
				continue
			if not highlights.is_empty() and _unit_roll(seed, cell, "highlight") < highlight_ratio:
				var highlight_name: String = str(highlights[_roll(seed, cell, "highlight_choice") % highlights.size()])
				var highlight_image: Image = _catalog.get_named_tile_image(asset_id, highlight_name)
				if highlight_image != null and not highlight_image.is_empty():
					deep_image = _merge_highlight_pixels(deep_image, highlight_image)
			shallow_composed.blit_rect(shallow_image, Rect2i(Vector2i.ZERO, _cell_size), cell * _cell_size)
			deep_composed.blit_rect(deep_image, Rect2i(Vector2i.ZERO, _cell_size), cell * _cell_size)
			generated_tile_count += 2
	var shape: Dictionary = _ground_shape(str(config.get("polygon_shape_id", "")))
	var polygon: PackedVector2Array = _points(shape.get("points", []))
	if polygon.size() < 3:
		warnings.append("Polygon water shape is missing: %s" % config.get("polygon_shape_id", "?"))
		return
	var parent: Node2D = _parents.get(str(config.get("layer", "WaterTiles"))) as Node2D
	if parent == null:
		warnings.append("Missing polygon water parent")
		return
	var shore := Polygon2D.new()
	shore.name = "%s__shore_base" % config.get("mask_id", "water")
	shore.polygon = polygon
	shore.color = _color(config.get("shore_base_color", shape.get("shore_color", "#74806e")), Color("74806e"))
	shore.z_index = 0
	parent.add_child(shore)
	var water_polygon: PackedVector2Array = _points(config.get("water_polygon_points", []))
	if water_polygon.size() < 3:
		water_polygon = _scale_polygon(polygon, float(config.get("inset_factor", 0.97)))
	var water := Polygon2D.new()
	water.name = "%s__shallow_texture" % config.get("mask_id", "water")
	water.polygon = water_polygon
	water.uv = water_polygon
	water.texture = ImageTexture.create_from_image(shallow_composed)
	water.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	water.z_index = 1
	water.color = _color(config.get("tint", "#ffffff"), Color.WHITE)
	parent.add_child(water)
	var deep_polygon: PackedVector2Array = _points(config.get("deep_polygon_points", []))
	if deep_polygon.size() < 3:
		deep_polygon = _scale_polygon(water_polygon, float(config.get("deep_inset_factor", 0.78)))
	var deep_water := Polygon2D.new()
	deep_water.name = "%s__deep_texture" % config.get("mask_id", "water")
	deep_water.polygon = deep_polygon
	deep_water.uv = deep_polygon
	deep_water.texture = ImageTexture.create_from_image(deep_composed)
	deep_water.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	deep_water.z_index = 2
	deep_water.color = _color(config.get("tint", "#ffffff"), Color.WHITE)
	parent.add_child(deep_water)


func _merge_highlight_pixels(base: Image, highlight: Image) -> Image:
	var merged: Image = base.duplicate()
	for y: int in range(mini(base.get_height(), highlight.get_height())):
		for x: int in range(mini(base.get_width(), highlight.get_width())):
			var base_color: Color = base.get_pixel(x, y)
			var highlight_color: Color = highlight.get_pixel(x, y)
			if highlight_color.get_luminance() > base_color.get_luminance() + 0.055:
				merged.set_pixel(x, y, highlight_color)
	return merged


func _build_shore(config: Dictionary, mask: Dictionary) -> void:
	var shore_asset: String = str(config.get("shore_asset", ""))
	if shore_asset.is_empty():
		return
	var default_material: String = str(config.get("shore_material", "grass"))
	for cell_value: Variant in mask.keys():
		var cell: Vector2i = cell_value as Vector2i
		var outside: Array[String] = _water_outside_cardinals(mask, cell, config)
		var suffix: String = ""
		if outside.size() >= 2:
			var corner: String = _corner_suffix(outside)
			if not corner.is_empty():
				suffix = "outer_corner_%s" % corner
		elif outside.size() == 1:
			suffix = "edge_%s" % outside[0].left(1)
		else:
			var diagonal: String = _missing_diagonal(mask, cell, config)
			if not diagonal.is_empty():
				suffix = "inner_corner_%s" % diagonal
		if suffix.is_empty():
			continue
		var material: String = _shore_material(config, cell, default_material)
		_add_cell_tile("ShoreTiles", shore_asset, "%s_%s" % [material, suffix], cell)


func _water_outside_cardinals(mask: Dictionary, cell: Vector2i, config: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var candidates: Array = [
		["north", Vector2i.UP], ["south", Vector2i.DOWN],
		["west", Vector2i.LEFT], ["east", Vector2i.RIGHT],
	]
	for value: Variant in candidates:
		var pair: Array = value as Array
		var direction: String = str(pair[0])
		if not mask.has(cell + (pair[1] as Vector2i)) and not _is_open_water_edge(cell, direction, config):
			result.append(direction)
	return result


func _is_open_water_edge(cell: Vector2i, direction: String, config: Dictionary) -> bool:
	var open_edges: Array = config.get("open_edges", []) as Array
	if direction not in open_edges:
		return false
	var columns: int = ceili(float(_scene.get("width", 768)) / float(_cell_size.x))
	var rows: int = ceili(float(_scene.get("height", 480)) / float(_cell_size.y))
	return (direction == "north" and cell.y <= 0) or (direction == "south" and cell.y >= rows - 1) or (direction == "west" and cell.x <= 0) or (direction == "east" and cell.x >= columns - 1)


func _transition_directions(mask: Dictionary, cell: Vector2i, config: Dictionary) -> Array[String]:
	var result: Array[String] = []
	var candidates: Array = [
		["north", Vector2i.UP], ["south", Vector2i.DOWN],
		["west", Vector2i.LEFT], ["east", Vector2i.RIGHT],
	]
	for value: Variant in candidates:
		var pair: Array = value as Array
		var direction: String = str(pair[0])
		var neighbor: Vector2i = cell + (pair[1] as Vector2i)
		if mask.has(neighbor) and direction in _water_outside_cardinals(mask, neighbor, config):
			result.append(direction)
	return result


func _corner_suffix(directions: Array[String]) -> String:
	var vertical: String = "n" if "north" in directions else ("s" if "south" in directions else "")
	var horizontal: String = "w" if "west" in directions else ("e" if "east" in directions else "")
	return vertical + horizontal if not vertical.is_empty() and not horizontal.is_empty() else ""


func _missing_diagonal(mask: Dictionary, cell: Vector2i, config: Dictionary) -> String:
	var candidates: Array = [
		["nw", Vector2i(-1, -1)], ["ne", Vector2i(1, -1)],
		["sw", Vector2i(-1, 1)], ["se", Vector2i(1, 1)],
	]
	for value: Variant in candidates:
		var pair: Array = value as Array
		var diagonal: String = str(pair[0])
		var neighbor: Vector2i = cell + (pair[1] as Vector2i)
		if not mask.has(neighbor):
			var vertical: String = "north" if diagonal.begins_with("n") else "south"
			var horizontal: String = "west" if diagonal.ends_with("w") else "east"
			if not _is_open_water_edge(cell, vertical, config) and not _is_open_water_edge(cell, horizontal, config):
				return diagonal
	return ""


func _shore_material(config: Dictionary, cell: Vector2i, fallback: String) -> String:
	for value: Variant in config.get("shore_material_overrides", []):
		var entry: Dictionary = value as Dictionary
		var rect_values: Array = entry.get("rect", []) as Array
		if rect_values.size() == 4:
			var rect := Rect2i(int(rect_values[0]), int(rect_values[1]), int(rect_values[2]), int(rect_values[3]))
			if rect.has_point(cell):
				return str(entry.get("material", fallback))
	return fallback


func _build_interior(config: Dictionary) -> void:
	if config.is_empty():
		return
	var wall_asset: String = str(config.get("wall_asset", "interior_wall_modular_set"))
	var corner_asset: String = str(config.get("corner_asset", "interior_corner_set"))
	var baseboard_asset: String = str(config.get("baseboard_asset", "baseboard_set"))
	var theme: String = str(config.get("theme", "inn_warm"))
	_build_structural_shapes(config)
	for value: Variant in config.get("wall_segments", []):
		var segment: Dictionary = value as Dictionary
		_build_linear_segment("WallTiles", wall_asset, theme, segment)
	for value: Variant in config.get("baseboard_segments", []):
		var segment: Dictionary = value as Dictionary
		_build_linear_segment("BaseboardTiles", baseboard_asset, theme, segment)
	for value: Variant in config.get("corners", []):
		var entry: Dictionary = value as Dictionary
		_add_pixel_tile("CornerTiles", corner_asset, "%s_%s" % [theme, entry.get("tile", "inside_left")], _vector2i(entry.get("position", [0, 0]), Vector2i.ZERO), _color(entry.get("tint", "#ffffff"), Color.WHITE))
	for value: Variant in config.get("door_openings", []):
		var entry: Dictionary = value as Dictionary
		_add_pixel_tile("DoorOpenings", wall_asset, "%s_%s" % [theme, entry.get("tile", "door_compatible")], _vector2i(entry.get("position", [0, 0]), Vector2i.ZERO), _color(entry.get("tint", "#ffffff"), Color.WHITE))


func _build_structural_shapes(config: Dictionary) -> void:
	for value: Variant in config.get("structural_shapes", []):
		var entry: Dictionary = value as Dictionary
		var parent: Node2D = _parents.get(str(entry.get("layer", "WallTiles"))) as Node2D
		var polygon: PackedVector2Array = _points(entry.get("points", []))
		if parent == null or polygon.size() < 3:
			warnings.append("Invalid interior structural shape: %s" % entry.get("object_id", "?"))
			continue
		var shape := Polygon2D.new()
		shape.name = str(entry.get("object_id", "structural_shape"))
		shape.polygon = polygon
		shape.color = _color(entry.get("color", "#4d392d"), Color("4d392d"))
		shape.z_index = int(entry.get("z_index", 0))
		parent.add_child(shape)
		var outline_width: float = float(entry.get("outline_width", 2.0))
		if outline_width > 0.0:
			var outline := Line2D.new()
			outline.name = "%s__outline" % shape.name
			outline.points = polygon
			outline.closed = true
			outline.width = outline_width
			outline.default_color = _color(entry.get("outline", "#2d211b"), Color("2d211b"))
			outline.antialiased = false
			outline.z_index = shape.z_index + 1
			parent.add_child(outline)
		generated_tile_count += 1
	for value: Variant in config.get("structural_lines", []):
		var entry: Dictionary = value as Dictionary
		var parent: Node2D = _parents.get(str(entry.get("layer", "WallTiles"))) as Node2D
		var points: PackedVector2Array = _points(entry.get("points", []))
		if parent == null or points.size() < 2:
			continue
		var line := Line2D.new()
		line.name = str(entry.get("object_id", "structural_line"))
		line.points = points
		line.width = float(entry.get("width", 2.0))
		line.default_color = _color(entry.get("color", "#8a694c"), Color("8a694c"))
		line.antialiased = false
		line.z_index = int(entry.get("z_index", 2))
		parent.add_child(line)


func _build_linear_segment(layer: String, asset_id: String, theme: String, segment: Dictionary) -> void:
	var position: Vector2i = _vector2i(segment.get("position", [0, 0]), Vector2i.ZERO)
	var count: int = maxi(0, int(segment.get("count", 0)))
	var pattern: Array = segment.get("pattern", ["straight"]) as Array
	if pattern.is_empty():
		pattern = ["straight"]
	var size: Vector2i = _catalog.tile_size(asset_id)
	var tint: Color = _color(segment.get("tint", "#ffffff"), Color.WHITE)
	for index: int in range(count):
		var suffix: String = str(pattern[index % pattern.size()])
		if index == 0 and segment.has("start"):
			suffix = str(segment["start"])
		elif index == count - 1 and segment.has("end"):
			suffix = str(segment["end"])
		_add_pixel_tile(layer, asset_id, "%s_%s" % [theme, suffix], position + Vector2i(size.x * index, 0), tint)


func _terrain_semantic(mask: Dictionary, cell: Vector2i, centers: Array, seed: String) -> String:
	var north: bool = not mask.has(cell + Vector2i.UP)
	var south: bool = not mask.has(cell + Vector2i.DOWN)
	var west: bool = not mask.has(cell + Vector2i.LEFT)
	var east: bool = not mask.has(cell + Vector2i.RIGHT)
	if north and west: return "outer_corner_nw"
	if north and east: return "outer_corner_ne"
	if south and west: return "outer_corner_sw"
	if south and east: return "outer_corner_se"
	if north: return "edge_n"
	if south: return "edge_s"
	if west: return "edge_w"
	if east: return "edge_e"
	if not mask.has(cell + Vector2i(-1, -1)): return "inner_corner_nw"
	if not mask.has(cell + Vector2i(1, -1)): return "inner_corner_ne"
	if not mask.has(cell + Vector2i(-1, 1)): return "inner_corner_sw"
	if not mask.has(cell + Vector2i(1, 1)): return "inner_corner_se"
	return str(centers[_roll(seed, cell, "center") % centers.size()])


func _outside_cardinals(mask: Dictionary, cell: Vector2i) -> Array[String]:
	var result: Array[String] = []
	if not mask.has(cell + Vector2i.UP): result.append("north")
	if not mask.has(cell + Vector2i.DOWN): result.append("south")
	if not mask.has(cell + Vector2i.LEFT): result.append("west")
	if not mask.has(cell + Vector2i.RIGHT): result.append("east")
	return result


func _mask_from_entry(entry: Dictionary) -> Dictionary:
	var result := {}
	for value: Variant in entry.get("rects", []):
		var rect_values: Array = value as Array
		if rect_values.size() != 4:
			continue
		for y: int in range(int(rect_values[1]), int(rect_values[1]) + int(rect_values[3])):
			for x: int in range(int(rect_values[0]), int(rect_values[0]) + int(rect_values[2])):
				result[Vector2i(x, y)] = true
	for value: Variant in entry.get("rows", []):
		var row_values: Array = value as Array
		if row_values.size() != 3:
			continue
		for x: int in range(int(row_values[1]), int(row_values[2])):
			result[Vector2i(x, int(row_values[0]))] = true
	for value: Variant in entry.get("exclude_cells", []):
		result.erase(_vector2i(value, Vector2i(-999, -999)))
	return result


func _ground_shape(object_id: String) -> Dictionary:
	for value: Variant in _layout.get("ground_shapes", []):
		var item: Dictionary = value as Dictionary
		if str(item.get("object_id", "")) == object_id:
			return item
	return {}


func _points(value: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if typeof(value) != TYPE_ARRAY:
		return result
	for point_value: Variant in value as Array:
		result.append(Vector2(_vector2i(point_value, Vector2i.ZERO)))
	return result


func _scale_polygon(polygon: PackedVector2Array, factor: float) -> PackedVector2Array:
	var center := Vector2.ZERO
	for point: Vector2 in polygon:
		center += point
	center /= float(maxi(1, polygon.size()))
	var result := PackedVector2Array()
	for point: Vector2 in polygon:
		result.append(center + (point - center) * factor)
	return result


func _is_near_mask(cell: Vector2i, mask: Dictionary, radius: int) -> bool:
	for oy: int in range(-radius, radius + 1):
		for ox: int in range(-radius, radius + 1):
			if mask.has(cell + Vector2i(ox, oy)):
				return true
	return false


func _add_cell_tile(layer: String, asset_id: String, tile_name: String, cell: Vector2i, tint: Color = Color.WHITE) -> void:
	_add_pixel_tile(layer, asset_id, tile_name, cell * _cell_size, tint)


func _add_pixel_tile(layer: String, asset_id: String, tile_name: String, position: Vector2i, tint: Color = Color.WHITE) -> void:
	var parent: Node2D = _parents.get(layer) as Node2D
	if parent == null:
		warnings.append("Missing atlas tile parent: %s" % layer)
		return
	var texture: Texture2D = _catalog.get_named_tile(asset_id, tile_name)
	if texture == null:
		warnings.append("Unable to load named tile: %s.%s" % [asset_id, tile_name])
		return
	var sprite := Sprite2D.new()
	sprite.name = "%s__%s__%d_%d" % [asset_id, tile_name, position.x, position.y]
	sprite.centered = false
	sprite.position = Vector2(position)
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.modulate = tint
	parent.add_child(sprite)
	generated_tile_count += 1


func _roll(seed: String, cell: Vector2i, salt: String) -> int:
	var value: int = hash("%s:%s" % [seed, salt]) & 0x7fffffff
	value = (value ^ (cell.x * 374761393) ^ (cell.y * 668265263)) & 0x7fffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff
	return (value ^ (value >> 16)) & 0x7fffffff


func _unit_roll(seed: String, cell: Vector2i, salt: String) -> float:
	return float(_roll(seed, cell, salt) % 10000) / 10000.0


func _vector2i(value: Variant, fallback: Vector2i) -> Vector2i:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() == 2:
		return Vector2i(int((value as Array)[0]), int((value as Array)[1]))
	return fallback


func _color(value: Variant, fallback: Color) -> Color:
	return Color.from_string(str(value), fallback)
