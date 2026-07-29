extends Node

var failures: int = 0
var checks: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	await get_tree().process_frame
	_check(DataManager.loaded, "JSON content loads and validates")
	for texture_path: String in [
		"res://assets/images/source_art/world/tile_grass.png",
		"res://assets/images/source_art/world/tile_water.png",
		"res://assets/images/source_art/world/tile_cobble.png",
		"res://assets/images/source_art/world/tile_wood.png",
	]:
		_check(ResourceLoader.exists(texture_path), "migrated surface exists: %s" % texture_path.get_file())
		_check(load(texture_path) is Texture2D, "migrated surface imports as Texture2D: %s" % texture_path.get_file())
	var main_scene: PackedScene = load("res://scenes/main/main.tscn") as PackedScene
	_check(main_scene != null, "main scene loads as PackedScene")
	var main_instance: Node = main_scene.instantiate()
	add_child(main_instance)
	await get_tree().process_frame
	_check(main_instance.get_node_or_null("WorldController/WorldView") != null, "main scene contains a drawable world")
	_check(main_instance.get_node_or_null("GameUI/UIRoot/TitleScreen") != null, "main scene builds a visible title layer")
	main_instance.queue_free()
	await get_tree().process_frame
	_check(DataManager.npcs_by_id.size() == 7, "exact seven-NPC cast")
	_check(DataManager.scenes_by_id.size() == 18, "one region plus seventeen places")
	_check(DataManager.items_by_id.has("fixed_portrait"), "stable item IDs are indexed")
	for scene_value: Variant in DataManager.scenes_by_id.values():
		var scene: Dictionary = scene_value as Dictionary
		for portal_value: Variant in scene.get("portals", []):
			var portal: Dictionary = portal_value as Dictionary
			_check(DataManager.scenes_by_id.has(str(portal.get("targetPlaceId", ""))), "portal target %s exists" % portal.get("id", "?"))

	var state: Dictionary = GameManager.create_initial_state()
	_check(state.get("placeId") == "player-room", "new game starts in room eight")
	_check(int(state.get("minute", 0)) == 360, "loop starts Saturday 06:00")
	var before: float = float(state.get("loopElapsed", 0.0))
	TimeManager.advance(state, 1.0)
	_check(is_equal_approx(float(state.get("loopElapsed", 0.0)) - before, 2.0), "one real second advances two game minutes")
	state["conversationOpen"] = true
	before = float(state.get("loopElapsed", 0.0))
	TimeManager.advance(state, 1.0)
	_check(is_equal_approx(float(state.get("loopElapsed", 0.0)) - before, 0.5), "dialogue uses quarter-speed time")
	state["conversationOpen"] = false
	state["placeId"] = "low-tide-cave"
	before = float(state.get("loopElapsed", 0.0))
	TimeManager.advance(state, 1.0)
	_check(is_equal_approx(float(state.get("loopElapsed", 0.0)), before), "low-tide cave pauses time")

	GameManager.state = state
	GameManager.mark_repair("master")
	GameManager.mark_repair("chapel")
	GameManager.mark_repair("tide")
	_check(bool((state.get("flags", {}) as Dictionary).get("basement_open", false)), "three repairs reveal basement")
	KnowledgeManager.add_evidence(state, "ledger_gap")
	InventoryManager.add_item(state, "room7_tag")
	var dorothea_actions: Array[Dictionary] = DialogueManager.get_actions("dorothea", state)
	_check(dorothea_actions.any(func(action: Dictionary) -> bool: return action.get("id") == "exchange_room7_key"), "room-seven evidence unlocks authored handoff")
	DialogueManager.apply_action("dorothea", "exchange_room7_key", state)
	_check(InventoryManager.has_item(state, "unnumbered_key"), "NPC action gives unnumbered key")

	KnowledgeManager.learn(state, "persistent_test")
	InventoryManager.add_item(state, "temporary_test")
	GameManager.state = state
	var reset_state: Dictionary = GameManager.reset_loop()
	_check(KnowledgeManager.knows(reset_state, "persistent_test"), "knowledge survives loop reset")
	_check(not InventoryManager.has_item(reset_state, "temporary_test"), "physical inventory resets")

	print("TIME ECHO tests: %d checks, %d failures" % [checks, failures])
	call_deferred("_finish", 1 if failures > 0 else 0)


func _finish(exit_code: int) -> void:
	get_tree().quit(exit_code)


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: %s" % label)
