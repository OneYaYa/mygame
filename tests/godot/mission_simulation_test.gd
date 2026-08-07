extends Node

const SimulationScript: Script = preload("res://scripts/core/mission_simulation.gd")
const LocalProviderScript: Script = preload("res://scripts/services/local_npc_provider.gd")
const ContextCompilerScript: Script = preload("res://scripts/services/npc_context_compiler.gd")

var _checks: int = 0
var _failures: int = 0


func _ready() -> void:
	_test_initial_contract()
	_test_context_compiler_protocol_and_trace()
	_test_split_clues_and_local_boundary()
	_test_local_language_and_ambiguity()
	_test_randomized_evidence_and_social_memory()
	_test_relationship_and_communication_pressure()
	_test_clean_completion()
	_test_emergency_route_and_oxygen_branch()
	_test_illegal_actions_and_carry_slot()
	_test_danger_confirmation_can_cancel()
	_test_wrong_cable_costly_completion()
	_test_resource_failure()
	print("Blindspot Relay core tests: %d checks, %d failures" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _new_simulation() -> MissionSimulation:
	return SimulationScript.new("res://data/mission.json", 4242) as MissionSimulation


func _scenario(simulation: MissionSimulation) -> Dictionary:
	return ((simulation.get("_state") as Dictionary).get("scenario", {}) as Dictionary)


func _correct_cable(simulation: MissionSimulation) -> String:
	return str(_scenario(simulation).get("correct_cable", ""))


func _wrong_cable(simulation: MissionSimulation) -> String:
	for cable_id: String in ["blue_cable", "red_cable", "yellow_cable"]:
		if cable_id != _correct_cable(simulation):
			return cable_id
	return ""


func _coolant_targets(simulation: MissionSimulation) -> Array:
	return (_scenario(simulation).get("coolant_required_targets", []) as Array).duplicate()


func _test_initial_contract() -> void:
	var simulation: MissionSimulation = _new_simulation()
	var state: Dictionary = simulation.snapshot()
	_expect(bool(state.get("ok", false)), "mission JSON loads")
	_expect_equal(str(state.get("room_id", "")), "relay_control", "starts in relay control")
	_expect_equal(int((state.get("resources", {}) as Dictionary).get("oxygen", -1)), 100, "starts with 100 oxygen")
	_expect_equal(int((state.get("resources", {}) as Dictionary).get("power", -1)), 70, "starts with 70 power")
	_expect_equal((state.get("rooms", []) as Array).size(), 5, "defines exactly five rooms")
	var action_ids: Array = state.get("action_ids", []) as Array
	_expect_equal(action_ids.size(), 8, "defines exactly eight action types")
	for expected_id: String in ["move", "inspect", "take", "drop", "connect", "toggle", "use", "wait"]:
		_expect(expected_id in action_ids, "action type exists: %s" % expected_id)
	_expect_equal(str(state.get("carried_item", "missing")), "", "carry slot starts empty")
	var context: Dictionary = simulation.build_npc_context()
	_expect_equal(str((context.get("local_state", {}) as Dictionary).get("room_id", "")), "relay_control", "NPC context is grounded in current room")
	var intro := str(state.get("npc_intro", ""))
	_expect(not intro.is_empty(), "snapshot includes a trapped-person introduction")
	_expect(not intro.contains("明确指令") and not intro.contains("复述") and not intro.contains("授权"), "intro never speaks UI mechanics aloud")
	_expect(intro.contains("调度") and intro.contains("能听见吗") and intro.contains("被困"), "intro sounds like a frightened person seeking contact")
	_expect((state.get("operator_telemetry", []) as Array).size() >= 2, "snapshot exposes operator-only telemetry")
	var initial_guide := state.get("guidance", {}) as Dictionary
	_expect(str(initial_guide.get("instruction", "")).contains("遥测台"), "initial guidance names the first useful objective")
	_expect_equal(str(initial_guide.get("example_command", "")), "检查遥测台", "initial guidance gives an exact command example")
	var early_junction: MissionSimulation = _new_simulation()
	_execute(early_junction, "move", "central_junction")
	var recovery_guide := early_junction.snapshot().get("guidance", {}) as Dictionary
	_expect(str(recovery_guide.get("instruction", "")).contains("返回中继控制室") and str(recovery_guide.get("instruction", "")).contains("遥测台"), "central-junction guidance recovers players who skipped telemetry")
	var route_choice: MissionSimulation = _new_simulation()
	_execute(route_choice, "inspect", "telemetry_console")
	_execute(route_choice, "move", "central_junction")
	var route_guide := route_choice.snapshot().get("guidance", {}) as Dictionary
	_expect(str(route_guide.get("instruction", "")).contains("相位保险芯") and str(route_guide.get("instruction", "")).contains("应急旁路电芯"), "central-junction guidance explains both power routes")
	var dropped_sealant: MissionSimulation = _new_simulation()
	var edge_state: Dictionary = dropped_sealant.get("_state") as Dictionary
	(edge_state.get("flags", {}) as Dictionary)["telemetry_inspected"] = true
	(edge_state.get("flags", {}) as Dictionary)["grid_online"] = true
	edge_state["room_id"] = "power_bay"
	var edge_items: Dictionary = edge_state.get("room_items", {}) as Dictionary
	(edge_items.get("power_bay", []) as Array).erase("sealant_kit")
	(edge_items.get("central_junction", []) as Array).append("sealant_kit")
	var dropped_guide := dropped_sealant.snapshot().get("guidance", {}) as Dictionary
	_expect(str(dropped_guide.get("instruction", "")).contains("中央交汇舱"), "guidance tracks a sealant kit dropped in another room")
	_expect(not str(dropped_guide.get("example_command", "")).contains("放下phase_fuse"), "empty carry slot never produces a bogus drop command")


func _test_context_compiler_protocol_and_trace() -> void:
	var simulation: MissionSimulation = _new_simulation()
	simulation.record_conversation("远端记录写着 4.2 欧，但你先别猜是哪根。", {"intent": "report", "mood": "focused"})
	var history: Array[Dictionary] = []
	for index: int in range(14):
		history.append({"role": "player" if index % 2 == 0 else "npc", "content": "连续通讯 %d" % index})
	var compiler: NpcContextCompiler = ContextCompilerScript.new() as NpcContextCompiler
	var compiled := compiler.compile(
		simulation.build_npc_context(),
		simulation.snapshot(),
		simulation.valid_actions(),
		history,
		{"player_name": "陈锋", "promises": ["我会保持通讯。"]},
		"你现在看见什么？"
	)
	var encoded := JSON.stringify(compiled)
	_expect(not encoded.contains("operator_telemetry"), "context compiler hard-filters operator telemetry")
	var protocol: Dictionary = compiled.get("context_protocol", {}) as Dictionary
	_expect_equal(int(protocol.get("protocol_version", 0)), 2, "context compiler emits versioned protocol")
	_expect_equal((protocol.get("recent_dialogue", []) as Array).size(), 10, "recent dialogue obeys its own quota")
	var beliefs: Array = protocol.get("known_beliefs", []) as Array
	_expect(beliefs.any(func(item: Variant) -> bool: return item is Dictionary and str((item as Dictionary).get("truth_status", "")) == "unverified_claim"), "operator report remains an unverified NPC belief")
	var memories: Array = protocol.get("relevant_memories", []) as Array
	_expect(memories.any(func(item: Variant) -> bool: return item is Dictionary and str((item as Dictionary).get("memory_id", "")) == "memory:player_name"), "subjective memory keeps a stable source ID")
	var trace: Dictionary = compiled.get("prompt_trace", {}) as Dictionary
	_expect(not str(trace.get("trace_id", "")).is_empty(), "compiled prompt has a replay trace ID")
	_expect(not (trace.get("partition_token_estimates", {}) as Dictionary).is_empty(), "trace records per-partition token estimates")
	_expect(not (trace.get("dropped", []) as Array).is_empty(), "trace records quota drops")


func _test_split_clues_and_local_boundary() -> void:
	var simulation: MissionSimulation = _new_simulation()
	_execute(simulation, "inspect", "telemetry_console")
	var state: Dictionary = simulation.snapshot()
	var telemetry_text: String = JSON.stringify(state.get("operator_telemetry", []))
	var required_reading := str(_scenario(simulation).get("required_reading", ""))
	_expect(not required_reading.is_empty() and telemetry_text.contains(required_reading), "operator telemetry contains this run's power-side half clue")
	var coolant_target := str(_scenario(simulation).get("coolant_target_pressure", ""))
	_expect(not coolant_target.is_empty() and telemetry_text.contains(coolant_target) and telemetry_text.contains("kPa"), "operator telemetry contains the coolant target pressure")
	var npc_context: Dictionary = simulation.build_npc_context()
	var npc_json: String = JSON.stringify(npc_context)
	_expect(not npc_context.has("operator_telemetry"), "NPC context excludes operator telemetry field")
	_expect(not npc_json.contains("本轮控制器需要"), "NPC context does not leak operator power truth")
	_expect(not npc_json.contains("必须调节到"), "NPC context does not leak the operator-only target pressure")
	_expect(not str((npc_context.get("local_state", {}) as Dictionary).get("stress", "")).is_empty(), "NPC context exposes derived stress")

	_execute(simulation, "take", "phase_fuse")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "power_bay")
	var power_inspection: Dictionary = _execute(simulation, "inspect", "cable_panel")
	var power_event: Dictionary = power_inspection.get("event", {}) as Dictionary
	_expect(not str(power_event.get("text", "")).contains("返程总线"), "power inspection does not name the correct cable role")
	_expect(not str(power_event.get("npc_line", "")).is_empty(), "first puzzle inspection includes restrained NPC speech")


func _test_local_language_and_ambiguity() -> void:
	var simulation: MissionSimulation = _new_simulation()
	_execute(simulation, "take", "phase_fuse")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "power_bay")
	_execute(simulation, "inspect", "cable_panel")
	var context: Dictionary = simulation.build_npc_context()
	context["available_actions"] = simulation.valid_actions()
	var provider: LocalNpcProvider = LocalProviderScript.new() as LocalNpcProvider
	var ambiguous: Dictionary = provider.decide(context, "连接一根电缆")
	_expect_equal(str(ambiguous.get("action", "missing")), "", "ambiguous cable command proposes no action")
	_expect_equal(str(ambiguous.get("intent", "")), "clarify", "ambiguous cable command asks for clarification")
	var ambiguous_reply := str(ambiguous.get("reply", ""))
	_expect(not ambiguous_reply.contains("蓝色套管") and not ambiguous_reply.contains("红色陶瓷") and not ambiguous_reply.contains("黄色编织"), "clarification never exposes a hidden action list")
	var explicit: Dictionary = provider.decide(context, "连接蓝色套管接头")
	_expect_equal(str(explicit.get("action", "")), "connect", "explicit Chinese verb maps to connect")
	_expect_equal(str(explicit.get("target", "")), "blue_cable", "explicit color maps to stable target id")
	_expect(not str(explicit.get("reply", "")).contains("复述") and not str(explicit.get("reply", "")).contains("授权"), "action acknowledgement stays in character instead of reciting UI mechanics")
	var false_time_jump: Dictionary = provider.decide(context, "过了一年")
	_expect_equal(str(false_time_jump.get("action", "missing")), "", "local provider never turns a player-authored time skip into an action")
	_expect(str(false_time_jump.get("reply", "")).contains("没有过去一年") and str(false_time_jump.get("reply", "")).contains("主电网舱"), "local provider rejects a false time jump and preserves the current room")
	for negated_text: String in ["不要连接蓝色接头", "先别连接红色接头", "如果安全就连接黄色接头"]:
		var negated: Dictionary = provider.decide(context, negated_text)
		_expect_equal(str(negated.get("action", "missing")), "", "negated or conditional local command proposes no action")
	var humane: Dictionary = provider.decide(context, "如果只检查一件东西，你现在最想先确认什么？")
	_expect_equal(str(humane.get("action", "missing")), "", "humane quick question never becomes an action")
	_expect_equal(str(humane.get("intent", "")), "report", "humane quick question receives a character response")
	_expect(not str(humane.get("reply", "")).begins_with("先"), "concern reply describes fear instead of assigning the player a tutorial step")
	for question: String in [
		"林岚，先告诉我：你受伤了吗？呼吸还稳不稳？",
		"别急着动。你身边有什么声音、气味，或者让你不安的东西？",
		"你最后清楚记得的事情是什么？",
	]:
		var check_in: Dictionary = provider.decide(context, question)
		_expect_equal(str(check_in.get("action", "missing")), "", "check-in question remains conversation")
		_expect(not str(check_in.get("reply", "")).is_empty(), "check-in question receives a humane reply")
		_expect(not str(check_in.get("reply", "")).contains("physical_state") and not str(check_in.get("reply", "")).contains("精细操作"), "check-in reply avoids schema and medical-report language")
	var coolant_simulation: MissionSimulation = _new_simulation()
	_execute(coolant_simulation, "move", "central_junction")
	_execute(coolant_simulation, "move", "coolant_gallery")
	_execute(coolant_simulation, "inspect", "valve_manifold")
	var coolant_context := coolant_simulation.build_npc_context()
	coolant_context["available_actions"] = coolant_simulation.valid_actions()
	var pressure_command := provider.decide(coolant_context, "接入 I 阀")
	_expect_equal(str(pressure_command.get("action", "")), "toggle", "pressure-language verb maps to regulator toggle")
	_expect_equal(str(pressure_command.get("target", "")), "valve_i", "pressure-language command keeps the explicit regulator target")


func _test_randomized_evidence_and_social_memory() -> void:
	var simulation: MissionSimulation = _new_simulation()
	var initial: Dictionary = simulation.snapshot()
	var initial_json := JSON.stringify(initial)
	_expect(not initial_json.contains("correct_cable") and not initial_json.contains("coolant_required_targets"), "public snapshot never exposes randomized answers")
	var first_id := str(initial.get("scenario_id", ""))
	var restarted := simulation.restart()
	_expect(str(restarted.get("scenario_id", "")) != first_id, "restart generates a new incident signature")
	var before_turn := int(restarted.get("turn", -1))
	var social_before := restarted.get("npc_social", {}) as Dictionary
	var after_social := simulation.record_conversation("我会一直保持通讯，启动记录要求 4.2 欧。", {
		"intent": "reassure", "mood": "nervous"
	})
	var social_after := after_social.get("npc_social", {}) as Dictionary
	_expect(int(social_after.get("trust", 0)) > int(social_before.get("trust", 0)), "reassurance raises locally authoritative trust")
	_expect_equal(int(after_social.get("turn", -2)), before_turn, "conversation changes social state without consuming a facility turn")
	var beliefs := after_social.get("npc_beliefs", {}) as Dictionary
	_expect(not (beliefs.get("operator_claims", []) as Array).is_empty(), "operator clue becomes an NPC belief rather than world truth")
	_expect(bool((after_social.get("flags", {}) as Dictionary).get("focused_scan_ready", false)), "reassurance prepares a focused field scan")


func _test_relationship_and_communication_pressure() -> void:
	var simulation: MissionSimulation = _new_simulation()
	var oxygen_before := int((simulation.snapshot().get("resources", {}) as Dictionary).get("oxygen", 0))
	for index: int in range(3):
		simulation.record_conversation("再报告一次现场。", {"intent": "report", "mood": "focused"})
	var pressured := simulation.snapshot()
	_expect_equal(int((pressured.get("resources", {}) as Dictionary).get("oxygen", 0)), oxygen_before - 1, "three conversation turns consume one communication-cycle oxygen")
	_expect_equal(int((pressured.get("npc_social", {}) as Dictionary).get("communication_cycles", 0)), 1, "communication cycle is recorded")
	for index: int in range(4):
		simulation.record_conversation("闭嘴，快点照做。", {"intent": "refuse", "mood": "afraid"})
	_execute(simulation, "take", "phase_fuse")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "power_bay")
	_execute(simulation, "inspect", "cable_panel")
	var blocked := simulation.propose("connect", _correct_cable(simulation))
	_expect_equal(str(blocked.get("status", "")), "invalid", "low trust and high fear block dangerous work")
	for index: int in range(3):
		simulation.record_conversation("我在，慢一点，我们重新核对。", {"intent": "reassure", "mood": "focused"})
	var restored := simulation.propose("connect", _correct_cable(simulation))
	_expect_equal(str(restored.get("status", "")), "confirmation_required", "reassurance restores willingness to attempt dangerous work")


func _test_clean_completion() -> void:
	var simulation: MissionSimulation = _new_simulation()
	_execute(simulation, "inspect", "telemetry_console")
	_execute(simulation, "take", "phase_fuse")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "power_bay")
	_execute(simulation, "inspect", "cable_panel")
	_confirm_action(simulation, "connect", _correct_cable(simulation))
	_execute(simulation, "use", "phase_fuse")
	_expect_equal(str((simulation.snapshot().get("puzzles", {}) as Dictionary).get("power", "")), "solved", "power puzzle solved deterministically")
	_execute(simulation, "take", "sealant_kit")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "coolant_gallery")
	_execute(simulation, "inspect", "valve_manifold")
	_perform_coolant_solution(simulation)
	_execute(simulation, "use", "sealant_kit")
	var after_puzzles: Dictionary = simulation.snapshot()
	_expect_equal(str((after_puzzles.get("puzzles", {}) as Dictionary).get("coolant", "")), "solved", "coolant puzzle solved deterministically")
	_expect(bool((after_puzzles.get("flags", {}) as Dictionary).get("escape_unlocked", false)), "two puzzles unlock escape pod")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "escape_pod")
	_execute(simulation, "use", "launch_console")
	var ending: Dictionary = simulation.snapshot()
	_expect(bool(ending.get("is_terminal", false)), "clean route reaches terminal state")
	_expect_equal(str(ending.get("outcome", "")), "success", "clean route reaches success ending")
	_expect_equal(int(ending.get("mistakes", -1)), 0, "clean route records no mistakes")
	_expect((simulation.valid_actions()).is_empty(), "terminal mission exposes no further actions")


func _test_emergency_route_and_oxygen_branch() -> void:
	var simulation: MissionSimulation = _new_simulation()
	_execute(simulation, "inspect", "telemetry_console")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "take", "oxygen_canister")
	var before_oxygen := int((simulation.snapshot().get("resources", {}) as Dictionary).get("oxygen", 0))
	_execute(simulation, "use", "oxygen_canister")
	_expect(int((simulation.snapshot().get("resources", {}) as Dictionary).get("oxygen", 0)) > before_oxygen, "optional oxygen route restores supply")
	_execute(simulation, "take", "emergency_cell")
	_execute(simulation, "move", "power_bay")
	_execute(simulation, "inspect", "cable_panel")
	_confirm_action(simulation, "use", "emergency_cell")
	var bypassed := simulation.snapshot()
	_expect_equal(str((bypassed.get("flags", {}) as Dictionary).get("power_route", "")), "emergency_bypass", "emergency cell commits a distinct power route")
	_expect_equal(str((bypassed.get("puzzles", {}) as Dictionary).get("power", "")), "bypassed", "emergency route bypasses cable solution")
	_execute(simulation, "take", "sealant_kit")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "coolant_gallery")
	_execute(simulation, "inspect", "valve_manifold")
	_perform_coolant_solution(simulation)
	_execute(simulation, "use", "sealant_kit")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "escape_pod")
	_execute(simulation, "use", "launch_console")
	_expect_equal(str(simulation.snapshot().get("outcome", "")), "costly_success", "emergency route reaches a deliberate costly success")


func _test_illegal_actions_and_carry_slot() -> void:
	var simulation: MissionSimulation = _new_simulation()
	var initial: Dictionary = simulation.snapshot()
	var illegal_move: Dictionary = simulation.propose("move", "escape_pod")
	_expect_equal(str(illegal_move.get("status", "")), "invalid", "cannot move through locked escape bulkhead")
	_expect_equal(int(simulation.snapshot().get("turn", -1)), int(initial.get("turn", -2)), "illegal action consumes no turn")
	_expect_equal(simulation.snapshot().get("resources", {}), initial.get("resources", {}), "illegal action consumes no resources")
	var unknown: Dictionary = simulation.propose("teleport", "escape_pod")
	_expect_equal(str(unknown.get("status", "")), "invalid", "unknown action is rejected")
	_execute(simulation, "take", "phase_fuse")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "power_bay")
	var full_slot: Dictionary = simulation.propose("take", "sealant_kit")
	_expect_equal(str(full_slot.get("status", "")), "invalid", "one-slot inventory rejects second item")
	_expect_equal(str(simulation.snapshot().get("carried_item", "")), "phase_fuse", "failed take preserves carried item")


func _test_danger_confirmation_can_cancel() -> void:
	var simulation: MissionSimulation = _new_simulation()
	_execute(simulation, "take", "phase_fuse")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "power_bay")
	_execute(simulation, "inspect", "cable_panel")
	var before: Dictionary = simulation.snapshot()
	var pending: Dictionary = simulation.propose("connect", "red_cable")
	_expect_equal(str(pending.get("status", "")), "confirmation_required", "energized cable requires confirmation")
	_expect_equal(int(simulation.snapshot().get("turn", -1)), int(before.get("turn", -2)), "proposal alone consumes no turn")
	var canceled: Dictionary = simulation.confirm(int(pending.get("proposal_id", -1)), false)
	_expect_equal(str(canceled.get("status", "")), "canceled", "dangerous action can be canceled")
	_expect_equal(simulation.snapshot().get("resources", {}), before.get("resources", {}), "canceled danger consumes no resources")
	_expect((simulation.snapshot().get("pending_confirmation", {}) as Dictionary).is_empty(), "cancel clears pending confirmation")


func _test_wrong_cable_costly_completion() -> void:
	var simulation: MissionSimulation = _new_simulation()
	_execute(simulation, "take", "phase_fuse")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "power_bay")
	_execute(simulation, "inspect", "cable_panel")
	var before: Dictionary = simulation.snapshot()
	var wrong_result: Dictionary = _confirm_action(simulation, "connect", _wrong_cable(simulation))
	var after_error: Dictionary = simulation.snapshot()
	_expect(not str((wrong_result.get("event", {}) as Dictionary).get("npc_line", "")).is_empty(), "mistake event includes Lin Lan's restrained reaction")
	_expect_equal(int(after_error.get("mistakes", 0)), 1, "wrong cable records a mistake")
	_expect_equal(int((after_error.get("resources", {}) as Dictionary).get("power", 0)), int((before.get("resources", {}) as Dictionary).get("power", 0)) - 19, "wrong cable pays base and short-circuit power cost")
	_expect_equal(int((after_error.get("resources", {}) as Dictionary).get("oxygen", 0)), int((before.get("resources", {}) as Dictionary).get("oxygen", 0)) - 8, "wrong cable damages oxygen circuit")
	_expect_equal(str((after_error.get("puzzles", {}) as Dictionary).get("power", "")), "unsolved", "wrong cable does not solve power puzzle")

	_confirm_action(simulation, "connect", _correct_cable(simulation))
	_execute(simulation, "use", "phase_fuse")
	_execute(simulation, "take", "sealant_kit")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "coolant_gallery")
	_execute(simulation, "inspect", "valve_manifold")
	_perform_coolant_solution(simulation)
	_execute(simulation, "use", "sealant_kit")
	_execute(simulation, "move", "central_junction")
	_execute(simulation, "move", "escape_pod")
	_execute(simulation, "use", "launch_console")
	_expect_equal(str(simulation.snapshot().get("outcome", "")), "costly_success", "recoverable cable error leads to costly success")


func _test_resource_failure() -> void:
	var simulation: MissionSimulation = _new_simulation()
	var guard: int = 0
	while not bool(simulation.snapshot().get("is_terminal", false)) and guard < 30:
		_execute(simulation, "wait", "")
		guard += 1
	var ending: Dictionary = simulation.snapshot()
	_expect(guard < 30, "resource exhaustion terminates in finite turns")
	_expect_equal(str(ending.get("outcome", "")), "failure", "oxygen exhaustion reaches failure ending")
	_expect_equal(str(ending.get("ending_reason", "")), "oxygen_depleted", "failure reports depleted oxygen")
	var after_terminal: Dictionary = simulation.propose("wait", "")
	_expect_equal(str(after_terminal.get("status", "")), "terminal", "terminal mission rejects further proposals")
	var restarted: Dictionary = simulation.restart()
	_expect_equal(str(restarted.get("outcome", "")), "ongoing", "restart clears ending")
	_expect_equal(int(restarted.get("turn", -1)), 0, "restart resets turn counter")


func _execute(simulation: MissionSimulation, action_id: String, target: String) -> Dictionary:
	var result: Dictionary = simulation.propose(action_id, target)
	_expect_equal(str(result.get("status", "")), "executed", "executes %s:%s" % [action_id, target])
	return result


func _confirm_action(simulation: MissionSimulation, action_id: String, target: String) -> Dictionary:
	var proposal: Dictionary = simulation.propose(action_id, target)
	_expect_equal(str(proposal.get("status", "")), "confirmation_required", "confirms dangerous %s:%s" % [action_id, target])
	var proposal_id: int = int(proposal.get("proposal_id", -1))
	_expect(proposal_id > 0, "dangerous action has proposal id")
	var result: Dictionary = simulation.confirm(proposal_id, true)
	_expect_equal(str(result.get("status", "")), "executed", "confirmed action executes %s:%s" % [action_id, target])
	return result


func _perform_coolant_solution(simulation: MissionSimulation) -> void:
	var required := _coolant_targets(simulation)
	_expect_equal(required.size(), 2, "coolant pressure puzzle has a two-regulator solution")
	for value: Variant in required:
		var target := str(value)
		var proposal := simulation.propose("toggle", target)
		if str(proposal.get("status", "")) == "confirmation_required":
			var result := simulation.confirm(int(proposal.get("proposal_id", -1)), true)
			_expect_equal(str(result.get("status", "")), "executed", "confirmed pressure regulator executes: %s" % target)
		else:
			_expect_equal(str(proposal.get("status", "")), "executed", "pressure regulator executes: %s" % target)


func _expect(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		return
	_failures += 1
	push_error("FAIL: %s" % label)


func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	_expect(actual == expected, "%s (expected=%s actual=%s)" % [label, str(expected), str(actual)])
