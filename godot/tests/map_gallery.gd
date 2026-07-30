extends Node

const DEFAULT_OUTPUT_RELATIVE: String = "tests/render/maps_v2"
const DAYTIME_ELAPSED: float = 4.0 * 60.0
const NIGHT_ELAPSED: float = 18.0 * 60.0
const LOW_TIDE_ELAPSED: float = 20.5 * 60.0

@onready var main: TimeEchoMain = $Main

var _captures: Array[Dictionary] = []
var _failures: int = 0
var _suffix: String = ""
var _time_of_day: String = ""


func _ready() -> void:
	call_deferred("_generate_gallery")


func _generate_gallery() -> void:
	await get_tree().process_frame
	var output_relative: String = _read_output_relative()
	_suffix = _safe_suffix(_read_option("--suffix"))
	_time_of_day = _read_option("--time-of-day").to_lower()
	if _time_of_day not in ["", "day", "dusk", "night"]:
		push_error("Invalid --time-of-day: %s" % _time_of_day)
		get_tree().quit(2)
		return
	var output_absolute: String = ProjectSettings.globalize_path("res://%s" % output_relative)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(output_absolute)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("无法创建地图截图目录：%s" % output_absolute)
		get_tree().quit(1)
		return

	var state: Dictionary = _create_gallery_state()
	main.ui.close_modal(false)
	main.ui.show_game()
	main.ui.journal_panel.visible = false
	main.flow.transition(GameFlowStateMachine.State.PLAYING)
	main.world.set_art_debug("--art-debug" in OS.get_cmdline_user_args())
	main.world.set_time_of_day_override(_time_of_day)

	var scenes: Array = []
	scenes.append_array(DataManager.maps.get("regions", []) as Array)
	scenes.append_array(DataManager.maps.get("places", []) as Array)
	var map_filter: PackedStringArray = _read_repeated_option("--map-id")
	for index: int in range(scenes.size()):
		var scene: Dictionary = scenes[index] as Dictionary
		if not map_filter.is_empty() and str(scene.get("id", "")) not in map_filter:
			continue
		await _capture_scene(index, scene, state, output_absolute)

	_write_manifest(output_absolute)
	await _capture_contact_pages(output_absolute)
	AudioManager.shutdown()
	await get_tree().process_frame
	print("TIME ECHO map gallery: %d maps, %d failures, %s" % [_captures.size(), _failures, output_absolute])
	get_tree().quit(1 if _failures > 0 else 0)


func _read_output_relative() -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		var argument: String = args[index]
		if argument.begins_with("--output-dir="):
			return argument.trim_prefix("--output-dir=").trim_prefix("res://").trim_suffix("/")
		if argument == "--output-dir" and index + 1 < args.size():
			return args[index + 1].trim_prefix("res://").trim_suffix("/")
	return DEFAULT_OUTPUT_RELATIVE


func _read_repeated_option(option: String) -> PackedStringArray:
	var result := PackedStringArray()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index].begins_with("%s=" % option):
			result.append(args[index].trim_prefix("%s=" % option))
		elif args[index] == option and index + 1 < args.size():
			result.append(args[index + 1])
	return result


func _read_option(option: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(args.size()):
		if args[index].begins_with("%s=" % option):
			return args[index].trim_prefix("%s=" % option)
		if args[index] == option and index + 1 < args.size():
			return args[index + 1]
	return ""


func _safe_suffix(value: String) -> String:
	var cleaned: String = value.strip_edges().replace("/", "-").replace("\\", "-").replace("..", "-")
	return "" if cleaned.is_empty() else (cleaned if cleaned.begins_with("_") else "_%s" % cleaned)


func _create_gallery_state() -> Dictionary:
	var state: Dictionary = GameManager.new_game()
	state["cinematic"] = null
	state["endingId"] = null
	state["conversationOpen"] = false
	state["repairs"] = {"master": true, "chapel": true, "tide": true}
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	flags["counterweight_raised"] = true
	flags["light_route_inn_studio"] = true
	flags["slot_seven_filled"] = true
	state["flags"] = flags
	InventoryManager.add_item(state, "unnumbered_key")
	InventoryManager.add_item(state, "flashlight")
	var photos: Dictionary = state.get("photos", {}) as Dictionary
	photos["fixed_portrait_installed"] = true
	state["photos"] = photos
	return state


func _capture_scene(index: int, scene: Dictionary, state: Dictionary, output_absolute: String) -> void:
	var scene_id: String = str(scene.get("id", "scene_%02d" % (index + 1)))
	var elapsed: float = _elapsed_for_scene(scene_id, _time_of_day)
	state["placeId"] = scene_id
	state["loopElapsed"] = elapsed
	state["speed"] = 0.0
	TimeManager.sync_clock(state)
	TimeManager.sync_world_flags(state)
	TimeManager.sync_npc_schedules(state)
	var player_state: Dictionary = state.get("player", {}) as Dictionary
	player_state["x"] = float(scene.get("width", 768.0)) * 0.5
	player_state["y"] = float(scene.get("height", 480.0)) * 0.5
	player_state["facing"] = "down"
	state["player"] = player_state
	main.world.load_state(state, true)
	main.ui.update_state(state, scene)
	main.ui.journal_panel.visible = false
	for _frame: int in range(3):
		await get_tree().process_frame
	RenderingServer.force_draw(false, 0.0)
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		_failures += 1
		push_error("Map capture has no rendered image: %s" % scene_id)
		return
	var filename: String = "%02d_%s%s.png" % [index + 1, scene_id, _suffix]
	var save_error: Error = image.save_png(output_absolute.path_join(filename))
	if save_error != OK:
		_failures += 1
		push_error("地图截图写入失败：%s (%s)" % [filename, error_string(save_error)])
		return
	var metrics: Dictionary = main.world.get_art_review_metrics()
	_captures.append({
		"index": index + 1,
		"id": scene_id,
		"name": str(scene.get("name", scene_id)),
		"kind": str(scene.get("kind", "outdoor")),
		"width": int(scene.get("width", 0)),
		"height": int(scene.get("height", 0)),
		"time": TimeManager.format_time(int(state.get("minute", 0))),
		"file": filename,
		"image": image,
		"art_metrics": metrics,
	})


func _elapsed_for_scene(scene_id: String, time_of_day: String = "") -> float:
	if time_of_day == "day":
		return DAYTIME_ELAPSED
	if time_of_day == "dusk":
		return 12.5 * 60.0
	if time_of_day == "night":
		return NIGHT_ELAPSED
	if scene_id == "inn-upstairs":
		return NIGHT_ELAPSED
	if scene_id in ["low-tide-cave", "hidden-darkroom"]:
		return LOW_TIDE_ELAPSED
	return DAYTIME_ELAPSED


func _write_manifest(output_absolute: String) -> void:
	var entries: Array[Dictionary] = []
	for capture: Dictionary in _captures:
		entries.append({
			"index": capture["index"], "id": capture["id"], "name": capture["name"],
			"kind": capture["kind"], "width": capture["width"], "height": capture["height"],
			"time": capture["time"], "file": capture["file"],
			"art_metrics": capture["art_metrics"],
		})
	var file: FileAccess = FileAccess.open(output_absolute.path_join("gallery_manifest%s.json" % _suffix), FileAccess.WRITE)
	if file == null:
		_failures += 1
		push_error("无法写入地图截图索引")
		return
	file.store_string(JSON.stringify({"godot": Engine.get_version_info(), "maps": entries}, "  ", false))


func _capture_contact_pages(output_absolute: String) -> void:
	main.world.visible = false
	main.ui.visible = false
	var gallery_layer := CanvasLayer.new()
	gallery_layer.layer = 100
	add_child(gallery_layer)
	var page_count: int = ceili(float(_captures.size()) / 6.0)
	for page_index: int in range(page_count):
		for child: Node in gallery_layer.get_children():
			child.queue_free()
		await get_tree().process_frame
		_build_contact_page(gallery_layer, page_index, page_count)
		await get_tree().process_frame
		RenderingServer.force_draw(false, 0.0)
		var page_image: Image = get_viewport().get_texture().get_image()
		if page_image == null or page_image.is_empty():
			_failures += 1
			push_error("Gallery contact page has no rendered image: %d" % (page_index + 1))
			continue
		var save_error: Error = page_image.save_png(output_absolute.path_join("gallery_page_%d%s.png" % [page_index + 1, _suffix]))
		if save_error != OK:
			_failures += 1
			push_error("总览页写入失败：%s" % error_string(save_error))
	gallery_layer.queue_free()
	await get_tree().process_frame


func _build_contact_page(layer: CanvasLayer, page_index: int, page_count: int) -> void:
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("10191b")
	layer.add_child(background)
	var header := Label.new()
	header.position = Vector2(12, 4)
	header.size = Vector2(1128, 30)
	header.text = "TIME ECHO · 地图实际渲染总览  %d / %d" % [page_index + 1, page_count]
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 20)
	header.add_theme_color_override("font_color", Color("efd9a6"))
	background.add_child(header)
	for local_index: int in range(6):
		var capture_index: int = page_index * 6 + local_index
		if capture_index >= _captures.size():
			break
		var capture: Dictionary = _captures[capture_index]
		var column: int = local_index % 3
		var row: int = local_index / 3
		var cell := ColorRect.new()
		cell.position = Vector2(6 + column * 382, 36 + row * 302)
		cell.size = Vector2(376, 294)
		cell.color = Color("1a2a2c")
		background.add_child(cell)
		var title := Label.new()
		title.position = Vector2(8, 3)
		title.size = Vector2(360, 28)
		title.text = "%02d  %s  ·  %s" % [capture["index"], capture["name"], capture["id"]]
		title.add_theme_font_size_override("font_size", 15)
		title.add_theme_color_override("font_color", Color("e8d6aa"))
		cell.add_child(title)
		var preview := TextureRect.new()
		preview.position = Vector2(8, 32)
		preview.size = Vector2(360, 203)
		preview.texture = ImageTexture.create_from_image(capture["image"] as Image)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(preview)
		var footer := Label.new()
		footer.position = Vector2(8, 243)
		footer.size = Vector2(360, 42)
		footer.text = "%s · %d×%d · %s" % [capture["kind"], capture["width"], capture["height"], capture["time"]]
		footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		footer.add_theme_font_size_override("font_size", 13)
		footer.add_theme_color_override("font_color", Color("aebda8"))
		cell.add_child(footer)
