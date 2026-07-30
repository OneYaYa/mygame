class_name TimeEchoWorldView
extends Node2D

const BUILDING_SCENE: PackedScene = preload("res://scenes/world/building_art_object.tscn")
const PROP_SCENE: PackedScene = preload("res://scenes/world/prop_art_object.tscn")

@onready var ground_details: Node2D = $Ground/GroundDetails
@onready var base_tiles: Node2D = $Ground/Base
@onready var variation_tiles: Node2D = $Ground/Variation
@onready var path_tiles: Node2D = $Ground/Paths
@onready var water_tiles: Node2D = $Ground/Water
@onready var shore_tiles: Node2D = $Ground/ShoreTiles
@onready var architecture_back: Node2D = $ArchitectureBack
@onready var wall_tiles: Node2D = $InteriorShell/WallTiles
@onready var corner_tiles: Node2D = $InteriorShell/CornerTiles
@onready var baseboard_tiles: Node2D = $InteriorShell/BaseboardTiles
@onready var door_openings: Node2D = $InteriorShell/DoorOpenings
@onready var wall_decorations: Node2D = $WallDecorations
@onready var world_objects: Node2D = $WorldObjects
@onready var characters: Node2D = $Characters
@onready var architecture_front: Node2D = $ArchitectureFront
@onready var foreground: Node2D = $Foreground
@onready var lighting: Node2D = $Lighting
@onready var canvas_modulate: CanvasModulate = $Lighting/CanvasModulate
@onready var weather_and_particles: Node2D = $WeatherAndParticles
@onready var interaction_hints: Node2D = $InteractionHints
@onready var debug_overlay: TimeEchoArtDebugManager = $DebugOverlay

var scene_data: Dictionary = {}
var game_state: Dictionary = {}
var layout: Dictionary = {}
var art_catalog := TimeEchoArtCatalog.new()
var layout_catalog := TimeEchoArtLayoutCatalog.new()
var tile_layer_builder := TimeEchoArtTileLayerBuilder.new()
var _catalogs_loaded: bool = false
var _has_water: bool = false
var _water_time: float = 0.0
var _water_redraw_accumulator: float = 0.0
var _light_texture: Texture2D
var _validation_warnings: PackedStringArray = []


func _ready() -> void:
	_load_catalogs()
	set_process(true)


func set_world(scene: Dictionary, state: Dictionary) -> void:
	_load_catalogs()
	scene_data = scene
	game_state = state
	layout = layout_catalog.get_layout(str(scene.get("id", "")))
	_validation_warnings = _collect_layout_warnings()
	_has_water = (layout.get("ground_shapes", []) as Array).any(func(value: Variant) -> bool: return str((value as Dictionary).get("kind", "")) == "water")
	_validation_warnings.append_array(tile_layer_builder.rebuild(scene_data, layout, art_catalog, {
		"BaseTiles": base_tiles,
		"VariationTiles": variation_tiles,
		"PathTiles": path_tiles,
		"WaterTiles": water_tiles,
		"ShoreTiles": shore_tiles,
		"GroundDetails": ground_details,
		"WallTiles": wall_tiles,
		"CornerTiles": corner_tiles,
		"BaseboardTiles": baseboard_tiles,
		"DoorOpenings": door_openings,
		"ForegroundTiles": foreground,
	}))
	_rebuild_objects()
	_rebuild_lights()
	debug_overlay.configure(scene_data, layout, get_art_errors(), _validation_warnings)
	queue_redraw()


func update_state(state: Dictionary) -> void:
	game_state = state
	_update_layout_object_state()
	if _has_water:
		queue_redraw()


func has_art_layout() -> bool:
	return not layout.is_empty()


func get_art_layout() -> Dictionary:
	return layout


func get_art_errors() -> PackedStringArray:
	var result := PackedStringArray()
	result.append_array(art_catalog.errors)
	result.append_array(layout_catalog.errors)
	return result


func get_validation_warnings() -> PackedStringArray:
	return _validation_warnings


func set_art_debug(value: bool) -> void:
	debug_overlay.set_enabled(value)


func is_art_debug_enabled() -> bool:
	return debug_overlay.art_debug_enabled


func get_gameplay_rect(object_id: String, field: String, fallback: Rect2) -> Rect2:
	var overrides: Dictionary = layout.get("gameplay_overrides", {}) as Dictionary
	var entry: Dictionary = overrides.get(object_id, {}) as Dictionary
	return _array_rect(entry.get(field, []), fallback)


func get_collision_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	for value: Variant in layout.get("collision_rects", []):
		var entry: Dictionary = value as Dictionary
		var rect: Rect2 = _array_rect(entry.get("rect", []), Rect2())
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			result.append(rect)
	return result


func get_review_metrics() -> Dictionary:
	var foreground_count: int = 0
	for raw: Variant in layout.get("objects", []):
		var entry: Dictionary = raw as Dictionary
		if str(entry.get("layer", "WorldObjects")) == "Foreground":
			foreground_count += 1
	return {
		"map_id": str(scene_data.get("id", "")),
		"asset_errors": get_art_errors(),
		"warnings": _validation_warnings,
		"object_count": (layout.get("objects", []) as Array).size(),
		"collision_count": (layout.get("collision_rects", []) as Array).size(),
		"foreground_count": foreground_count,
		"portal_count": (scene_data.get("portals", []) as Array).size(),
		"generated_tile_count": tile_layer_builder.generated_tile_count,
		"camera_zoom": float(layout.get("camera_zoom", 1.0)),
	}


func _process(delta: float) -> void:
	if not _has_water:
		return
	_water_time += delta
	_water_redraw_accumulator += delta
	if _water_redraw_accumulator >= 0.24:
		_water_redraw_accumulator = 0.0
		queue_redraw()


func _draw() -> void:
	if scene_data.is_empty():
		return
	var width: float = float(scene_data.get("width", 768))
	var height: float = float(scene_data.get("height", 480))
	var canvas: Dictionary = layout.get("canvas", {}) as Dictionary
	if str(scene_data.get("kind", "outdoor")) == "interior":
		_draw_room_shell(Rect2(0, 0, width, height), canvas)
	else:
		_draw_outdoor_base(Rect2(0, 0, width, height), canvas)
	var tile_art: Dictionary = layout.get("atlas_tile_art", {}) as Dictionary
	var replaced_shapes: Array = tile_art.get("replaced_ground_shapes", []) as Array
	for value: Variant in layout.get("ground_shapes", []):
		var ground_shape: Dictionary = value as Dictionary
		if str(ground_shape.get("object_id", "")) in replaced_shapes:
			continue
		_draw_ground_shape(ground_shape, canvas)
	_draw_dynamic_story_marks(canvas)
	var border: Color = _color(canvas.get("edge_color", "#2f4743"), Color("2f4743"))
	if bool(canvas.get("draw_map_border", true)):
		draw_rect(Rect2(3, 3, width - 6, height - 6), border, false, 4.0)


func _load_catalogs() -> void:
	if _catalogs_loaded:
		return
	_catalogs_loaded = true
	art_catalog.load_catalog()
	layout_catalog.load_catalog()


func _rebuild_objects() -> void:
	for parent: Node2D in [ground_details, architecture_back, wall_decorations, world_objects, architecture_front, foreground]:
		for child: Node in parent.get_children():
			child.queue_free()
	for value: Variant in layout.get("objects", []):
		var entry: Dictionary = value as Dictionary
		var asset_id: String = str(entry.get("asset_id", ""))
		var asset: Dictionary = art_catalog.get_asset(asset_id)
		var category: String = str(asset.get("category", ""))
		var scene: PackedScene = BUILDING_SCENE if category == "building" else PROP_SCENE
		var object: TimeEchoArtObject2D = scene.instantiate() as TimeEchoArtObject2D
		var layer_name: String = str(entry.get("layer", "WorldObjects"))
		var parent: Node2D = _layer_node(layer_name)
		parent.add_child(object)
		object.configure(entry, asset, art_catalog.get_texture(asset_id))
		object.update_story_state(game_state)
		object.update_occlusion(_player_position())
		object.z_as_relative = false
		if layer_name == "GroundDetails":
			object.z_index = -720 + int(entry.get("z_index", 0))
		elif layer_name == "ArchitectureBack":
			object.z_index = -380 + int(entry.get("z_index", 0))
		elif layer_name == "WallDecorations":
			object.z_index = -200 + int(entry.get("z_index", 0))
		elif layer_name == "ArchitectureFront":
			object.z_index = 1600 + int(entry.get("z_index", 0))
		elif layer_name == "Foreground":
			object.z_index = 1900 + int(entry.get("z_index", 0))


func _update_layout_object_state() -> void:
	var player_position: Vector2 = _player_position()
	for parent: Node2D in [ground_details, architecture_back, wall_decorations, world_objects, architecture_front, foreground]:
		for child: Node in parent.get_children():
			if child is TimeEchoArtObject2D:
				var object := child as TimeEchoArtObject2D
				object.update_story_state(game_state)
				object.update_occlusion(player_position)
	_update_story_lights()


func _update_story_lights() -> void:
	var flags: Dictionary = game_state.get("flags", {}) as Dictionary
	for child: Node in lighting.get_children():
		if not (child is PointLight2D):
			continue
		var light := child as PointLight2D
		var base_energy: float = float(light.get_meta("base_energy", light.energy))
		var flag_name: String = str(light.get_meta("story_flag", ""))
		light.energy = base_energy if flag_name.is_empty() or bool(flags.get(flag_name, false)) else float(light.get_meta("inactive_energy", base_energy * 0.25))


func _player_position() -> Vector2:
	var player_state: Dictionary = game_state.get("player", {}) as Dictionary
	return Vector2(float(player_state.get("x", -9999.0)), float(player_state.get("y", -9999.0)))


func _rebuild_lights() -> void:
	for child: Node in lighting.get_children():
		if child != canvas_modulate:
			child.queue_free()
	if _light_texture == null:
		_light_texture = _make_light_texture()
	for value: Variant in layout.get("lights", []):
		var entry: Dictionary = value as Dictionary
		var light := PointLight2D.new()
		light.name = str(entry.get("object_id", "ArtLight"))
		light.position = _array_vector(entry.get("position", [0, 0])).round()
		light.texture = _light_texture
		light.texture_scale = float(entry.get("radius", 72.0)) / 32.0
		light.color = _color(entry.get("color", "#f1bd70"), Color("f1bd70"))
		light.energy = float(entry.get("energy", 0.55))
		light.set_meta("base_energy", light.energy)
		light.set_meta("story_flag", str(entry.get("story_flag", "")))
		light.set_meta("inactive_energy", float(entry.get("inactive_energy", light.energy * 0.25)))
		light.blend_mode = Light2D.BLEND_MODE_ADD
		light.shadow_enabled = false
		lighting.add_child(light)
	_update_story_lights()


func _draw_outdoor_base(rect: Rect2, canvas: Dictionary) -> void:
	var base_color: Color = _color(canvas.get("base_color", "#667f59"), Color("667f59"))
	if not (layout.get("atlas_tile_art", {}) as Dictionary).get("base_fill", {}).is_empty():
		return
	draw_rect(rect, base_color)
	var texture: Texture2D = art_catalog.get_texture(str(canvas.get("base_texture", "tile_grass_low_noise")))
	if texture != null:
		var tint := Color(0.72, 0.78, 0.61, float(canvas.get("texture_opacity", 0.16)))
		draw_texture_rect(texture, rect, true, tint)
	_draw_fixed_ground_details(rect, base_color, int(canvas.get("detail_density", 90)))


func _draw_room_shell(world_rect: Rect2, canvas: Dictionary) -> void:
	if bool(canvas.get("natural_boundary", false)):
		_draw_natural_shell(world_rect, canvas)
		return
	if bool(canvas.get("open_structure", false)):
		_draw_open_structure_shell(world_rect, canvas)
		return
	var outside: Color = _color(canvas.get("outside_color", "#101719"), Color("101719"))
	draw_rect(world_rect, outside)
	var room: Rect2 = _array_rect(canvas.get("room_rect", [48, 52, world_rect.size.x - 96, world_rect.size.y - 78]), Rect2(48, 52, world_rect.size.x - 96, world_rect.size.y - 78))
	var wall: Color = _color(canvas.get("wall_color", "#6f665b"), Color("6f665b"))
	var wall_dark: Color = _color(canvas.get("wall_dark", wall.darkened(0.34).to_html()), wall.darkened(0.34))
	var floor: Color = _color(canvas.get("floor_color", "#7a644e"), Color("7a644e"))
	var wall_height: float = float(canvas.get("wall_height", 48))
	var side_width: float = float(canvas.get("side_wall", 16))
	draw_rect(room.grow(8), Color(0.02, 0.035, 0.038, 0.66))
	draw_rect(room, wall_dark)
	draw_rect(Rect2(room.position + Vector2(side_width, wall_height), room.size - Vector2(side_width * 2.0, wall_height + side_width)), floor)
	draw_rect(Rect2(room.position + Vector2(side_width, 8), Vector2(room.size.x - side_width * 2.0, wall_height - 8)), wall)
	draw_line(room.position + Vector2(side_width, wall_height), Vector2(room.end.x - side_width, room.position.y + wall_height), wall_dark.darkened(0.18), 4.0)
	draw_line(room.position + Vector2(side_width, wall_height - 4), Vector2(room.end.x - side_width, room.position.y + wall_height - 4), wall.lightened(0.12), 2.0)
	_draw_floor_pattern(Rect2(room.position + Vector2(side_width, wall_height), room.size - Vector2(side_width * 2.0, wall_height + side_width)), str(canvas.get("floor_style", "warm_wood")), floor)
	# Pixel-dark corners and wall footings give the shell depth without blur.
	draw_colored_polygon(PackedVector2Array([room.position, room.position + Vector2(34, 0), room.position + Vector2(side_width, wall_height + 24), room.position + Vector2(0, wall_height + 36)]), Color(0.04, 0.055, 0.06, 0.48))
	draw_colored_polygon(PackedVector2Array([Vector2(room.end.x - 34, room.position.y), room.end - Vector2(0, room.size.y), room.position + Vector2(room.size.x, wall_height + 36), room.position + Vector2(room.size.x - side_width, wall_height + 24)]), Color(0.04, 0.055, 0.06, 0.48))


func _draw_open_structure_shell(world_rect: Rect2, canvas: Dictionary) -> void:
	# Elevated special spaces are assembled from authored platforms, beams and
	# voids. They intentionally receive no rectangular room floor/baseboard.
	var outside: Color = _color(canvas.get("outside_color", "#071013"), Color("071013"))
	draw_rect(world_rect, outside)
	var depth: Color = _color(canvas.get("depth_color", "#10191b"), Color("10191b"))
	var horizon_y: float = float(canvas.get("depth_horizon_y", world_rect.size.y * 0.38))
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, horizon_y), Vector2(world_rect.size.x, horizon_y),
		Vector2(world_rect.size.x, world_rect.size.y), Vector2(0, world_rect.size.y),
	]), depth)
	var far_beam: Color = _color(canvas.get("far_beam_color", "#243033"), Color("243033"))
	for y_offset: int in [0, 38, 84]:
		var y: float = horizon_y + float(y_offset)
		draw_line(Vector2(36, y), Vector2(world_rect.size.x - 36, y), far_beam.darkened(float(y_offset) / 260.0), 3.0)
	for x: int in range(68, int(world_rect.size.x), 128):
		draw_line(Vector2(x, 52), Vector2(x - 26, horizon_y + 112), far_beam.darkened(0.12), 4.0)


func _draw_natural_shell(world_rect: Rect2, canvas: Dictionary) -> void:
	# Caves use an authored irregular boundary instead of pretending to be a
	# rectangular furnished room.  Atlas rock walls and ceiling overhangs are
	# layered above this low-noise foundation by the tile builder.
	var outside: Color = _color(canvas.get("outside_color", "#071012"), Color("071012"))
	draw_rect(world_rect, outside)
	var boundary: PackedVector2Array = _points(canvas.get("boundary_points", []))
	if boundary.size() < 3:
		boundary = PackedVector2Array([
			Vector2(72, 98), Vector2(world_rect.size.x - 76, 82),
			Vector2(world_rect.size.x - 42, world_rect.size.y - 82),
			Vector2(74, world_rect.size.y - 58),
		])
	var floor: Color = _color(canvas.get("floor_color", "#344346"), Color("344346"))
	var rim: Color = _color(canvas.get("wall_dark", "#172529"), Color("172529"))
	draw_colored_polygon(boundary, rim)
	var center := Vector2.ZERO
	for point: Vector2 in boundary:
		center += point
	center /= float(boundary.size())
	var inner := PackedVector2Array()
	for point: Vector2 in boundary:
		inner.append(center + (point - center) * 0.91)
	draw_colored_polygon(inner, floor)
	draw_polyline(_closed(boundary), rim.darkened(0.35), 7.0)
	draw_polyline(_closed(inner), floor.lightened(0.09), 2.0)
	_draw_floor_pattern(_polygon_bounds(inner), "wet_stone", floor)


func _draw_floor_pattern(rect: Rect2, style: String, base: Color) -> void:
	match style:
		"warm_wood":
			var texture: Texture2D = art_catalog.get_texture("tile_wood_warm")
			if texture != null:
				draw_texture_rect(texture, rect, true, Color(0.75, 0.68, 0.54, 0.24))
			for y: int in range(int(rect.position.y), int(rect.end.y), 18):
				draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), base.darkened(0.11), 1.0)
		"dark_wood", "engineering":
			for y: int in range(int(rect.position.y), int(rect.end.y), 16):
				draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), base.darkened(0.18), 2.0)
				for x: int in range(int(rect.position.x + ((y / 16) % 2) * 31), int(rect.end.x), 62):
					draw_line(Vector2(x, y), Vector2(x, minf(rect.end.y, y + 16)), base.lightened(0.07), 1.0)
			if style == "engineering":
				for x: int in range(int(rect.position.x + 24), int(rect.end.x), 96):
					draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0.36, 0.39, 0.36, 0.48), 2.0)
		"chapel_stone", "archive_stone", "mechanical_stone", "wet_stone":
			var tile_width: int = 48 if style != "mechanical_stone" else 64
			for y: int in range(int(rect.position.y), int(rect.end.y), 32):
				draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), base.darkened(0.16), 2.0)
				for x: int in range(int(rect.position.x + (tile_width / 2 if int(y / 32) % 2 else 0)), int(rect.end.x), tile_width):
					draw_line(Vector2(x, y), Vector2(x, minf(rect.end.y, y + 32)), base.darkened(0.12), 1.0)
			if style == "wet_stone":
				for index: int in range(18):
					var point := _seeded_point(rect, "wet:%d" % index)
					draw_line(point, point + Vector2(8 + index % 7, 0), base.lightened(0.16), 1.0)
		"darkroom":
			for y: int in range(int(rect.position.y), int(rect.end.y), 24):
				draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0.18, 0.075, 0.07, 0.74), 2.0)
			for x: int in range(int(rect.position.x), int(rect.end.x), 48):
				draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0.08, 0.07, 0.075, 0.7), 1.0)


func _draw_fixed_ground_details(rect: Rect2, base: Color, count: int) -> void:
	var blocked_polygons: Array[PackedVector2Array] = []
	for value: Variant in layout.get("ground_shapes", []):
		var item: Dictionary = value as Dictionary
		if str(item.get("kind", "")) in ["path", "water", "platform", "pier", "plaza", "garden"]:
			blocked_polygons.append(_shape_polygon(item))
	for index: int in range(count):
		var point := _seeded_point(rect, "%s:ground:%d" % [scene_data.get("id", "map"), index])
		var blocked: bool = blocked_polygons.any(func(polygon: PackedVector2Array) -> bool: return polygon.size() >= 3 and Geometry2D.is_point_in_polygon(point, polygon))
		if blocked:
			continue
		var color: Color = base.lightened(0.055) if index % 3 == 0 else base.darkened(0.045)
		draw_rect(Rect2(point.round(), Vector2(2 + index % 2, 1)), color)


func _draw_ground_shape(item: Dictionary, canvas: Dictionary) -> void:
	var kind: String = str(item.get("kind", "polygon"))
	if kind == "path":
		_draw_path(item, canvas)
		return
	var polygon: PackedVector2Array = _shape_polygon(item)
	if polygon.size() < 3:
		return
	if kind == "water":
		_draw_water(item, polygon, canvas)
		return
	var color: Color = _color(item.get("color", canvas.get("path_color", "#a99570")), Color("a99570"))
	if kind == "garden":
		draw_colored_polygon(polygon, color.darkened(0.2))
		var bounds: Rect2 = _polygon_bounds(polygon)
		for y: int in range(int(bounds.position.y + 10), int(bounds.end.y), 18):
			draw_line(Vector2(bounds.position.x + 8, y), Vector2(bounds.end.x - 8, y), color.lightened(0.24), 2.0)
			for x: int in range(int(bounds.position.x + 18 + (y % 2) * 7), int(bounds.end.x - 10), 28):
				var plant := Vector2(x, y - 3)
				if Geometry2D.is_point_in_polygon(plant, polygon):
					draw_circle(plant, 3.0, color.lightened(0.38))
	elif kind == "pier":
		draw_colored_polygon(polygon, Color(0.07, 0.10, 0.11, 0.34))
		draw_polyline(_closed(polygon), Color(0.06, 0.09, 0.10, 0.62), 4.0)
		draw_colored_polygon(polygon, color.darkened(0.2))
		var bounds: Rect2 = _polygon_bounds(polygon)
		for y: int in range(int(bounds.position.y + 8), int(bounds.end.y), 12):
			draw_line(Vector2(bounds.position.x, y), Vector2(bounds.end.x, y), color.lightened(0.08), 2.0)
	elif kind == "wood_platform":
		draw_colored_polygon(polygon, color.darkened(0.18))
		draw_polyline(_closed(polygon), color.darkened(0.52), 5.0)
		var bounds: Rect2 = _polygon_bounds(polygon)
		for y: int in range(int(bounds.position.y + 8), int(bounds.end.y), 13):
			var from := Vector2(bounds.position.x, y)
			var to := Vector2(bounds.end.x, y)
			if Geometry2D.is_point_in_polygon(from + Vector2(5, 0), polygon) or Geometry2D.is_point_in_polygon(to - Vector2(5, 0), polygon):
				draw_line(from, to, color.lightened(0.06), 2.0)
		for x: int in range(int(bounds.position.x + 20), int(bounds.end.x), 58):
			draw_line(Vector2(x, bounds.position.y + 4), Vector2(x, bounds.end.y - 4), color.darkened(0.22), 2.0)
	elif kind in ["platform", "plaza"]:
		draw_colored_polygon(polygon, color)
		draw_polyline(_closed(polygon), color.darkened(0.3), 4.0)
		_draw_stone_marks(polygon, color)
	else:
		draw_colored_polygon(polygon, color)
		draw_polyline(_closed(polygon), color.darkened(0.28), float(item.get("outline_width", 3.0)))


func _draw_path(item: Dictionary, canvas: Dictionary) -> void:
	var points: PackedVector2Array = _points(item.get("points", []))
	if points.size() < 2:
		return
	var width: float = float(item.get("width", 54))
	var color: Color = _color(item.get("color", canvas.get("path_color", "#a99570")), Color("a99570"))
	var edge: Color = _color(item.get("edge_color", color.darkened(0.3).to_html()), color.darkened(0.3))
	# Draw all edge strokes before the paving. Interleaving them per segment
	# exposes circular seams and makes a lane read as a chain of disks.
	for index: int in range(points.size() - 1):
		draw_line(points[index], points[index + 1], edge, width + 6.0)
	for point: Vector2 in points:
		draw_circle(point, width * 0.5 + 3.0, edge)
	for index: int in range(points.size() - 1):
		draw_line(points[index], points[index + 1], color, width)
	for point: Vector2 in points:
		draw_circle(point, width * 0.5, color)
	# Fixed chips and grass intrusions break the rectangle without changing collision logic.
	for index: int in range(points.size() * 7):
		var segment: int = index % (points.size() - 1)
		var t: float = float((hash("%s:%s:%d" % [scene_data.get("id", ""), item.get("object_id", "path"), index]) & 1023)) / 1023.0
		var center: Vector2 = points[segment].lerp(points[segment + 1], t)
		var direction: Vector2 = (points[segment + 1] - points[segment]).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var side: float = -1.0 if index % 2 == 0 else 1.0
		var mark: Vector2 = (center + normal * side * width * (0.22 + float(index % 4) * 0.07)).round()
		draw_rect(Rect2(mark, Vector2(5 + index % 5, 2)), color.lightened(0.10) if index % 3 else edge.lightened(0.08))


func _draw_water(item: Dictionary, polygon: PackedVector2Array, canvas: Dictionary) -> void:
	var deep: Color = _color(item.get("color", canvas.get("water_color", "#355f69")), Color("355f69"))
	var shore: Color = _color(item.get("shore_color", canvas.get("shore_color", "#85927a")), Color("85927a"))
	draw_colored_polygon(polygon, shore.darkened(0.18))
	var inset: PackedVector2Array = _scale_polygon(polygon, 0.965)
	draw_colored_polygon(inset, deep)
	draw_polyline(_closed(inset), deep.lightened(0.13), 3.0)
	var texture: Texture2D = art_catalog.get_texture("tile_water_world")
	if texture != null:
		# Texture is sampled in world coordinates; the polygon color remains the mask boundary.
		var bounds := _polygon_bounds(inset)
		for y: int in range(int(bounds.position.y), int(bounds.end.y), 64):
			for x: int in range(int(bounds.position.x), int(bounds.end.x), 64):
				var center := Vector2(x + 32, y + 32)
				if Geometry2D.is_point_in_polygon(center, inset):
					draw_texture_rect(texture, Rect2(x, y, 64, 64), false, Color(0.55, 0.76, 0.78, 0.15))
	var bounds: Rect2 = _polygon_bounds(inset)
	var phase: int = int(_water_time * 2.0) % 4
	for y: int in range(int(bounds.position.y + 18 + phase), int(bounds.end.y - 8), 28):
		for x: int in range(int(bounds.position.x + 12 + (y % 3) * 7), int(bounds.end.x - 16), 58):
			var point := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(point, inset):
				draw_line(point, point + Vector2(13 + (x + y) % 10, 0), deep.lightened(0.24), 2.0)


func _draw_stone_marks(polygon: PackedVector2Array, color: Color) -> void:
	var bounds: Rect2 = _polygon_bounds(polygon)
	for y: int in range(int(bounds.position.y + 10), int(bounds.end.y), 18):
		for x: int in range(int(bounds.position.x + 10 + (9 if int(y / 18) % 2 else 0)), int(bounds.end.x), 28):
			var point := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(point, polygon):
				draw_line(point, point + Vector2(8 + (x + y) % 7, 0), color.darkened(0.12), 1.0)


func _draw_dynamic_story_marks(canvas: Dictionary) -> void:
	var flags: Dictionary = game_state.get("flags", {}) as Dictionary
	var repairs: Dictionary = game_state.get("repairs", {}) as Dictionary
	var map_id: String = str(scene_data.get("id", ""))
	if map_id == "town" and bool(repairs.get("master", false)):
		var center: Vector2 = _override_center("square_clock_face", "interaction_rect", Vector2(576, 154))
		draw_arc(center, 34.0, 0.0, TAU, 24, Color(0.93, 0.76, 0.35, 0.58), 2.0)
	if map_id == "harbor" and bool(flags.get("low_tide", false)):
		var cave: Rect2 = get_gameplay_rect("enter_low_tide_cave", "trigger_rect", Rect2(1130, 510, 80, 110))
		for index: int in range(5):
			draw_circle(cave.get_center() + Vector2(index * 13 - 26, 18), 3.0, _color(canvas.get("path_color", "#a99570"), Color("a99570")))
	if map_id == "clock-basement" and bool(flags.get("slot_seven_filled", false)):
		var slot: Vector2 = _override_center("witness_slot_seven", "interaction_rect", Vector2(659, 154))
		draw_circle(slot, 25.0, Color(0.78, 0.64, 0.31, 0.18))
		draw_arc(slot, 25.0, 0.0, TAU, 20, Color(0.92, 0.78, 0.42, 0.7), 2.0)


func _layer_node(layer_name: String) -> Node2D:
	match layer_name:
		"GroundDetails": return ground_details
		"ArchitectureBack": return architecture_back
		"WallDecorations": return wall_decorations
		"ArchitectureFront": return architecture_front
		"Foreground": return foreground
		_: return world_objects


func _collect_layout_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if layout.is_empty():
		warnings.append("No Godot art layout for %s" % scene_data.get("id", "?"))
		return warnings
	var rectangles: Array[Dictionary] = []
	for value: Variant in layout.get("objects", []):
		var item: Dictionary = value as Dictionary
		var position: Vector2 = _array_vector(item.get("position", [0, 0]))
		var size: Vector2 = _array_vector(item.get("display_size", [24, 24]))
		if position != position.round():
			warnings.append("Non-integer position: %s" % item.get("object_id", "?"))
		if size != size.round():
			warnings.append("Non-integer display size: %s" % item.get("object_id", "?"))
		if bool(item.get("warn_overlap", false)):
			var anchor := _array_vector(item.get("anchor", [0.5, 1.0]))
			var rect := Rect2(position - size * anchor, size)
			for existing: Dictionary in rectangles:
				if rect.intersects(existing["rect"] as Rect2):
					warnings.append("Art overlap: %s / %s" % [item.get("object_id", "?"), existing["id"]])
			rectangles.append({"id": item.get("object_id", "?"), "rect": rect})
	return warnings


func _make_light_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y: int in range(64):
		for x: int in range(64):
			var distance: float = Vector2(x - 31.5, y - 31.5).length() / 31.5
			var alpha: float = clampf(1.0 - distance, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * alpha))
	return ImageTexture.create_from_image(image)


func _seeded_point(rect: Rect2, key: String) -> Vector2:
	var x_hash: int = abs(hash("x:%s" % key))
	var y_hash: int = abs(hash("y:%s" % key))
	return Vector2(rect.position.x + float(x_hash % maxi(1, int(rect.size.x))), rect.position.y + float(y_hash % maxi(1, int(rect.size.y))))


func _shape_polygon(item: Dictionary) -> PackedVector2Array:
	var polygon: PackedVector2Array = _points(item.get("points", []))
	if polygon.size() >= 3:
		return polygon
	var rect: Rect2 = _array_rect(item.get("rect", []), Rect2())
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]) if rect.size.x > 0.0 else PackedVector2Array()


func _points(value: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if typeof(value) != TYPE_ARRAY:
		return result
	for point_value: Variant in (value as Array):
		result.append(_array_vector(point_value))
	return result


func _closed(polygon: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = polygon.duplicate()
	if not result.is_empty():
		result.append(result[0])
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


func _polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	if polygon.is_empty():
		return Rect2()
	var minimum := polygon[0]
	var maximum := polygon[0]
	for point: Vector2 in polygon:
		minimum.x = minf(minimum.x, point.x)
		minimum.y = minf(minimum.y, point.y)
		maximum.x = maxf(maximum.x, point.x)
		maximum.y = maxf(maximum.y, point.y)
	return Rect2(minimum, maximum - minimum)


func _array_vector(value: Variant) -> Vector2:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() == 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO


func _array_rect(value: Variant, fallback: Rect2) -> Rect2:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() == 4:
		return Rect2(float((value as Array)[0]), float((value as Array)[1]), float((value as Array)[2]), float((value as Array)[3]))
	return fallback


func _override_center(object_id: String, field: String, fallback: Vector2) -> Vector2:
	var rect: Rect2 = get_gameplay_rect(object_id, field, Rect2(fallback - Vector2(1, 1), Vector2(2, 2)))
	return rect.get_center()


func _color(value: Variant, fallback: Color) -> Color:
	return Color.from_string(str(value), fallback)
