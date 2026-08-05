class_name FacilityNodeMap
extends Control


const BG := Color("07131a")
const GRID := Color(0.18, 0.46, 0.50, 0.08)
const LINK := Color("31515b")
const LINK_OPEN := Color("54b7b5")
const LINK_LOCKED := Color("70494a")
const NODE := Color("132b34")
const NODE_EDGE := Color("3d7178")
const ACTIVE := Color("d6a552")
const SAFE := Color("61baa3")
const DANGER := Color("d35e57")
const MUTED := Color("789198")

var _rooms: Array[Dictionary] = []
var _links: Array[Dictionary] = []
var _npc_room := ""
var _selected_room := ""


func _ready() -> void:
	custom_minimum_size = Vector2(320, 230)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_defaults()


func set_snapshot(snapshot: Dictionary) -> void:
	_rooms = _normalize_rooms(snapshot)
	_links = _normalize_links(snapshot)
	var npc: Dictionary = _dictionary(snapshot.get("npc", {}))
	var requested_room := str(npc.get("room_id", npc.get("location_id", snapshot.get("room_id", snapshot.get("npc_room", "")))))
	_npc_room = requested_room
	_selected_room = str(snapshot.get("selected_room", _npc_room))
	if _rooms.is_empty():
		_set_defaults()
		if not requested_room.is_empty():
			_npc_room = requested_room
			_selected_room = requested_room
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	for x: int in range(12, int(size.x), 24):
		draw_line(Vector2(x, 0), Vector2(x, size.y), GRID, 1.0)
	for y: int in range(12, int(size.y), 24):
		draw_line(Vector2(0, y), Vector2(size.x, y), GRID, 1.0)
	var centers := _room_centers()
	for link: Dictionary in _links:
		var from_id := str(link.get("from", link.get("a", "")))
		var to_id := str(link.get("to", link.get("b", "")))
		if not centers.has(from_id) or not centers.has(to_id):
			continue
		var state := str(link.get("state", "open"))
		var color := LINK_OPEN if state in ["open", "powered", "safe"] else LINK_LOCKED if state in ["locked", "blocked", "danger"] else LINK
		draw_line(centers[from_id], centers[to_id], color, 3.0)
		draw_circle(centers[from_id].lerp(centers[to_id], 0.5), 3.0, color)
	for room: Dictionary in _rooms:
		_draw_room(room, centers.get(str(room.get("id", "")), Vector2.ZERO))
	draw_string(ThemeDB.fallback_font, Vector2(12, 20), "FACILITY ROUTING / 设施链路", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)


func _draw_room(room: Dictionary, center: Vector2) -> void:
	var room_id := str(room.get("id", ""))
	var rect := Rect2(center - Vector2(44, 23), Vector2(88, 46))
	var status := str(room.get("status", "unknown"))
	var fill := NODE
	var edge := NODE_EDGE
	if status in ["danger", "breach", "fire", "offline"]:
		edge = DANGER
	elif status in ["safe", "cleared", "powered"]:
		edge = SAFE
	if room_id == _selected_room:
		fill = Color("1b3339")
	if room_id == _npc_room:
		edge = ACTIVE
	draw_rect(rect, fill)
	draw_rect(rect, edge, false, 2.0)
	if room_id == _npc_room:
		draw_circle(Vector2(rect.position.x + 9, rect.position.y + 9), 4.0, ACTIVE)
	var label := str(room.get("label", room.get("name", room_id))).left(12)
	draw_string(ThemeDB.fallback_font, center + Vector2(-36, 5), label, HORIZONTAL_ALIGNMENT_CENTER, 72, 12, Color("d7e2d8"))
	var code := str(room.get("code", room_id)).to_upper().left(8)
	draw_string(ThemeDB.fallback_font, center + Vector2(-36, 19), code, HORIZONTAL_ALIGNMENT_CENTER, 72, 9, MUTED)


func _room_centers() -> Dictionary:
	var centers: Dictionary = {}
	var count := maxi(_rooms.size(), 1)
	if count == 5:
		var positions := [
			Vector2(size.x * 0.18, size.y * 0.54),
			Vector2(size.x * 0.40, size.y * 0.32),
			Vector2(size.x * 0.62, size.y * 0.54),
			Vector2(size.x * 0.82, size.y * 0.32),
			Vector2(size.x * 0.82, size.y * 0.75),
		]
		for index: int in range(_rooms.size()):
			centers[str(_rooms[index].get("id", index))] = positions[index]
		return centers
	var columns := ceili(sqrt(float(count)))
	for index: int in range(_rooms.size()):
		var row := index / columns
		var column := index % columns
		var x := (float(column) + 0.5) / float(columns)
		var rows := ceili(float(count) / float(columns))
		var y := (float(row) + 0.7) / float(rows + 0.3)
		centers[str(_rooms[index].get("id", index))] = Vector2(size.x * x, size.y * y)
	return centers


func _normalize_rooms(snapshot: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source: Array = _array(snapshot.get("rooms", snapshot.get("nodes", [])))
	for value: Variant in source:
		if value is Dictionary:
			var room := (value as Dictionary).duplicate(true)
			if not room.has("status"):
				room["status"] = "locked" if bool(room.get("locked", false)) else "safe" if bool(room.get("current", false)) else "unknown"
			result.append(room)
	return result


func _normalize_links(snapshot: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source: Array = _array(snapshot.get("links", snapshot.get("connections", [])))
	for value: Variant in source:
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	if result.is_empty():
		var current := str(snapshot.get("room_id", ""))
		for target: Variant in _array(snapshot.get("reachable_rooms", [])):
			result.append({"from": current, "to": str(target), "state": "open"})
	return result


func _set_defaults() -> void:
	_rooms = [
		{"id": "relay", "label": "中继舱", "code": "RLY-01", "status": "safe"},
		{"id": "junction", "label": "联络井", "code": "JNC-02", "status": "unknown"},
		{"id": "workshop", "label": "维修间", "code": "WRK-03", "status": "unknown"},
		{"id": "life_support", "label": "生命支持", "code": "LFS-04", "status": "offline"},
		{"id": "escape", "label": "逃生舱", "code": "ESC-05", "status": "locked"},
	]
	_links = [
		{"from": "relay", "to": "junction", "state": "open"},
		{"from": "junction", "to": "workshop", "state": "unknown"},
		{"from": "workshop", "to": "life_support", "state": "locked"},
		{"from": "workshop", "to": "escape", "state": "unknown"},
	]
	_npc_room = "relay"


func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value as Array if value is Array else []
