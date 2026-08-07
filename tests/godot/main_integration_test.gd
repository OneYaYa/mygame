extends Node


const MainScene := preload("res://scenes/main.tscn")

var _checks := 0
var _failures := 0


func _ready() -> void:
	var main := MainScene.instantiate()
	add_child(main)
	await get_tree().process_frame

	var context_value: Variant = main.call("_build_npc_context")
	_check(context_value is Dictionary, "main should build a dictionary NPC context")
	var context := context_value as Dictionary
	var local_state := context.get("state", {}) as Dictionary
	_check(not local_state.has("flags"), "NPC context must exclude global mission flags")
	_check(not local_state.has("puzzles"), "NPC context must exclude global puzzle state")
	_check(not local_state.has("power"), "NPC context must exclude operator-only power telemetry")
	_check(not context.has("operator_telemetry"), "operator telemetry must not enter the NPC request context")
	_check(local_state.has("observation"), "NPC context should include current-room observation")
	main.call("_remember_player_facts", "我叫陈锋，请记住。")
	main.call("_record_conversation", "player", "我叫陈锋，请记住。")
	main.call("_record_conversation", "npc", "记住了，陈锋。")
	var remembered_context := main.call("_build_npc_context") as Dictionary
	_check(str((remembered_context.get("conversation_memory", {}) as Dictionary).get("player_name", "")) == "陈锋", "main should keep stable player facts locally")
	var remembered_history := remembered_context.get("history", []) as Array
	_check(remembered_history.size() >= 2, "main should forward bounded player/NPC dialogue history")

	var visible := context.get("visible_observations", []) as Array
	_check(not visible.is_empty(), "NPC context should include visible observation strings")
	for value: Variant in visible:
		_check(value is String, "visible observations must be strings")
	var ui: Node = main.get_node("MissionConsoleUI")
	var left_panel := ui.get("_left_panel") as Control
	var right_panel := ui.get("_right_panel") as Control
	var objective_text := ui.get("_objective_text") as RichTextLabel
	var observation_text := ui.get("_npc_observation") as RichTextLabel
	_check(left_panel != null and left_panel.custom_minimum_size.x >= 350.0, "facility panel should stay wide enough to reduce wrapped scrolling in the 1280 layout")
	_check(right_panel != null and right_panel.custom_minimum_size.x <= 280.0, "1280 layout should compact the operator rail before it can overflow")
	_check(right_panel != null and right_panel.get_global_rect().end.x <= ui.get_global_rect().end.x - 8.0, "operator rail should remain fully inside the visible console")
	_check(objective_text != null and objective_text.custom_minimum_size.y >= 150.0, "objective, next step and system feed should have a taller reading area")
	_check(objective_text != null and objective_text.text.contains("NEXT / 现在做什么") and objective_text.text.contains("检查遥测台"), "left panel should lead with an exact first step")
	_check(objective_text != null and objective_text.text.contains("输入指令 → AI 提出动作 → 右侧授权执行"), "left panel should explain the command and authorization loop")
	_check(observation_text != null and observation_text.custom_minimum_size.y >= 126.0, "local observation should have a taller reading area")
	var facility_map := ui.get("_facility_map") as Control
	var map_links := facility_map.get("_links") as Array
	var junction_routes := 0
	var has_escape_route := false
	for map_link: Dictionary in map_links:
		var from_id := str(map_link.get("from", ""))
		var to_id := str(map_link.get("to", ""))
		if from_id == "central_junction" or to_id == "central_junction":
			junction_routes += 1
		if [from_id, to_id].has("central_junction") and [from_id, to_id].has("escape_pod"):
			has_escape_route = true
	_check(junction_routes == 4, "facility map should show all four corridors from the central junction")
	_check(has_escape_route, "facility map should explicitly connect the central junction to the escape pod")
	var map_centers := facility_map.call("_room_centers") as Dictionary
	var junction_center := map_centers.get("central_junction", Vector2.ZERO) as Vector2
	var power_center := map_centers.get("power_bay", Vector2.ZERO) as Vector2
	var escape_center := map_centers.get("escape_pod", Vector2.ZERO) as Vector2
	_check(power_center.x < junction_center.x and escape_center.x > junction_center.x, "star layout should keep the escape route from passing behind the power node")
	var settings := ui.call("get_settings") as Dictionary
	_check(settings.has("font_scale") and settings.has("reduced_motion") and settings.has("online_enabled") and settings.has("quick_safe_actions"), "UI should expose persistent accessibility, provider and safe-action settings")
	var settings_dialog := ui.get("_settings_dialog") as Window
	_check(settings_dialog != null and not settings_dialog.visible, "settings should stay hidden until the player requests them")
	ui.call("_open_settings")
	_check(settings_dialog != null and settings_dialog.visible, "settings button should open the settings window on demand")
	settings_dialog.hide()
	var intro_state := ui.call("get_intro_debug_state") as Dictionary
	_check(bool(intro_state.get("active", false)), "signal boot sequence should start on the first UI instance")
	_check(bool(intro_state.get("input_blocked", false)), "opening overlay should block input while the signal is unstable")
	_check(float(intro_state.get("duration", 0.0)) >= 3.5, "opening signal sequence should be long enough to read")
	ui.call("skip_intro")
	await get_tree().process_frame
	var skipped_intro := ui.call("get_intro_debug_state") as Dictionary
	_check(bool(skipped_intro.get("completed", false)) and bool(skipped_intro.get("skipped", false)), "opening signal sequence should support an explicit skip")
	_check(not bool(skipped_intro.get("active", true)) and not bool(skipped_intro.get("input_blocked", true)), "skipping should release input immediately")
	_check(bool(skipped_intro.get("screen_restored", false)), "skipping should restore the UI position and color")
	main.call("_on_restart_requested")
	var restart_intro := ui.call("get_intro_debug_state") as Dictionary
	_check(not bool(restart_intro.get("active", true)), "restarting the mission should not replay the program boot sequence")
	var system_entries := ui.get("_system_entries") as Array
	var dialogue_entries := ui.get("_log_entries") as Array
	_check(not system_entries.is_empty(), "authoritative SYSTEM events should appear in the left information panel")
	_check(dialogue_entries.all(func(entry: Dictionary) -> bool: return str(entry.get("speaker", "")).to_upper() != "SYSTEM"), "central dialogue log should contain no SYSTEM speaker entries")
	_check(objective_text.text.contains("SYSTEM FEED / 系统事件"), "left information panel should visibly label the SYSTEM feed")
	var carried_label := ui.get("_carried_value") as Label
	_check(carried_label != null and carried_label.text == "无 / EMPTY", "empty carry slot should have an explicit UI value")
	_check(carried_label != null and carried_label.size.x > 20.0 and carried_label.size.y > 10.0, "carry-slot value should receive visible layout space")
	var telemetry_box := ui.get("_telemetry_box") as VBoxContainer
	_check(telemetry_box != null and telemetry_box.get_child_count() > 0, "operator telemetry should render without exposing an action list")
	var local_clue_box := ui.get("_local_clue_box") as VBoxContainer
	_check(local_clue_box != null and local_clue_box.get_child_count() > 0, "clue workbench should expose the local evidence lane")
	ui.call("_pin_remote_clue", "PWR-03 本轮需要 4.2 Ω 闭环")
	ui.call("_pin_local_clue", "蓝色接头 4.2 Ω；红色接头 6.8 Ω")
	var workbench_summary := ui.get("_workbench_summary") as Label
	_check(workbench_summary != null and workbench_summary.text.contains("同域证据已对齐"), "workbench should recognize compatible remote and local clues")
	var quick_box := ui.get("_quick_box") as GridContainer
	var expected_quick_labels := [
		"尝试询问他的状态",
		"尝试询问他的周边环境",
		"尝试安抚他的心情",
		"尝试询问他最后的记忆",
	]
	_check(quick_box != null and quick_box.get_child_count() == expected_quick_labels.size(), "right panel should expose four broad conversation directions")
	for index: int in range(expected_quick_labels.size()):
		var quick_button := quick_box.get_child(index) as Button
		var broad_label := str(expected_quick_labels[index])
		_check(quick_button != null and quick_button.text.contains(broad_label), "quick button should display broad intent: %s" % broad_label)
		_check(quick_button != null and not quick_button.text.contains("？") and not quick_button.text.contains("林岚，"), "quick button should not display a scripted full sentence")
		var submitted_message := str(quick_button.get_meta("quick_message", "")) if quick_button != null else ""
		_check(not submitted_message.is_empty() and submitted_message != broad_label, "quick intent should still map to a natural hidden message")
	var candidate_hint := ui.get("_candidate_label") as Label
	var message_input := ui.get("_message_input") as LineEdit
	var retired_pronoun := String.chr(0x5979)
	_check(candidate_hint != null and not candidate_hint.text.contains(retired_pronoun), "candidate guidance should use the male character pronoun")
	_check(message_input != null and message_input.placeholder_text.contains("追问他"), "message placeholder should use the male character pronoun")
	var keyword_cards := ui.call("get_keyword_card_texts") as Array
	_check("遥测台" in keyword_cards and "中继控制室" in keyword_cards, "keyword cards should expose current special nouns")
	message_input.text = "请检查"
	message_input.caret_column = message_input.text.length()
	ui.call("_insert_keyword", "遥测台")
	_check(message_input.text == "请检查遥测台", "clicking a keyword card should insert it at the input caret without sending")
	message_input.clear()
	var portrait := ui.get("_portrait") as Control
	_check(portrait != null and portrait.has_method("get_debug_visual_state"), "pixel scene should expose semantic visual state for tests")
	var initial_visual := portrait.call("get_debug_visual_state") as Dictionary
	_check(str(initial_visual.get("room_id", "")) == "relay_control", "pixel background should start in the relay control room")
	_check(is_equal_approx(float(initial_visual.get("oxygen", -1.0)), 100.0), "pixel character should receive current oxygen state")
	_check(str(initial_visual.get("condition", "")) == "normal", "initial pixel character condition should be normal")
	_check(str(initial_visual.get("framing", "")) == "shoulders_up", "remote feed should frame the trapped man from the shoulders up")
	_check(str(initial_visual.get("character_asset", "")).ends_with("lin_lan_male_pixel.png"), "remote feed should use the male pixel portrait asset")

	var service: Node = main.get_node("NpcDecisionService")
	var payload_value: Variant = service.call("_build_payload", context, "拿起保险芯")
	_check(payload_value is Dictionary, "decision service should build a dictionary payload")
	var payload := payload_value as Dictionary
	var valid_actions := payload.get("valid_actions", []) as Array
	var found_take := false
	for value: Variant in valid_actions:
		if value is Dictionary:
			var action := value as Dictionary
			if str(action.get("action", "")) == "take" and str(action.get("target", "")) == "phase_fuse":
				found_take = true
	_check(found_take, "Godot take action must survive the proxy payload mapping")
	var ambiguous_context := context.duplicate(true)
	ambiguous_context["available_actions"] = [
		{"id": "connect", "target": "blue_cable", "enabled": true},
		{"id": "connect", "target": "red_cable", "enabled": true},
	]
	var rejected_empty_target := service.call("_sanitize_decision", {
		"reply": "我接一根。", "intent": "propose_action", "action": "connect", "target": "", "mood": "focused"
	}, ambiguous_context, "test") as Dictionary
	_check(not bool(rejected_empty_target.get("candidate_valid", true)), "client defense rejects an empty target when multiple actions share the same verb")

	var before := (main.get("_snapshot") as Dictionary).duplicate(true)
	main.call("_on_decision_ready", {
		"reply": "我建议拿起保险芯，等待你在控制台确认。",
		"intent": "propose_action",
		"action": "take",
		"target": "phase_fuse",
		"mood": "focused",
		"candidate_valid": true,
	})
	var after_candidate := main.get("_snapshot") as Dictionary
	_check(after_candidate.get("turn") == before.get("turn"), "model candidate must not consume a turn")
	_check(str(after_candidate.get("carried_item", "")) == "", "model candidate must not mutate inventory")
	_check(not (ui.get("_pending_candidate") as Dictionary).is_empty(), "validated model candidate should wait in the single authorization card")
	var candidate_panel := ui.get("_candidate_panel") as PanelContainer
	_check(candidate_panel != null and candidate_panel.visible, "authorization card should be visible for one validated candidate")

	(ui.get("_settings") as Dictionary)["quick_safe_actions"] = true
	ui.call("_submit_message", "")
	var after_confirmed_ui_action := main.get("_snapshot") as Dictionary
	_check(int(after_confirmed_ui_action.get("turn", 0)) == 1, "empty Enter should quick-authorize an already validated safe action")
	_check(str(after_confirmed_ui_action.get("carried_item", "")) == "phase_fuse", "confirmed UI action should update inventory")
	_check((ui.get("_pending_candidate") as Dictionary).is_empty(), "authorization card should clear after emitting exactly one action")

	main.call("_on_action_requested", "move", "central_junction", {})
	var junction_visual := portrait.call("get_debug_visual_state") as Dictionary
	_check(str(junction_visual.get("room_id", "")) == "central_junction", "pixel background should follow the NPC into the central junction")
	_check(bool(junction_visual.get("transitioning", false)), "room changes should start a visual transition")
	main.call("_on_action_requested", "move", "power_bay", {})
	var power_visual := portrait.call("get_debug_visual_state") as Dictionary
	_check(str(power_visual.get("room_id", "")) == "power_bay", "pixel background should follow the NPC into the power bay")
	main.call("_on_action_requested", "inspect", "cable_panel", {})
	var action_visual := portrait.call("get_debug_visual_state") as Dictionary
	_check(bool(action_visual.get("action_active", false)), "completed core actions should trigger a short pixel-character animation")
	_check(str(action_visual.get("action_id", "")) == "inspect", "pixel action animation should identify the completed action")
	_check(bool(action_visual.get("focus_active", false)), "inspection should trigger a short field close-up overlay")
	var before_danger := (main.get("_snapshot") as Dictionary).duplicate(true)
	main.call("_on_action_requested", "connect", "red_cable", {})
	var pending := (main.get("_snapshot") as Dictionary).get("pending_confirmation", {}) as Dictionary
	var proposal_id := int(main.get("_last_confirmation_id"))
	_check(proposal_id > 0 and not pending.is_empty(), "dangerous UI action should wait for confirmation")
	_check((main.get("_snapshot") as Dictionary).get("turn") == before_danger.get("turn"), "unconfirmed dangerous action must not consume a turn")
	main.call("_on_proposal_confirmation_requested", proposal_id, false)
	var after_cancel := main.get("_snapshot") as Dictionary
	_check((after_cancel.get("pending_confirmation", {}) as Dictionary).is_empty(), "cancel should clear the dangerous proposal")
	_check(after_cancel.get("turn") == before_danger.get("turn"), "canceling a dangerous action must not mutate the world")
	(ui.get("_pending_proposal") as Dictionary).clear()
	var danger_dialog := ui.get("_danger_dialog") as ConfirmationDialog
	if danger_dialog != null and danger_dialog.visible:
		danger_dialog.hide()
	var risky_action: Dictionary = {}
	for available: Dictionary in main.call("_valid_actions") as Array:
		if str(available.get("id", "")) == "connect":
			risky_action = available
			break
	_check(not risky_action.is_empty(), "inspected power panel should expose a risky cable candidate")
	var before_single_confirm := int((main.get("_snapshot") as Dictionary).get("turn", -1))
	main.call("_on_decision_ready", {
		"reply": "这根线，我的手已经停在旁边。你确认我就接。",
		"intent": "propose_action",
		"action": str(risky_action.get("id", "")),
		"target": str(risky_action.get("target", "")),
		"mood": "nervous",
		"candidate_valid": true,
	})
	ui.call("_authorize_candidate")
	var after_single_confirm := main.get("_snapshot") as Dictionary
	_check(int(after_single_confirm.get("turn", -1)) == before_single_confirm + 1, "risk acknowledged in the candidate card should execute without a second dialog")
	_check((after_single_confirm.get("pending_confirmation", {}) as Dictionary).is_empty(), "single-confirm risk flow should leave no pending proposal")
	var log_entries := ui.get("_log_entries") as Array
	var routed_system_entries := ui.get("_system_entries") as Array
	var seen_log_ids: Dictionary = {}
	var unique_log_ids := true
	var all_routed_entries: Array = log_entries + routed_system_entries
	for log_entry: Dictionary in all_routed_entries:
		var source_id := str(log_entry.get("source_id", ""))
		if source_id.is_empty():
			continue
		if seen_log_ids.has(source_id):
			unique_log_ids = false
		seen_log_ids[source_id] = true
	_check(unique_log_ids, "authoritative core log entries should use stable deduplication ids")

	var low_oxygen_snapshot := after_cancel.duplicate(true)
	var low_resources := (low_oxygen_snapshot.get("resources", {}) as Dictionary).duplicate(true)
	low_resources["oxygen"] = 20
	low_oxygen_snapshot["resources"] = low_resources
	ui.call("render_snapshot", low_oxygen_snapshot)
	var low_oxygen_visual := portrait.call("get_debug_visual_state") as Dictionary
	_check(str(low_oxygen_visual.get("condition", "")) == "low_oxygen", "low oxygen should switch the pixel character into hypoxia animation")
	_check(is_equal_approx(float(low_oxygen_visual.get("oxygen", -1.0)), 20.0), "pixel HUD should receive the low oxygen value")

	var terminal_snapshot := low_oxygen_snapshot.duplicate(true)
	terminal_snapshot["is_terminal"] = true
	terminal_snapshot["outcome"] = "failure"
	ui.call("render_snapshot", terminal_snapshot)
	var terminal_visual := portrait.call("get_debug_visual_state") as Dictionary
	_check(str(terminal_visual.get("condition", "")) == "terminal", "terminal mission state should override the character condition")

	print("Blindspot Relay integration tests: %d checks, %d failures" % [_checks, _failures])
	main.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("INTEGRATION CHECK FAILED: %s" % message)
