extends Control


const PortraitClass := preload("res://scripts/ui/npc_portrait.gd")
const OUTPUT_PATH := "res://artifacts/pixel_scene_gallery.png"

const ROOM_CASES := [
	{"label": "RELAY / 中继控制室", "room_id": "relay_control", "room_name": "中继控制室"},
	{"label": "JUNCTION / 中央交汇舱", "room_id": "central_junction", "room_name": "中央交汇舱"},
	{"label": "POWER / 主电网舱", "room_id": "power_bay", "room_name": "主电网舱"},
	{"label": "COOLANT / 冷却回廊", "room_id": "coolant_gallery", "room_name": "冷却回廊"},
	{"label": "ESCAPE / 逃生舱", "room_id": "escape_pod", "room_name": "逃生舱"},
]

const STATE_CASES := [
	{"label": "LISTENING / 通讯中", "room_id": "relay_control", "thinking": true},
	{"label": "INJURED / 负伤", "room_id": "central_junction", "mood": "hurt", "mistakes": 1},
	{"label": "HYPOXIA / 低氧", "room_id": "coolant_gallery", "oxygen": 20},
	{"label": "FAILED ACTION / 操作失败", "room_id": "power_bay", "action": "connect", "action_success": false},
	{"label": "EVAC / 撤离", "room_id": "escape_pod", "is_terminal": true, "outcome": "success", "flags": {"escape_unlocked": true}},
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color("050d12")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var content := VBoxContainer.new()
	content.position = Vector2(16, 12)
	content.add_theme_constant_override("separation", 20)
	add_child(content)
	_build_row(content, ROOM_CASES)
	_build_row(content, STATE_CASES)

	await get_tree().create_timer(0.42).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(OUTPUT_PATH)
	print("Pixel scene visual gallery: %s" % ("saved" if error == OK else "failed (%s)" % error))
	get_tree().quit(0 if error == OK else 1)


func _build_row(parent: VBoxContainer, cases: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	for scene_case: Dictionary in cases:
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 4)
		row.add_child(column)
		var label := Label.new()
		label.text = str(scene_case.get("label", "SCENE"))
		label.custom_minimum_size = Vector2(240, 18)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", Color("9bb1b3"))
		label.add_theme_font_size_override("font_size", 11)
		column.add_child(label)
		var portrait: Control = PortraitClass.new()
		portrait.custom_minimum_size = Vector2(240, 218)
		column.add_child(portrait)
		var state := {
			"room_id": str(scene_case.get("room_id", "relay_control")),
			"room_name": str(scene_case.get("room_name", "")),
			"oxygen": float(scene_case.get("oxygen", 78.0)),
			"power": 64.0,
			"mood": str(scene_case.get("mood", "focused")),
			"mistakes": int(scene_case.get("mistakes", 0)),
			"thinking": bool(scene_case.get("thinking", false)),
			"is_terminal": bool(scene_case.get("is_terminal", false)),
			"outcome": str(scene_case.get("outcome", "ongoing")),
			"flags": (scene_case.get("flags", {}) as Dictionary).duplicate(true),
		}
		portrait.call("set_npc_state", state, "online")
		var action_id := str(scene_case.get("action", ""))
		if not action_id.is_empty():
			portrait.call("trigger_action", action_id, bool(scene_case.get("action_success", true)))
