class_name TimeEchoArtObject2D
extends Node2D

@onready var contact_shadow: Polygon2D = $ContactShadow
@onready var visual: Sprite2D = $Visual
@onready var foreground_visual: Sprite2D = $ForegroundVisual
@onready var collision_body: StaticBody2D = $CollisionBody
@onready var interaction_area: Area2D = $InteractionArea
@onready var entrance_marker: Marker2D = $EntranceMarker
@onready var navigation_obstacle: Node2D = $NavigationObstacle
@onready var debug_overlay: Node2D = $DebugOverlay

var object_data: Dictionary = {}
var asset_data: Dictionary = {}
var display_size: Vector2 = Vector2(32, 32)
var _procedural_type: String = ""
var _primary: Color = Color("78664f")
var _secondary: Color = Color("c5aa72")


func configure(data: Dictionary, asset: Dictionary, texture: Texture2D) -> void:
	object_data = data
	asset_data = asset
	name = str(data.get("object_id", "ArtObject"))
	position = _rounded_vector(data.get("position", [0, 0]))
	var size_values: Array = data.get("display_size", asset.get("recommended_display_size", [32, 32])) as Array
	display_size = Vector2(float(size_values[0]), float(size_values[1])) if size_values.size() == 2 else Vector2(32, 32)
	var anchor_values: Array = data.get("anchor", asset.get("anchor", [0.5, 1.0])) as Array
	var anchor := Vector2(float(anchor_values[0]), float(anchor_values[1])) if anchor_values.size() == 2 else Vector2(0.5, 1.0)
	var center_offset := Vector2((0.5 - anchor.x) * display_size.x, (0.5 - anchor.y) * display_size.y)
	visual.position = center_offset.round()
	visual.texture = texture
	visual.flip_h = bool(data.get("mirror_x", false)) and bool(asset.get("can_mirror", false))
	visual.modulate.a = clampf(float(data.get("opacity", 1.0)), 0.0, 1.0)
	foreground_visual.visible = false
	_procedural_type = str(data.get("procedural_type", ""))
	if texture == null and _procedural_type.is_empty():
		# A missing or disabled texture remains visible as a restrained, semantic
		# fallback instead of deleting collision/interactions or aborting the map.
		_procedural_type = "missing"
	_primary = Color.from_string(str(data.get("color", "#78664f")), Color("78664f"))
	_secondary = Color.from_string(str(data.get("accent", "#c5aa72")), Color("c5aa72"))
	var sort_y: int = int(data.get("sort_y", position.y))
	z_index = clampi(int(data.get("z_index", sort_y)), -4096, 4096)
	_build_shadow(bool(data.get("contact_shadow", asset.get("contact_shadow", false))))
	_build_collision(data.get("collision_rect", []))
	queue_redraw()


func visual_rect() -> Rect2:
	var anchor_values: Array = object_data.get("anchor", asset_data.get("anchor", [0.5, 1.0])) as Array
	var anchor := Vector2(float(anchor_values[0]), float(anchor_values[1])) if anchor_values.size() == 2 else Vector2(0.5, 1.0)
	return Rect2(position - display_size * anchor, display_size)


func _draw() -> void:
	if visual.texture != null or _procedural_type.is_empty():
		return
	var rect := Rect2(-display_size * Vector2(0.5, 1.0), display_size)
	match _procedural_type:
		"rug": _draw_rug(rect)
		"threshold_wear": _draw_threshold_wear(rect)
		"table", "reading_table", "chart_table": _draw_table(rect)
		"chair": _draw_chair(rect)
		"pew": _draw_pew(rect)
		"console", "clockwork", "development_bench": _draw_console(rect)
		"door": _draw_door(rect)
		"window": _draw_window(rect)
		"stairs": _draw_stairs(rect)
		"wall_frame", "photo", "notice": _draw_wall_frame(rect)
		"beam": _draw_beam(rect)
		"rock": _draw_rock(rect)
		"bucket": _draw_bucket(rect)
		"rope_hang": _draw_rope_hang(rect)
		"bell", "hammer": _draw_bell(rect)
		"gear": _draw_gear(rect)
		"slot": _draw_slot(rect)
		"signal": _draw_signal(rect)
		"safelight": _draw_safelight(rect)
		"missing":
			draw_rect(rect, _primary.darkened(0.2))
			draw_rect(rect.grow(-3), _secondary, false, 2.0)
			draw_line(rect.position + Vector2(5, 5), rect.end - Vector2(5, 5), _secondary.darkened(0.2), 2.0)
			draw_line(Vector2(rect.end.x - 5, rect.position.y + 5), Vector2(rect.position.x + 5, rect.end.y - 5), _secondary.darkened(0.2), 2.0)
		_:
			draw_rect(rect, _primary)
			draw_rect(rect.grow(-2), _secondary, false, 2.0)


func _build_shadow(enabled: bool) -> void:
	contact_shadow.visible = enabled
	if not enabled:
		return
	var size_values: Array = object_data.get("shadow_size", [maxf(16.0, display_size.x * 0.62), clampf(display_size.y * 0.12, 7.0, 18.0)]) as Array
	var shadow_size := Vector2(float(size_values[0]), float(size_values[1]))
	var offset_values: Array = object_data.get("shadow_offset", [4, -3]) as Array
	contact_shadow.position = Vector2(float(offset_values[0]), float(offset_values[1])).round()
	var points := PackedVector2Array()
	for index: int in range(16):
		var angle: float = TAU * float(index) / 16.0
		points.append(Vector2(cos(angle) * shadow_size.x * 0.5, sin(angle) * shadow_size.y * 0.5))
	contact_shadow.polygon = points
	contact_shadow.color = Color(0.055, 0.07, 0.065, float(object_data.get("shadow_opacity", 0.34)))


func _build_collision(values: Variant) -> void:
	for child: Node in collision_body.get_children():
		child.queue_free()
	if typeof(values) != TYPE_ARRAY or (values as Array).size() != 4:
		collision_body.process_mode = Node.PROCESS_MODE_DISABLED
		return
	# Runtime collision is built centrally by WorldController. This shape is an
	# inspectable editor/debug representation and remains disabled in play.
	var rect_values: Array = values as Array
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(float(rect_values[2]), float(rect_values[3]))
	shape_node.position = Vector2(float(rect_values[0]), float(rect_values[1])) + shape.size * 0.5 - position
	shape_node.shape = shape
	shape_node.disabled = true
	collision_body.add_child(shape_node)
	collision_body.process_mode = Node.PROCESS_MODE_DISABLED


func _draw_rug(rect: Rect2) -> void:
	draw_rect(rect, _primary)
	draw_rect(rect.grow(-3), _secondary, false, 2.0)
	draw_line(rect.position + Vector2(8, rect.size.y * 0.5), rect.end - Vector2(8, rect.size.y * 0.5), _secondary.darkened(0.25), 2.0)


func _draw_threshold_wear(rect: Rect2) -> void:
	# A broken, low-contrast contact patch reads as foot traffic rather than a
	# debug rectangle or floating platform.
	var inset := Rect2(rect.position + Vector2(5, 4), rect.size - Vector2(10, 8))
	for index: int in range(7):
		var x: float = inset.position.x + fmod(float(index * 17 + 5), maxf(1.0, inset.size.x - 5.0))
		var y: float = inset.position.y + fmod(float(index * 11 + 3), maxf(1.0, inset.size.y - 2.0))
		var length: float = 3.0 + float(index % 3) * 2.0
		draw_line(Vector2(x, y), Vector2(minf(inset.end.x, x + length), y), _primary, 2.0)
	for index: int in range(4):
		var pebble := inset.position + Vector2(8 + index * 13, inset.size.y - float((index * 3) % 5))
		draw_circle(pebble, 1.5, _secondary.darkened(0.15))


func _draw_table(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(5, rect.size.y - 16), Vector2(6, 16)), _primary.darkened(0.35))
	draw_rect(Rect2(rect.end - Vector2(11, 16), Vector2(6, 16)), _primary.darkened(0.35))
	var top := Rect2(rect.position, Vector2(rect.size.x, rect.size.y - 12))
	draw_rect(top, _primary)
	draw_rect(top.grow(-3), _secondary, false, 2.0)


func _draw_chair(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(2, 0), Vector2(rect.size.x - 4, 8)), _primary.darkened(0.25))
	draw_rect(Rect2(rect.position + Vector2(4, 8), Vector2(rect.size.x - 8, rect.size.y - 13)), _primary)
	draw_line(rect.position + Vector2(5, rect.size.y - 5), rect.end - Vector2(rect.size.x - 5, 0), _secondary, 2.0)


func _draw_pew(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(3, 0), Vector2(rect.size.x - 6, 9)), _primary.darkened(0.28))
	draw_rect(Rect2(rect.position + Vector2(0, 8), Vector2(rect.size.x, rect.size.y - 14)), _primary)
	draw_rect(Rect2(rect.position + Vector2(5, rect.size.y - 8), Vector2(rect.size.x - 10, 5)), _secondary.darkened(0.22))


func _draw_console(rect: Rect2) -> void:
	draw_rect(rect, _primary.darkened(0.28))
	draw_rect(Rect2(rect.position + Vector2(4, 4), Vector2(rect.size.x - 8, rect.size.y * 0.48)), _primary)
	draw_rect(Rect2(rect.position + Vector2(8, 9), Vector2(rect.size.x - 16, maxf(8.0, rect.size.y * 0.2))), _secondary.darkened(0.35))
	for index: int in range(3):
		draw_circle(rect.position + Vector2(14 + index * 12, rect.size.y * 0.35), 2.5, _secondary)


func _draw_door(rect: Rect2) -> void:
	draw_rect(rect, _primary.darkened(0.38))
	draw_rect(rect.grow(-3), _primary)
	draw_circle(rect.position + Vector2(rect.size.x - 7, rect.size.y * 0.54), 2.0, _secondary)


func _draw_window(rect: Rect2) -> void:
	draw_rect(rect, _primary.darkened(0.46))
	draw_rect(rect.grow(-3), _secondary.darkened(0.18))
	var glass := rect.grow(-6)
	draw_rect(glass, Color("738b89"))
	draw_line(Vector2(glass.get_center().x, glass.position.y), Vector2(glass.get_center().x, glass.end.y), _primary.darkened(0.3), 2.0)
	draw_line(Vector2(glass.position.x, glass.get_center().y), Vector2(glass.end.x, glass.get_center().y), _primary.darkened(0.3), 2.0)
	draw_line(glass.position + Vector2(3, 3), glass.position + Vector2(10, 3), Color("b9c8b1"), 2.0)


func _draw_stairs(rect: Rect2) -> void:
	draw_rect(rect, _primary.darkened(0.46))
	draw_rect(rect.grow(-4), _primary)
	var inner: Rect2 = rect.grow(-7)
	draw_rect(inner, _primary.darkened(0.14))
	var step_count: int = maxi(4, floori(inner.size.y / 13.0))
	for index: int in range(step_count + 1):
		var y: float = inner.position.y + inner.size.y * float(index) / float(step_count)
		draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), _secondary.darkened(0.12), 2.0)
	draw_line(inner.position + Vector2(5, 0), Vector2(inner.position.x + 5, inner.end.y), _secondary, 2.0)
	draw_line(Vector2(inner.end.x - 5, inner.position.y), inner.end - Vector2(5, 0), _secondary, 2.0)


func _draw_wall_frame(rect: Rect2) -> void:
	draw_rect(rect, _primary.darkened(0.4))
	draw_rect(rect.grow(-3), _secondary)
	draw_rect(rect.grow(-6), _primary.lightened(0.08))


func _draw_beam(rect: Rect2) -> void:
	draw_rect(rect, _primary.darkened(0.36))
	draw_line(rect.position + Vector2(5, 2), rect.end - Vector2(5, rect.size.y - 2), _secondary.darkened(0.2), 2.0)


func _draw_rock(rect: Rect2) -> void:
	var points := PackedVector2Array([rect.position + Vector2(3, rect.size.y * 0.55), rect.position + Vector2(rect.size.x * 0.25, 4), rect.position + Vector2(rect.size.x * 0.72, 0), rect.end - Vector2(0, 6), rect.end - Vector2(rect.size.x * 0.55, 0)])
	draw_colored_polygon(points, _primary)
	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, _secondary.darkened(0.25), 2.0)


func _draw_bucket(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(3, 7), Vector2(rect.size.x - 6, rect.size.y - 7)), _primary)
	draw_arc(rect.position + Vector2(rect.size.x * 0.5, 8), rect.size.x * 0.34, PI, TAU, 12, _secondary, 2.0)


func _draw_rope_hang(rect: Rect2) -> void:
	for index: int in range(3):
		var x: float = rect.position.x + 5 + index * (rect.size.x - 10) / 2.0
		draw_line(Vector2(x, rect.position.y), Vector2(x + (2 if index % 2 == 0 else -2), rect.end.y), _primary, 3.0)


func _draw_bell(rect: Rect2) -> void:
	draw_colored_polygon(PackedVector2Array([rect.position + Vector2(rect.size.x * 0.5, 3), rect.position + Vector2(5, rect.size.y - 8), rect.end - Vector2(5, 8)]), _primary)
	draw_line(rect.position + Vector2(3, rect.size.y - 7), rect.end - Vector2(3, 7), _secondary, 4.0)
	draw_circle(rect.position + Vector2(rect.size.x * 0.5, rect.size.y - 3), 3.0, _secondary.darkened(0.3))


func _draw_gear(rect: Rect2) -> void:
	var radius: float = minf(rect.size.x, rect.size.y) * 0.42
	var center: Vector2 = rect.get_center()
	draw_circle(center, radius, _primary)
	draw_circle(center, radius * 0.42, _secondary.darkened(0.35))
	for index: int in range(8):
		var angle: float = TAU * index / 8.0
		draw_line(center + Vector2(cos(angle), sin(angle)) * radius * 0.72, center + Vector2(cos(angle), sin(angle)) * radius, _secondary, 3.0)


func _draw_slot(rect: Rect2) -> void:
	draw_rect(rect, _primary.darkened(0.4))
	draw_rect(rect.grow(-3), _secondary, false, 2.0)
	draw_circle(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.18, _secondary.darkened(0.25))


func _draw_signal(rect: Rect2) -> void:
	draw_rect(rect, _primary.darkened(0.4))
	for index: int in range(3):
		var light_color: Color = [Color("d26858"), Color("d9b75d"), Color("8db9b0")][index]
		draw_circle(rect.position + Vector2(rect.size.x * (0.24 + index * 0.26), rect.size.y * 0.45), minf(7.0, rect.size.y * 0.17), light_color)


func _draw_safelight(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.42, rect.size.y * 0.4), Vector2(rect.size.x * 0.16, rect.size.y * 0.6)), _primary.darkened(0.45))
	draw_circle(rect.position + Vector2(rect.size.x * 0.5, rect.size.y * 0.34), minf(rect.size.x, rect.size.y) * 0.28, _secondary)


func _rounded_vector(value: Variant) -> Vector2:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() == 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1])).round()
	return Vector2.ZERO
