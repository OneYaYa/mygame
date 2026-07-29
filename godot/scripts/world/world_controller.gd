class_name TimeEchoWorldController
extends Node2D

signal interaction_requested(target: Dictionary)

const NPC_SCENE: PackedScene = preload("res://scenes/characters/npc.tscn")

@onready var world_view: TimeEchoWorldView = $WorldView
@onready var collisions: Node2D = $Collisions
@onready var actors: Node2D = $Actors
@onready var player: TimeEchoPlayer = $Player
@onready var canvas_modulate: CanvasModulate = $CanvasModulate

var current_scene: Dictionary = {}
var state: Dictionary = {}
var npc_actors: Dictionary = {}
var _last_step_at: int = 0


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
	_update_daylight()


func set_input_enabled(value: bool) -> void:
	player.active = value


func get_nearest_interaction() -> Dictionary:
	if current_scene.is_empty():
		return {}
	var point: Vector2 = player.position
	var candidates: Array[Dictionary] = []
	var npcs: Dictionary = state.get("npcs", {}) as Dictionary
	for npc_id: Variant in npc_actors.keys():
		var npc_state: Dictionary = npcs.get(npc_id, {}) as Dictionary
		var distance: float = point.distance_to(Vector2(float(npc_state.get("x", 0.0)), float(npc_state.get("y", 0.0))))
		if distance <= 62.0:
			var profile: Dictionary = DataManager.get_npc(str(npc_id))
			candidates.append({"type": "npc", "value": profile, "distance": distance, "label": "与 %s 交谈" % profile.get("name", npc_id)})
	for raw: Variant in current_scene.get("landmarks", []):
		var landmark: Dictionary = raw as Dictionary
		if not bool(landmark.get("interactive", false)):
			continue
		var distance: float = _point_rect_distance(point, _rect(landmark))
		if distance <= 52.0:
			candidates.append({"type": "landmark", "value": landmark, "distance": distance, "label": str(landmark.get("label", "检查"))})
	for raw: Variant in current_scene.get("portals", []):
		var portal: Dictionary = raw as Dictionary
		if not SceneManager.can_reveal_portal(portal, state):
			continue
		var distance: float = _point_rect_distance(point, _rect(portal))
		if distance <= 58.0:
			candidates.append({"type": "portal", "value": portal, "distance": distance, "label": str(portal.get("label", "前往"))})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
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
		push_error("无法实例化地点：%s" % place_id)
		return
	world_view.set_world(current_scene, state)
	_rebuild_collisions()
	_rebuild_npcs()
	var player_state: Dictionary = state.get("player", {}) as Dictionary
	var bounds := Rect2(0, 0, float(current_scene.get("width", 768)), float(current_scene.get("height", 480)))
	player.configure(Vector2(float(player_state.get("x", 384.0)), float(player_state.get("y", 350.0))), str(player_state.get("facing", "down")), bounds)
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(bounds.size.x)
	camera.limit_bottom = int(bounds.size.y)
	EventBus.scene_changed.emit(current_scene)


func _rebuild_npcs() -> void:
	for child: Node in actors.get_children():
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
		(npc_actors[npc_id] as TimeEchoNPCActor).update_from_state(npcs[npc_id] as Dictionary, delta)
		var actor: TimeEchoNPCActor = npc_actors[npc_id] as TimeEchoNPCActor
		var npc_state: Dictionary = npcs[npc_id] as Dictionary
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
	for raw: Variant in current_scene.get("obstacles", []):
		var item: Dictionary = raw as Dictionary
		if item.get("collision", true) != false: _add_solid(_rect(item))
	for raw: Variant in current_scene.get("buildings", []):
		var item: Dictionary = raw as Dictionary
		if item.get("collision", true) == false: continue
		var rect: Rect2 = _rect(item)
		_add_solid(Rect2(rect.position.x, rect.position.y + rect.size.y * 0.36, rect.size.x, rect.size.y * 0.64))
	for raw: Variant in current_scene.get("furniture", []):
		var item: Dictionary = raw as Dictionary
		if item.get("collision", true) == false: continue
		var rect: Rect2 = _rect(item)
		var inset: float = minf(4.0, rect.size.x * 0.12)
		_add_solid(Rect2(rect.position.x + inset, rect.position.y + rect.size.y * 0.35, maxf(2.0, rect.size.x - inset * 2.0), maxf(2.0, rect.size.y * 0.65)))
	for group: String in ["zones", "landmarks", "decorations"]:
		for raw: Variant in current_scene.get(group, []):
			var item: Dictionary = raw as Dictionary
			if bool(item.get("collision", false)): _add_solid(_rect(item))


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
		if bool(item.get("interactive", false)) and _rect(item).grow(8).has_point(point):
			return {"type": "landmark", "value": item, "label": str(item.get("label", "检查")), "distance": 0.0}
	for raw: Variant in current_scene.get("portals", []):
		var portal: Dictionary = raw as Dictionary
		if SceneManager.can_reveal_portal(portal, state) and _rect(portal).grow(8).has_point(point):
			return {"type": "portal", "value": portal, "label": str(portal.get("label", "前往")), "distance": 0.0}
	for npc_id: Variant in npc_actors.keys():
		var actor: TimeEchoNPCActor = npc_actors[npc_id] as TimeEchoNPCActor
		if actor.position.distance_to(point) <= 28.0:
			return {"type": "npc", "value": DataManager.get_npc(str(npc_id)), "label": "交谈", "distance": 0.0}
	return {}


func _update_daylight() -> void:
	if str(current_scene.get("kind", "outdoor")) == "interior":
		canvas_modulate.color = Color("d8cfae") if not TimeManager.scene_pauses_time(str(current_scene.get("id", ""))) else Color("b79a91")
		return
	var minute: int = int(state.get("minute", 360))
	var hour: float = minute / 60.0
	var brightness: float = clampf(0.55 + sin((hour - 6.0) / 24.0 * TAU) * 0.35, 0.28, 1.0)
	canvas_modulate.color = Color(brightness, brightness * 0.98, brightness * 0.88 + 0.08)


func _rect(item: Dictionary) -> Rect2:
	return Rect2(float(item.get("x", 0.0)), float(item.get("y", 0.0)), float(item.get("w", 24.0)), float(item.get("h", 24.0)))


func _point_rect_distance(point: Vector2, rect: Rect2) -> float:
	var closest := Vector2(clampf(point.x, rect.position.x, rect.end.x), clampf(point.y, rect.position.y, rect.end.y))
	return point.distance_to(closest)

