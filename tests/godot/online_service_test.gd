extends Node


const MainScene := preload("res://scenes/main.tscn")

var _decision: Dictionary = {}


func _ready() -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame

	var service: Node = main.get_node("NpcDecisionService")
	service.connect("decision_ready", _on_decision_ready)
	var context_value: Variant = main.call("_build_npc_context")
	if not context_value is Dictionary:
		_fail("main did not produce an NPC context")
		return

	service.call("request_decision", context_value as Dictionary, "拿起相位保险芯。")
	var deadline := Time.get_ticks_msec() + 45000
	while _decision.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	if _decision.is_empty():
		_fail("timed out waiting for the decision service")
		return
	if str(_decision.get("provider", "")) != "openai":
		_fail("expected OpenAI provider, got %s" % str(_decision.get("provider", "")))
		return
	if str(_decision.get("action", "")) != "take" or str(_decision.get("target", "")) != "phase_fuse":
		_fail("expected take/phase_fuse, got %s/%s" % [_decision.get("action", ""), _decision.get("target", "")])
		return
	if not bool(_decision.get("candidate_valid", false)):
		_fail("online action should survive the local whitelist")
		return

	print("Blindspot Relay online service test: provider=openai action=take target=phase_fuse")
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _on_decision_ready(decision: Dictionary) -> void:
	_decision = decision.duplicate(true)


func _fail(message: String) -> void:
	push_error("ONLINE SERVICE TEST FAILED: %s" % message)
	get_tree().quit(1)
