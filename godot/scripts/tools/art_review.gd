class_name TimeEchoArtReview
extends Node

@onready var main: TimeEchoMain = $Main

var map_picker: OptionButton
var time_picker: OptionButton
var debug_toggle: CheckButton
var status_label: RichTextLabel
var map_entries: Array[Dictionary] = []
var review_state: Dictionary = {}


func _ready() -> void:
	_build_review_ui()
	call_deferred("_start_review")


func _process(_delta: float) -> void:
	if review_state.is_empty() or main.world.current_scene.is_empty():
		return
	debug_toggle.set_pressed_no_signal(main.world.world_view.is_art_debug_enabled())
	_update_status()


func _start_review() -> void:
	review_state = GameManager.new_game()
	review_state["speed"] = 0.0
	review_state["cinematic"] = null
	review_state["repairs"] = {"master": true, "chapel": true, "tide": true}
	var flags: Dictionary = review_state.get("flags", {}) as Dictionary
	flags["counterweight_raised"] = true
	flags["light_route_inn_studio"] = true
	flags["slot_seven_filled"] = true
	review_state["flags"] = flags
	InventoryManager.add_item(review_state, "unnumbered_key")
	InventoryManager.add_item(review_state, "flashlight")
	(review_state.get("photos", {}) as Dictionary)["fixed_portrait_installed"] = true
	main.ui.close_modal(false)
	main.ui.visible = false
	main.flow.transition(GameFlowStateMachine.State.PLAYING)
	_load_selected_map()


func _build_review_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ArtReviewUI"
	layer.layer = 90
	add_child(layer)
	var toolbar := PanelContainer.new()
	toolbar.position = Vector2(10, 10)
	toolbar.size = Vector2(760, 46)
	layer.add_child(toolbar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	toolbar.add_child(row)
	var title := Label.new()
	title.text = "ART REVIEW"
	title.add_theme_color_override("font_color", Color("f0d696"))
	row.add_child(title)
	map_picker = OptionButton.new()
	map_picker.custom_minimum_size = Vector2(220, 34)
	row.add_child(map_picker)
	map_entries.append_array(DataManager.maps.get("regions", []) as Array)
	map_entries.append_array(DataManager.maps.get("places", []) as Array)
	for index: int in range(map_entries.size()):
		var scene: Dictionary = map_entries[index]
		map_picker.add_item("%02d  %s" % [index + 1, scene.get("id", "")])
		map_picker.set_item_metadata(index, scene.get("id", ""))
	map_picker.item_selected.connect(func(_index: int) -> void: _load_selected_map())
	var reload := Button.new()
	reload.text = "Reload"
	reload.pressed.connect(_load_selected_map)
	row.add_child(reload)
	time_picker = OptionButton.new()
	time_picker.custom_minimum_size = Vector2(110, 34)
	for label: String in ["Day", "Dusk", "Night"]:
		time_picker.add_item(label)
	time_picker.item_selected.connect(_on_time_selected)
	row.add_child(time_picker)
	debug_toggle = CheckButton.new()
	debug_toggle.text = "Art Debug (F3)"
	debug_toggle.toggled.connect(func(value: bool) -> void: main.world.set_art_debug(value))
	row.add_child(debug_toggle)
	status_label = RichTextLabel.new()
	status_label.name = "ReviewStatus"
	status_label.position = Vector2(790, 10)
	status_label.size = Vector2(352, 286)
	status_label.bbcode_enabled = true
	status_label.fit_content = false
	status_label.scroll_active = true
	status_label.add_theme_color_override("default_color", Color("d7dfcf"))
	layer.add_child(status_label)
	var help := Label.new()
	help.position = Vector2(12, 610)
	help.size = Vector2(740, 28)
	help.text = "WASD move · F3 bounds/anchors/collision/portal · selector reloads Godot-only art layout"
	help.add_theme_color_override("font_color", Color("e8d7a9"))
	layer.add_child(help)


func _load_selected_map() -> void:
	if review_state.is_empty() or map_picker.item_count == 0:
		return
	var map_id: String = str(map_picker.get_item_metadata(map_picker.selected))
	var scene: Dictionary = DataManager.get_scene_data(map_id)
	review_state["placeId"] = map_id
	review_state["speed"] = 0.0
	var elapsed_by_time: Array[float] = [4.0 * 60.0, 12.5 * 60.0, 18.0 * 60.0]
	review_state["loopElapsed"] = elapsed_by_time[time_picker.selected]
	TimeManager.sync_clock(review_state)
	TimeManager.sync_world_flags(review_state)
	TimeManager.sync_npc_schedules(review_state)
	var player_state: Dictionary = review_state.get("player", {}) as Dictionary
	player_state["x"] = roundf(float(scene.get("width", 768)) * 0.5)
	player_state["y"] = roundf(float(scene.get("height", 480)) * 0.58)
	player_state["facing"] = "down"
	review_state["player"] = player_state
	main.world.load_state(review_state, true)
	main.world.set_time_of_day_override(["day", "dusk", "night"][time_picker.selected])
	main.world.set_input_enabled(true)
	_update_status()


func _on_time_selected(_index: int) -> void:
	_load_selected_map()


func _update_status() -> void:
	var metrics: Dictionary = main.world.get_art_review_metrics()
	var errors: PackedStringArray = metrics.get("asset_errors", PackedStringArray())
	var warnings: PackedStringArray = metrics.get("warnings", PackedStringArray())
	var lines: PackedStringArray = PackedStringArray([
		"[b]MAP[/b]  %s" % metrics.get("map_id", "?"),
		"objects %d  ·  collisions %d  ·  portals %d" % [metrics.get("object_count", 0), metrics.get("collision_count", 0), metrics.get("portal_count", 0)],
		"player spawn  %s" % str(metrics.get("player_spawn", [])),
		"NPC schedule points  %d" % (metrics.get("npc_points", []) as Array).size(),
		"asset failures  %d  ·  pixel/overlap warnings  %d" % [errors.size(), warnings.size()],
		"",
		"[b]PORTAL REACHABILITY[/b]",
	])
	for raw: Variant in metrics.get("portal_reachability", []):
		var portal: Dictionary = raw as Dictionary
		var mark: String = "OK" if bool(portal.get("reachable", false)) else "BLOCKED"
		lines.append("%s  %s → %s" % [mark, portal.get("portal_id", "?"), portal.get("target", "?")])
	if not errors.is_empty():
		lines.append("\n[color=#ff8d80][b]LOAD FAILURES[/b][/color]")
		lines.append_array(errors)
	if not warnings.is_empty():
		lines.append("\n[color=#f0c56d][b]LAYOUT WARNINGS[/b][/color]")
		lines.append_array(warnings)
	status_label.text = "\n".join(lines)
