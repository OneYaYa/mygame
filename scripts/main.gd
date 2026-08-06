extends Node


const DecisionServiceClass := preload("res://scripts/services/npc_decision_service.gd")
const ContextCompilerClass := preload("res://scripts/services/npc_context_compiler.gd")
const ProceduralAudioClass := preload("res://scripts/services/procedural_audio.gd")
const CORE_SCRIPT_PATH := "res://scripts/core/mission_simulation.gd"

@onready var ui: MissionConsoleUI = $MissionConsoleUI

var _simulation: RefCounted
var _decision_service: NpcDecisionService
var _context_compiler: NpcContextCompiler
var _audio: ProceduralAudio
var _snapshot: Dictionary = {}
var _last_confirmation_id := -1
var _conversation_history: Array[Dictionary] = []
var _conversation_facts: Dictionary = {}
var _last_player_message := ""


func _ready() -> void:
	_context_compiler = ContextCompilerClass.new() as NpcContextCompiler
	_audio = ProceduralAudioClass.new()
	_audio.name = "ProceduralAudio"
	add_child(_audio)
	_decision_service = DecisionServiceClass.new()
	_decision_service.name = "NpcDecisionService"
	add_child(_decision_service)
	_decision_service.decision_ready.connect(_on_decision_ready)
	_decision_service.status_changed.connect(_on_provider_status_changed)
	ui.message_submitted.connect(_on_message_submitted)
	ui.action_requested.connect(_on_action_requested)
	ui.proposal_confirmation_requested.connect(_on_proposal_confirmation_requested)
	ui.restart_requested.connect(_on_restart_requested)
	ui.decision_cancel_requested.connect(_on_decision_cancel_requested)
	ui.settings_changed.connect(_on_settings_changed)
	_on_settings_changed(ui.get_settings())
	_initialize_simulation()


func _initialize_simulation() -> void:
	if not ResourceLoader.exists(CORE_SCRIPT_PATH):
		_show_core_waiting("核心脚本尚未出现；UI 已进入只读演示模式")
		return
	var resource: Resource = load(CORE_SCRIPT_PATH)
	if not resource is Script:
		_show_core_waiting("MissionSimulation 资源类型无效")
		return
	var instance: Variant = (resource as Script).new()
	if not instance is RefCounted:
		_show_core_waiting("MissionSimulation 必须继承 RefCounted")
		return
	_simulation = instance as RefCounted
	_connect_core_signal("state_changed", _on_core_state_changed)
	_connect_core_signal("mission_event", _on_mission_event)
	_connect_core_signal("confirmation_required", _on_confirmation_required)
	_connect_core_signal("mission_ended", _on_mission_ended)
	ui.set_core_status(true, "本地 MissionSimulation 已链接")
	_restart_core()


func _connect_core_signal(signal_name: StringName, callable: Callable) -> void:
	if _simulation != null and _simulation.has_signal(signal_name) and not _simulation.is_connected(signal_name, callable):
		_simulation.connect(signal_name, callable)


func _restart_core() -> void:
	if _simulation == null:
		_show_core_waiting("本地核心不可用，无法重开")
		return
	_decision_service.cancel_pending()
	_last_confirmation_id = -1
	_conversation_history.clear()
	_last_player_message = ""
	_conversation_facts = {
		"player_name": "",
		"promises": [],
	}
	ui.reset_console()
	var result: Variant = _simulation.call("restart")
	if result is Dictionary:
		_apply_snapshot(result as Dictionary)
	else:
		_refresh_from_core()
	var npc_intro := str(_snapshot.get("npc_intro", "")).strip_edges()
	if not npc_intro.is_empty():
		var npc: Dictionary = _dictionary(_snapshot.get("npc", {}))
		ui.append_dialogue(str(npc.get("name", "林岚")), npc_intro, "npc")
		_record_conversation("npc", npc_intro)
	else:
		ui.append_system("盲区中继任务启动。通讯已经接通，先确认林岚的状况。")


func _refresh_from_core() -> void:
	if _simulation == null:
		return
	var snapshot_value: Variant = _simulation.call("snapshot")
	if snapshot_value is Dictionary:
		_apply_snapshot(snapshot_value as Dictionary)


func _apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	var actions := _valid_actions()
	var view_snapshot := _snapshot.duplicate(true)
	view_snapshot["available_actions"] = actions
	ui.render_snapshot(view_snapshot)
	ui.set_actions(actions)


func _valid_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _simulation == null:
		return result
	var value: Variant = _simulation.call("valid_actions")
	if not value is Array:
		return result
	for raw: Variant in value as Array:
		if raw is Dictionary:
			result.append((raw as Dictionary).duplicate(true))
	return result


func _on_message_submitted(text: String) -> void:
	if _simulation == null or _snapshot.is_empty():
		ui.append_system("本地核心尚未就绪；无法构造安全的 NPC 上下文。", "warning")
		return
	ui.append_dialogue("OPERATOR", text, "player")
	ui.set_thinking(true)
	ui.show_candidate("")
	var context := _build_npc_context(text)
	_decision_service.request_decision(context, text)
	_last_player_message = text
	_remember_player_facts(text)
	_record_conversation("player", text)


func _build_npc_context(player_text: String = "") -> Dictionary:
	var context: Dictionary = {}
	if _simulation != null and _simulation.has_method("build_npc_context"):
		var value: Variant = _simulation.call("build_npc_context")
		if value is Dictionary:
			context = (value as Dictionary).duplicate(true)
	return _context_compiler.compile(
		context,
		_snapshot,
		_valid_actions(),
		_conversation_history,
		_conversation_facts,
		player_text
	)


func _on_decision_ready(decision: Dictionary) -> void:
	ui.set_thinking(false)
	if _simulation != null and _simulation.has_method("record_conversation"):
		var social_value: Variant = _simulation.call("record_conversation", _last_player_message, decision.duplicate(true))
		if social_value is Dictionary:
			_snapshot = (social_value as Dictionary).duplicate(true)
	var npc: Dictionary = _dictionary(_snapshot.get("npc", {}))
	var npc_name := str(npc.get("name", "林岚"))
	var reply := str(decision.get("reply", "通讯中断。"))
	ui.append_dialogue(npc_name, reply, "npc")
	_record_conversation("npc", reply)
	var current_actions := _valid_actions()
	ui.set_actions(current_actions)
	var candidate_valid := bool(decision.get("candidate_valid", false))
	ui.show_candidate(
		str(decision.get("action", "")) if candidate_valid else "",
		str(decision.get("target", "")) if candidate_valid else ""
	)
	var view_snapshot := _snapshot.duplicate(true)
	var view_npc := npc.duplicate(true)
	view_npc["mood"] = str(decision.get("mood", view_npc.get("mood", "focused")))
	view_snapshot["npc"] = view_npc
	view_snapshot["available_actions"] = current_actions
	ui.render_snapshot(view_snapshot)
	if candidate_valid:
		_audio.play_cue("candidate")
		ui.append_system("林岚提出了一项行动请求；请在右侧单独决定是否授权。", "info")
	if decision.has("fallback_reason"):
		ui.append_system("远端不可用，已用本地回复完成本轮对话。", "warning")
	ui.focus_message_input()


func _on_action_requested(action_id: String, target: String, arguments: Dictionary) -> void:
	if _simulation == null:
		ui.append_system("核心未链接；动作被拒绝。", "warning")
		return
	# This is the only path from UI to simulation. Model decisions never call this method.
	var value: Variant = _simulation.call("propose", action_id, target, arguments.duplicate(true))
	if not value is Dictionary:
		ui.append_system("核心没有返回结构化动作结果。", "warning")
		return
	var result := value as Dictionary
	var status := str(result.get("status", ""))
	var proposal_id := int(result.get("proposal_id", -1))
	if status == "confirmation_required":
		if proposal_id != _last_confirmation_id:
			_on_confirmation_required(result)
		return
	ui.show_action_result(result)
	if result.has("snapshot") and result["snapshot"] is Dictionary:
		_apply_snapshot(result["snapshot"] as Dictionary)
	else:
		_refresh_from_core()


func _on_proposal_confirmation_requested(proposal_id: int, accepted: bool) -> void:
	if _simulation == null:
		return
	var value: Variant = _simulation.call("confirm", proposal_id, accepted)
	_last_confirmation_id = -1
	if value is Dictionary:
		var result := value as Dictionary
		ui.show_action_result(result)
		if result.has("snapshot") and result["snapshot"] is Dictionary:
			_apply_snapshot(result["snapshot"] as Dictionary)
		else:
			_refresh_from_core()


func _on_restart_requested() -> void:
	_restart_core()


func _on_decision_cancel_requested() -> void:
	_decision_service.cancel_pending()


func _on_core_state_changed(snapshot: Dictionary) -> void:
	_apply_snapshot(snapshot)


func _on_mission_event(event: Dictionary) -> void:
	# Core events are ingested from the authoritative snapshot log. Only the
	# character line is appended here so a single action never appears twice.
	var npc_line := str(event.get("npc_line", "")).strip_edges()
	var event_type := str(event.get("type", "message"))
	_audio.play_cue("hazard" if event_type == "hazard" else "success" if event_type in ["puzzle_solved", "ending"] else event_type)
	if not npc_line.is_empty():
		var npc: Dictionary = _dictionary(_snapshot.get("npc", {}))
		ui.append_dialogue(str(npc.get("name", "林岚")), npc_line, "npc")
		_record_conversation("npc", npc_line)


func _on_confirmation_required(proposal: Dictionary) -> void:
	_last_confirmation_id = int(proposal.get("proposal_id", proposal.get("id", -1)))
	ui.present_confirmation(proposal)


func _on_mission_ended(outcome: String, snapshot: Dictionary) -> void:
	_audio.play_cue("failure" if outcome == "failure" else "success")
	_apply_snapshot(snapshot)
	ui.show_outcome(outcome, snapshot)


func _on_provider_status_changed(status: String, detail: String) -> void:
	ui.set_connection_status(status, detail)


func _on_settings_changed(settings: Dictionary) -> void:
	if is_instance_valid(_audio):
		_audio.configure(float(settings.get("volume", 0.65)), bool(settings.get("muted", false)))
	if is_instance_valid(_decision_service):
		_decision_service.set_online_enabled(bool(settings.get("online_enabled", true)))


func _show_core_waiting(message: String) -> void:
	_snapshot = _placeholder_snapshot()
	ui.set_core_status(false, message)
	ui.render_snapshot(_snapshot)
	ui.set_actions([])
	ui.append_system(message, "warning")


func _placeholder_snapshot() -> Dictionary:
	return {
		"mission_id": "blindspot_relay",
		"mission_name": "BLINDSPOT RELAY / 盲区中继",
		"turn": 0,
		"room_id": "relay",
		"resources": {"oxygen": 100.0, "power": 100.0},
		"carried_item": "无",
		"npc": {"name": "林岚", "room_id": "relay", "mood": "focused", "status": "STANDBY"},
		"objective": "等待本地 MissionSimulation；只读 UI 已就绪。",
		"rooms": [
			{"id": "relay_control", "label": "中继控制室", "code": "RLY-01", "status": "safe"},
			{"id": "central_junction", "label": "中央交汇舱", "code": "JNC-02", "status": "unknown"},
			{"id": "power_bay", "label": "主电网舱", "code": "PWR-03", "status": "offline"},
			{"id": "coolant_gallery", "label": "冷却回廊", "code": "CLT-04", "status": "danger"},
			{"id": "escape_pod", "label": "逃生舱", "code": "ESC-05", "status": "locked"},
		],
		"links": [
			{"from": "central_junction", "to": "relay_control", "state": "open"},
			{"from": "central_junction", "to": "power_bay", "state": "open"},
			{"from": "central_junction", "to": "coolant_gallery", "state": "open"},
			{"from": "central_junction", "to": "escape_pod", "state": "locked"},
		],
	}


func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value as Array if value is Array else []


func _record_conversation(role: String, content: String) -> void:
	var clean := content.strip_edges().left(360)
	if clean.is_empty() or role not in ["player", "npc"]:
		return
	_conversation_history.append({"role": role, "content": clean})
	if _conversation_history.size() > 24:
		_conversation_history = _conversation_history.slice(_conversation_history.size() - 24)


func _remember_player_facts(text: String) -> void:
	var clean := text.strip_edges()
	var name_pattern := RegEx.new()
	if name_pattern.compile("(?:我叫|叫我|我的名字是)([\\p{Han}A-Za-z0-9_·]{1,12})") == OK:
		var matched := name_pattern.search(clean)
		if matched != null:
			_conversation_facts["player_name"] = matched.get_string(1)
	var promises: Array = _array(_conversation_facts.get("promises", []))
	if (clean.contains("我会") or clean.contains("答应你")) and clean.length() <= 80:
		promises.append(clean.left(80))
		if promises.size() > 3:
			promises = promises.slice(promises.size() - 3)
		_conversation_facts["promises"] = promises
