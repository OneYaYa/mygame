class_name TimeEchoArtDebugManager
extends Node2D

@export var enabled_by_default: bool = false

var art_debug_enabled: bool = false
var map_id: String = ""
var scene_data: Dictionary = {}
var layout: Dictionary = {}
var asset_errors: PackedStringArray = []
var validation_warnings: PackedStringArray = []


func _ready() -> void:
	art_debug_enabled = enabled_by_default or "--art-debug" in OS.get_cmdline_user_args()
	visible = art_debug_enabled
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo and (event as InputEventKey).keycode == KEY_F3:
		set_enabled(not art_debug_enabled)
		get_viewport().set_input_as_handled()


func set_enabled(value: bool) -> void:
	art_debug_enabled = value
	visible = value
	queue_redraw()


func configure(scene: Dictionary, art_layout: Dictionary, load_errors: PackedStringArray, warnings: PackedStringArray = []) -> void:
	scene_data = scene
	layout = art_layout
	map_id = str(scene.get("id", ""))
	asset_errors = load_errors
	validation_warnings = warnings
	queue_redraw()


func _draw() -> void:
	if not art_debug_enabled:
		return
	var width: float = float(scene_data.get("width", 768))
	var height: float = float(scene_data.get("height", 480))
	draw_rect(Rect2(2, 2, width - 4, height - 4), Color("e4bd55"), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(14, 22), "ART DEBUG · %s" % map_id, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("ffe37f"))
	for raw: Variant in layout.get("objects", []):
		var item: Dictionary = raw as Dictionary
		var position := _vector(item.get("position", [0, 0]))
		var size := _vector(item.get("display_size", [24, 24]))
		var anchor := _vector(item.get("anchor", [0.5, 1.0]))
		var rect := Rect2(position - size * anchor, size)
		draw_rect(rect, Color(0.38, 0.8, 1.0, 0.72), false, 1.0)
		draw_line(position - Vector2(4, 0), position + Vector2(4, 0), Color("ffdb65"), 1.0)
		draw_line(position - Vector2(0, 4), position + Vector2(0, 4), Color("ffdb65"), 1.0)
		draw_string(ThemeDB.fallback_font, rect.position - Vector2(0, 3), "%s · %s" % [item.get("object_id", "?"), item.get("asset_id", item.get("procedural_type", "procedural"))], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("d9f3ff"))
	for raw: Variant in layout.get("collision_rects", []):
		var item: Dictionary = raw as Dictionary
		draw_rect(_rect(item.get("rect", [])), Color(1.0, 0.25, 0.2, 0.78), false, 2.0)
	var overrides: Dictionary = layout.get("gameplay_overrides", {}) as Dictionary
	for object_id: Variant in overrides.keys():
		var item: Dictionary = overrides[object_id] as Dictionary
		if item.has("trigger_rect"):
			draw_rect(_rect(item["trigger_rect"]), Color(1.0, 0.82, 0.2, 0.86), false, 2.0)
		if item.has("interaction_rect"):
			draw_rect(_rect(item["interaction_rect"]), Color(0.25, 1.0, 0.65, 0.86), false, 2.0)
	var message_y: float = 42.0
	for message: String in asset_errors + validation_warnings:
		draw_string(ThemeDB.fallback_font, Vector2(14, message_y), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("ff8d80"))
		message_y += 14.0


func _vector(value: Variant) -> Vector2:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() == 2:
		return Vector2(float((value as Array)[0]), float((value as Array)[1]))
	return Vector2.ZERO


func _rect(value: Variant) -> Rect2:
	if typeof(value) == TYPE_ARRAY and (value as Array).size() == 4:
		return Rect2(float((value as Array)[0]), float((value as Array)[1]), float((value as Array)[2]), float((value as Array)[3]))
	return Rect2()
