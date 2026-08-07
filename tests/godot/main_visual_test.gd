extends Node


const MainScene := preload("res://scenes/main.tscn")
const OUTPUT_PATH := "res://artifacts/main_console_v03.png"
const CANDIDATE_OUTPUT_PATH := "res://artifacts/main_candidate_guidance_v04.png"
const CENTRAL_OUTPUT_PATH := "res://artifacts/main_central_guidance_v04.png"
const CLUE_OUTPUT_PATH := "res://artifacts/main_clue_workbench_v03.png"


func _ready() -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame
	var ui := main.get_node("MissionConsoleUI")
	ui.call("skip_intro")
	await get_tree().process_frame
	var is_headless := DisplayServer.get_name() == "headless"
	var error: Error = OK
	if not is_headless:
		error = await _save_viewport(OUTPUT_PATH)
	ui.call("show_candidate", "inspect", "telemetry_console")
	await get_tree().process_frame
	var candidate_error: Error = OK
	if not is_headless:
		candidate_error = await _save_viewport(CANDIDATE_OUTPUT_PATH)
	ui.call("show_candidate", "")
	main.call("_on_action_requested", "inspect", "telemetry_console", {})
	main.call("_on_action_requested", "move", "central_junction", {})
	await get_tree().process_frame
	var central_error: Error = OK
	if not is_headless:
		central_error = await _save_viewport(CENTRAL_OUTPUT_PATH)
	main.call("_on_action_requested", "move", "relay_control", {})
	main.call("_on_action_requested", "take", "phase_fuse", {})
	main.call("_on_action_requested", "move", "central_junction", {})
	main.call("_on_action_requested", "move", "power_bay", {})
	main.call("_on_action_requested", "inspect", "cable_panel", {})
	var snapshot := main.get("_snapshot") as Dictionary
	var telemetry := snapshot.get("operator_telemetry", []) as Array
	for value: Variant in telemetry:
		if str(value).contains("PWR-03"):
			ui.call("_pin_remote_clue", str(value))
	var evidence := snapshot.get("evidence", {}) as Dictionary
	ui.call("_pin_local_clue", str(evidence.get("power_local", "")))
	await get_tree().process_frame
	var clue_error: Error = OK
	if not is_headless:
		clue_error = await _save_viewport(CLUE_OUTPUT_PATH)
	print("Main console visuals: %s" % ("headless smoke passed" if is_headless and error == OK and candidate_error == OK and central_error == OK and clue_error == OK else "saved" if error == OK and candidate_error == OK and central_error == OK and clue_error == OK else "failed"))
	get_tree().quit(0 if error == OK and candidate_error == OK and central_error == OK and clue_error == OK else 1)


func _save_viewport(path: String) -> Error:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image().save_png(path)
