class_name TimeEchoWorldController
extends Node2D

signal interaction_requested(target: Dictionary)

const NPC_SCENE: PackedScene = preload("res://scenes/characters/npc.tscn")

@onready var world_view: TimeEchoWorldView = $WorldView
@onready var collisions: Node2D = $WorldView/Collisions
@onready var actors: Node2D = $WorldView/Characters
@onready var player: TimeEchoPlayer = $WorldView/Characters/Player
@onready var canvas_modulate: CanvasModulate = $WorldView/Lighting/CanvasModulate

var current_scene: Dictionary = {}
var state: Dictionary = {}
var npc_actors: Dictionary = {}
var _last_step_at: int = 0
var _time_of_day_override: String = ""
var _player_light_texture: Texture2D


func _ready() -> void:
	player.interact_pressed.connect(_request_nearest_interaction)
	player.moved.connect(_on_player_moved)


func load_state(new_state: Dictionary, force_scene_rebuild: bool = false) -> void:
	state = new_state
	var place_id: String = str(state.get("placeId", "player-room"))
	if force_scene_rebuild or current_scene.is_empty() or str(current_scene.get("id", "")) != place_id:
		_change_scene(place_id)
	else:
		world_view.update_state(state)
		_update_npcs(0.0)
	_update_player_light()
	_update_daylight()


func set_input_enabled(value: bool) -> void:
	player.active = value


func set_time_of_day_override(value: String) -> void:
	_time_of_day_override = value
	_update_daylight()


func set_art_debug(value: bool) -> void:
	world_view.set_art_debug(value)


func get_art_review_metrics() -> Dictionary:
	var metrics: Dictionary = world_view.get_review_metrics()
	metrics["player_spawn"] = [player.position.x, player.position.y]
	metrics["camera_zoom"] = (player.get_node("Camera2D") as Camera2D).zoom.x
	var npc_points: Array[Dictionary] = []
	for npc_id: Variant in npc_actors.keys():
		var actor: TimeEchoNPCActor = npc_actors[npc_id] as TimeEchoNPCActor
		npc_points.append({"npc_id": str(npc_id), "position": [actor.position.x, actor.position.y]})
	metrics["npc_points"] = npc_points
	metrics["portal_reachability"] = get_portal_reachability_report()
	metrics["interaction_reachability"] = get_interaction_reachability_report()
	metrics["npc_reachability"] = get_npc_reachability_report()
	return metrics


func get_portal_reachability_report() -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	if current_scene.is_empty():
		return report
	const GRID: int = 16
	var bounds := Rect2(0, 0, float(current_scene.get("width", 768)), float(current_scene.get("height", 480)))
	var obstacles: Array[Rect2] = world_view.get_collision_rects()
	var visited: Dictionary = _reachable_cells_from_player(GRID, bounds, obstacles)
	for raw: Variant in current_scene.get("portals", []):
		var portal: Dictionary = raw as Dictionary
		var portal_id: String = str(portal.get("id", ""))
		var trigger: Rect2 = world_view.get_gameplay_rect(portal_id, "trigger_rect", _rect(portal))
		report.append({
			"portal_id": portal_id,
			"target": str(portal.get("targetPlaceId", "")),
			"revealed": SceneManager.can_reveal_portal(portal, state),
			"reachable": _rect_is_reachable(trigger, visited, GRID),
			"trigger_rect": [trigger.position.x, trigger.position.y, trigger.size.x, trigger.size.y],
		})
	return report


func get_interaction_reachability_report() -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	if current_scene.is_empty():
		return report
	const GRID: int = 16
	var bounds := Rect2(0, 0, float(current_scene.get("width", 768)), float(current_scene.get("height", 480)))
	var obstacles: Array[Rect2] = world_view.get_collision_rects()
	var visited: Dictionary = _reachable_cells_from_player(GRID, bounds, obstacles)
	for raw: Variant in current_scene.get("landmarks", []):
		var landmark: Dictionary = raw as Dictionary
		if not bool(landmark.get("interactive", false)):
			continue
		var landmark_id: String = str(landmark.get("id", ""))
		var interaction_rect: Rect2 = world_view.get_gameplay_rect(landmark_id, "interaction_rect", _rect(landmark))
		report.append({
			"landmark_id": landmark_id,
			"reachable": _rect_is_reachable(interaction_rect, visited, GRID),
			"interaction_rect": [interaction_rect.position.x, interaction_rect.position.y, interaction_rect.size.x, interaction_rect.size.y],
		})
	return report


func get_npc_reachability_report() -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	if current_scene.is_empty():
		return report
	const GRID: int = 16
	var bounds := Rect2(0, 0, float(current_scene.get("width", 768)), float(current_scene.get("height", 480)))
	var obstacles: Array[Rect2] = world_view.get_collision_rects()
	var visited: Dictionary = _reachable_cells_from_player(GRID, bounds, obstacles)
	for npc_id: Variant in npc_actors.keys():
		var actor: TimeEchoNPCActor = npc_actors[npc_id] as TimeEchoNPCActor
		var standing_area := Rect2(actor.position - Vector2(14.0, 14.0), Vector2(28.0, 28.0))
		report.append({
			"npc_id": str(npc_id),
			"reachable": _rect_is_reachable(standing_area, visited, GRID),
			"position": [actor.position.x, actor.position.y],
		})
	return report


func _reachable_cells_from_player(grid: int, bounds: Rect2, obstacles: Array[Rect2]) -> Dictionary:
	var start: Vector2i = _nearest_open_cell(_world_to_cell(player.position, grid), grid, bounds, obstacles)
	var visited: Dictionary = {start: true}
	var frontier: Array[Vector2i] = [start]
	var cursor: int = 0
	var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
	while cursor < frontier.size():
		var cell: Vector2i = frontier[cursor]
		cursor += 1
		for direction: Vector2i in directions:
			var next: Vector2i = cell + direction
			if visited.has(next) or _cell_is_blocked(next, grid, bounds, obstacles):
				continue
			visited[next] = true
			frontier.append(next)
	return visited


func _rect_is_reachable(rect: Rect2, visited: Dictionary, grid: int) -> bool:
	for cell_value: Variant in visited.keys():
		var point: Vector2 = _cell_center(cell_value as Vector2i, grid)
		if rect.grow(10.0).has_point(point):
			return true
	return false


func get_nearest_interaction() -> Dictionary:
	if current_scene.is_empty():
		return {}
	var point: Vector2 = player.position
	var candidates: Array[Dictionary] = []
	for npc_id: Variant in npc_actors.keys():
		var actor: TimeEchoNPCActor = npc_actors[npc_id] as TimeEchoNPCActor
		var distance: float = point.distance_to(actor.position)
		if distance <= 62.0:
			var profile: Dictionary = DataManager.get_npc(str(npc_id))
			candidates.append({"type": "npc", "value": profile, "distance": distance, "priority": 0, "label": "与 %s 交谈" % profile.get("name", npc_id)})
	for raw: Variant in current_scene.get("landmarks", []):
		var landmark: Dictionary = raw as Dictionary
		if not bool(landmark.get("interactive", false)):
			continue
		var fallback: Rect2 = _rect(landmark)
		var interaction_rect: Rect2 = world_view.get_gameplay_rect(str(landmark.get("id", "")), "interaction_rect", fallback)
		var distance: float = _point_rect_distance(point, interaction_rect)
		if distance <= float(world_view.get_art_layout().get("interaction_distance", 52.0)):
			candidates.append({"type": "landmark", "value": landmark, "distance": distance, "priority": 1, "label": str(landmark.get("label", "检查"))})
	for raw: Variant in current_scene.get("portals", []):
		var portal: Dictionary = raw as Dictionary
		if not SceneManager.can_reveal_portal(portal, state):
			continue
		var fallback: Rect2 = _rect(portal)
		var trigger_rect: Rect2 = world_view.get_gameplay_rect(str(portal.get("id", "")), "trigger_rect", fallback)
		var distance: float = _point_rect_distance(point, trigger_rect)
		if distance <= 58.0:
			candidates.append({"type": "portal", "value": portal, "distance": distance, "priority": 2, "label": str(portal.get("label", "前往"))})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if absf(float(a["distance"]) - float(b["distance"])) <= 4.0:
			return int(a["priority"]) < int(b["priority"])
		return float(a["distance"]) < float(b["distance"])
	)
	return candidates[0]


func _process(delta: float) -> void:
	if state.is_empty():
		return
	_update_npcs(delta)
	world_view.update_state(state)


func _unhandled_input(event: InputEvent) -> void:
	if not player.active or not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var world_point: Vector2 = get_global_mouse_position()
	var clicked: Dictionary = _target_at_point(world_point)
	if not clicked.is_empty():
		interaction_requested.emit(clicked)
		get_viewport().set_input_as_handled()


func _change_scene(place_id: String) -> void:
	current_scene = DataManager.get_scene_data(place_id)
	if current_scene.is_empty():
		push_error("Unable to instantiate location: %s" % place_id)
		return
	world_view.set_world(current_scene, state)
	_rebuild_collisions()
	_rebuild_npcs()
	var player_state: Dictionary = state.get("player", {}) as Dictionary
	var bounds := Rect2(0, 0, float(current_scene.get("width", 768)), float(current_scene.get("height", 480)))
	player.configure(Vector2(float(player_state.get("x", 384.0)), float(player_state.get("y", 350.0))), str(player_state.get("facing", "down")), bounds)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	var camera_zoom: float = clampf(float(world_view.get_art_layout().get("camera_zoom", 1.0)), 0.75, 1.5)
	var camera_offset_values: Array = world_view.get_art_layout().get("camera_offset", [0, -32]) as Array
	camera.zoom = Vector2(camera_zoom, camera_zoom)
	camera.position = Vector2(float(camera_offset_values[0]), float(camera_offset_values[1])).round() if camera_offset_values.size() == 2 else Vector2(0, -32)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(bounds.size.x)
	camera.limit_bottom = int(bounds.size.y)
	EventBus.scene_changed.emit(current_scene)


func _rebuild_npcs() -> void:
	for child: Node in actors.get_children():
		if child is TimeEchoNPCActor:
			child.queue_free()
	npc_actors.clear()
	var npcs: Dictionary = state.get("npcs", {}) as Dictionary
	for npc_id: Variant in npcs.keys():
		var npc_state: Dictionary = npcs[npc_id] as Dictionary
		if str(npc_state.get("placeId", "")) != str(current_scene.get("id", "")):
			continue
		var actor: TimeEchoNPCActor = NPC_SCENE.instantiate() as TimeEchoNPCActor
		actors.add_child(actor)
		actor.configure(DataManager.get_npc(str(npc_id)), npc_state)
		npc_actors[npc_id] = actor


func _update_player_light() -> void:
	var light: PointLight2D = player.get_node_or_null("LevelArtFlashlight") as PointLight2D
	if light == null:
		light = PointLight2D.new()
		light.name = "LevelArtFlashlight"
		light.position = Vector2(0, -18)
		light.color = Color("f2bd72")
		light.energy = 0.46
		light.texture_scale = 2.5
		light.blend_mode = Light2D.BLEND_MODE_ADD
		if _player_light_texture == null:
			_player_light_texture = _make_player_light_texture()
		light.texture = _player_light_texture
		player.add_child(light)
	light.enabled = str(current_scene.get("id", "")) == "low-tide-cave" and InventoryManager.has_item(state, "flashlight")


func _make_player_light_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y: int in range(64):
		for x: int in range(64):
			var distance: float = Vector2(x - 31.5, y - 31.5).length() / 31.5
			var alpha: float = clampf(1.0 - distance, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha * alpha))
	return ImageTexture.create_from_image(image)


func _update_npcs(delta: float) -> void:
	var npcs: Dictionary = state.get("npcs", {}) as Dictionary
	var expected_ids: Array = []
	for npc_id: Variant in npcs.keys():
		var npc_state: Dictionary = npcs[npc_id] as Dictionary
		if str(npc_state.get("placeId", "")) == str(current_scene.get("id", "")):
			expected_ids.append(npc_id)
	if expected_ids.size() != npc_actors.size() or expected_ids.any(func(id: Variant) -> bool: return not npc_actors.has(id)):
		_rebuild_npcs()
	for npc_id: Variant in npc_actors.keys():
		var actor: TimeEchoNPCActor = npc_actors[npc_id] as TimeEchoNPCActor
		var npc_state: Dictionary = npcs[npc_id] as Dictionary
		actor.update_from_state(npc_state, delta)
		npc_state["x"] = actor.position.x
		npc_state["y"] = actor.position.y


func _rebuild_collisions() -> void:
	for child: Node in collisions.get_children():
		child.queue_free()
	var width: float = float(current_scene.get("width", 768.0))
	var height: float = float(current_scene.get("height", 480.0))
	_add_solid(Rect2(-8, 0, 16, height))
	_add_solid(Rect2(width - 8, 0, 16, height))
	_add_solid(Rect2(0, -8, width, 16))
	_add_solid(Rect2(0, height - 8, width, 16))
	if world_view.has_art_layout():
		for rect: Rect2 in world_view.get_collision_rects():
			_add_solid(rect)
		return
	# Formal fallback for a missing art layout; it preserves old gameplay rather
	# than crashing, but is reported by Art Debug.
	for raw: Variant in current_scene.get("obstacles", []):
		var item: Dictionary = raw as Dictionary
		if item.get("collision", true) != false:
			_add_solid(_rect(item))
	for raw: Variant in current_scene.get("buildings", []):
		var item: Dictionary = raw as Dictionary
		if item.get("collision", true) == false:
			continue
		var rect: Rect2 = _rect(item)
		_add_solid(Rect2(rect.position.x, rect.position.y + rect.size.y * 0.36, rect.size.x, rect.size.y * 0.64))
	for raw: Variant in current_scene.get("furniture", []):
		var item: Dictionary = raw as Dictionary
		if item.get("collision", true) == false:
			continue
		var rect: Rect2 = _rect(item)
		var inset: float = minf(4.0, rect.size.x * 0.12)
		_add_solid(Rect2(rect.position.x + inset, rect.position.y + rect.size.y * 0.35, maxf(2.0, rect.size.x - inset * 2.0), maxf(2.0, rect.size.y * 0.65)))


func _add_solid(rect: Rect2) -> void:
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var body := StaticBody2D.new()
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	shape_node.shape = shape
	shape_node.position = rect.get_center()
	body.add_child(shape_node)
	collisions.add_child(body)


func _on_player_moved(world_position: Vector2, facing: String, running: bool) -> void:
	var player_state: Dictionary = state.get("player", {}) as Dictionary
	player_state["x"] = world_position.x
	player_state["y"] = world_position.y
	player_state["facing"] = facing
	state["player"] = player_state
	var now: int = Time.get_ticks_msec()
	if now - _last_step_at > (170 if running else 290):
		_last_step_at = now
		AudioManager.play("step")


func _request_nearest_interaction() -> void:
	var target: Dictionary = get_nearest_interaction()
	if not target.is_empty():
		interaction_requested.emit(target)


func _target_at_point(point: Vector2) -> Dictionary:
	for raw: Variant in current_scene.get("landmarks", []):
		var item: Dictionary = raw as Dictionary
		var hit_rect: Rect2 = world_view.get_gameplay_rect(str(item.get("id", "")), "interaction_rect", _rect(item))
		if bool(item.get("interactive", false)) and hit_rect.grow(8).has_point(point):
			return {"type": "landmark", "value": item, "label": str(item.get("label", "检查")), "distance": 0.0}
	for raw: Variant in current_scene.get("portals", []):
		var portal: Dictionary = raw as Dictionary
		var hit_rect: Rect2 = world_view.get_gameplay_rect(str(portal.get("id", "")), "trigger_rect", _rect(portal))
		if SceneManager.can_reveal_portal(portal, state) and hit_rect.grow(8).has_point(point):
			return {"type": "portal", "value": portal, "label": str(portal.get("label", "前往")), "distance": 0.0}
	for npc_id: Variant in npc_actors.keys():
		var actor: TimeEchoNPCActor = npc_actors[npc_id] as TimeEchoNPCActor
		if actor.position.distance_to(point) <= 28.0:
			return {"type": "npc", "value": DataManager.get_npc(str(npc_id)), "label": "交谈", "distance": 0.0}
	return {}


func _update_daylight() -> void:
	if current_scene.is_empty() or not is_instance_valid(canvas_modulate):
		return
	var canvas: Dictionary = world_view.get_art_layout().get("canvas", {}) as Dictionary
	if str(current_scene.get("kind", "outdoor")) == "interior":
		var ambient: Color = Color.from_string(str(canvas.get("ambient_color", "#d7c8a9")), Color("d7c8a9"))
		canvas_modulate.color = ambient
		return
	var minute: int = int(state.get("minute", 360))
	if _time_of_day_override == "day": minute = 10 * 60
	elif _time_of_day_override == "dusk": minute = 18 * 60 + 30
	elif _time_of_day_override == "night": minute = 23 * 60
	var hour: float = minute / 60.0
	var brightness: float = clampf(0.58 + sin((hour - 6.0) / 24.0 * TAU) * 0.34, 0.3, 1.0)
	var tint: Color = Color.from_string(str(canvas.get("day_tint", "#fff7dc")), Color("fff7dc"))
	canvas_modulate.color = Color(brightness * tint.r, brightness * tint.g, brightness * tint.b + 0.05)


func _rect(item: Dictionary) -> Rect2:
	return Rect2(float(item.get("x", 0.0)), float(item.get("y", 0.0)), float(item.get("w", 24.0)), float(item.get("h", 24.0)))


func _point_rect_distance(point: Vector2, rect: Rect2) -> float:
	var closest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
	return point.distance_to(closest)


func _world_to_cell(point: Vector2, grid: int) -> Vector2i:
	return Vector2i(floori(point.x / grid), floori(point.y / grid))


func _cell_center(cell: Vector2i, grid: int) -> Vector2:
	return Vector2((cell.x + 0.5) * grid, (cell.y + 0.5) * grid)


func _cell_is_blocked(cell: Vector2i, grid: int, bounds: Rect2, obstacles: Array[Rect2]) -> bool:
	var point: Vector2 = _cell_center(cell, grid)
	if not bounds.grow(-8.0).has_point(point):
		return true
	for obstacle: Rect2 in obstacles:
		if obstacle.grow(7.0).has_point(point):
			return true
	return false


func _nearest_open_cell(origin: Vector2i, grid: int, bounds: Rect2, obstacles: Array[Rect2]) -> Vector2i:
	if not _cell_is_blocked(origin, grid, bounds, obstacles):
		return origin
	for radius: int in range(1, 12):
		for y: int in range(origin.y - radius, origin.y + radius + 1):
			for x: int in range(origin.x - radius, origin.x + radius + 1):
				if abs(x - origin.x) != radius and abs(y - origin.y) != radius:
					continue
				var candidate := Vector2i(x, y)
				if not _cell_is_blocked(candidate, grid, bounds, obstacles):
					return candidate
	return origin
