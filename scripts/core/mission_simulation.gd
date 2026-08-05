class_name MissionSimulation
extends RefCounted

signal state_changed(state_snapshot: Dictionary)
signal mission_event(event: Dictionary)
signal confirmation_required(proposal: Dictionary)
signal mission_ended(outcome: String, state_snapshot: Dictionary)

const DEFAULT_MISSION_PATH: String = "res://data/mission.json"
const EXPECTED_ACTION_IDS: PackedStringArray = [
	"move", "inspect", "take", "drop", "connect", "toggle", "use", "wait"
]
const CABLE_TARGETS: PackedStringArray = ["blue_cable", "red_cable", "yellow_cable"]
const VALVE_TARGETS: PackedStringArray = ["valve_i", "valve_b", "valve_p"]
const VALVE_ROLES: PackedStringArray = ["intake", "bypass", "purge"]
const CABLE_READINGS: PackedStringArray = ["4.2 Ω", "6.8 Ω", "2.4 Ω"]

var _mission_path: String = DEFAULT_MISSION_PATH
var _mission_data: Dictionary = {}
var _rooms_by_id: Dictionary = {}
var _action_ids: PackedStringArray = []
var _state: Dictionary = {}
var _pending: Dictionary = {}
var _proposal_counter: int = 0
var _load_error: String = ""
var _variant_rng := RandomNumberGenerator.new()
var _variant_seed: int = -1
var _restart_index: int = 0


func _init(mission_path: String = DEFAULT_MISSION_PATH, variant_seed: int = -1) -> void:
	_mission_path = mission_path
	_variant_seed = variant_seed
	if _variant_seed < 0:
		_variant_seed = int(Time.get_unix_time_from_system() * 1000.0) ^ Time.get_ticks_msec()
	if _load_mission():
		restart()


## Return an immutable-by-convention, deep-copied view of the authoritative state.
func snapshot() -> Dictionary:
	if _state.is_empty():
		return {
			"ok": false,
			"error": _load_error,
			"is_terminal": true,
			"outcome": "failure",
		}
	var mission: Dictionary = _mission_data.get("mission", {}) as Dictionary
	var npc_config: Dictionary = _mission_data.get("npc", {}) as Dictionary
	var flags: Dictionary = _state.get("flags", {}) as Dictionary
	var room_id: String = str(_state.get("room_id", ""))
	var room: Dictionary = _room(room_id)
	var room_items: Dictionary = _state.get("room_items", {}) as Dictionary
	var all_rooms: Array[Dictionary] = []
	for room_variant: Variant in (_mission_data.get("rooms", []) as Array):
		var configured_room: Dictionary = room_variant as Dictionary
		var configured_id: String = str(configured_room.get("id", ""))
		all_rooms.append({
			"id": configured_id,
			"name": str(configured_room.get("name", configured_id)),
			"label": str(configured_room.get("name", configured_id)),
			"code": _room_code(configured_id),
			"current": configured_id == room_id,
			"locked": configured_id == "escape_pod" and not bool(flags.get("escape_unlocked", false)),
			"status": _room_status(configured_id, flags),
		})
	var all_links: Array[Dictionary] = _build_link_views(flags)
	var pending_view: Dictionary = {}
	if not _pending.is_empty():
		pending_view = {
			"proposal_id": int(_pending.get("proposal_id", -1)),
			"action": (_pending.get("action", {}) as Dictionary).duplicate(true),
			"reason": str(_pending.get("reason", "")),
		}
	return {
		"ok": true,
		"mission_id": str(mission.get("id", "")),
		"mission_title": str(mission.get("title", "")),
		"mission_name": str(mission.get("title", "")),
		"objective": str(mission.get("objective", "")),
		"npc_intro": str(npc_config.get("intro", "")),
		"operator_telemetry": _operator_telemetry(flags),
		"npc": {
			"id": str(npc_config.get("id", "")),
			"name": str(npc_config.get("name", "")),
			"role": str(npc_config.get("role", "")),
			"room_id": room_id,
			"mood": _npc_mood(),
			"status": "lost" if bool(_state.get("is_terminal", false)) and str(_state.get("outcome", "")) == "failure" else "active",
		},
		"turn": int(_state.get("turn", 0)),
		"room_id": room_id,
		"room_name": str(room.get("name", room_id)),
		"observation_summary": _current_observation_summary(room_id, flags),
		"rooms": all_rooms,
		"links": all_links,
		"reachable_rooms": _available_move_targets(),
		"resources": (_state.get("resources", {}) as Dictionary).duplicate(true),
		"carried_item": str(_state.get("carried_item", "")),
		"carried_item_name": _item_name(str(_state.get("carried_item", ""))) if not str(_state.get("carried_item", "")).is_empty() else "无",
		"room_items": (room_items.get(room_id, []) as Array).duplicate(true),
		"action_ids": Array(EXPECTED_ACTION_IDS),
		"flags": flags.duplicate(true),
		"puzzles": (_state.get("puzzles", {}) as Dictionary).duplicate(true),
		"scenario_id": str((_state.get("scenario", {}) as Dictionary).get("id", "")),
		"evidence": _evidence_view(flags),
		"npc_social": (_state.get("npc_social", {}) as Dictionary).duplicate(true),
		"npc_beliefs": (_state.get("npc_beliefs", {}) as Dictionary).duplicate(true),
		"mistakes": int(_state.get("mistakes", 0)),
		"pending_confirmation": pending_view,
		"outcome": str(_state.get("outcome", "ongoing")),
		"ending_reason": str(_state.get("ending_reason", "")),
		"debrief": _ending_debrief(),
		"hazard_stage": _hazard_stage(int(_state.get("turn", 0))),
		"is_terminal": bool(_state.get("is_terminal", false)),
		"log": (_state.get("log", []) as Array).duplicate(true),
		"last_event": (_state.get("last_event", {}) as Dictionary).duplicate(true),
	}


## Enumerate only actions that the deterministic simulation can accept now.
func valid_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if _state.is_empty() or bool(_state.get("is_terminal", false)) or not _pending.is_empty():
		return actions
	var room_id: String = str(_state.get("room_id", ""))
	var room: Dictionary = _room(room_id)
	var flags: Dictionary = _state.get("flags", {}) as Dictionary

	for target_variant: Variant in (room.get("links", []) as Array):
		var target: String = str(target_variant)
		if target == "escape_pod" and not bool(flags.get("escape_unlocked", false)):
			continue
		_append_action(actions, "move", target, "前往%s" % _room_name(target))

	for inspect_variant: Variant in (room.get("inspect_targets", []) as Array):
		var inspect_target: String = str(inspect_variant)
		_append_action(actions, "inspect", inspect_target, "检查%s" % _target_label(inspect_target))

	var carried_item: String = str(_state.get("carried_item", ""))
	var room_items: Dictionary = _state.get("room_items", {}) as Dictionary
	if carried_item.is_empty():
		for item_variant: Variant in (room_items.get(room_id, []) as Array):
			var item_id: String = str(item_variant)
			_append_action(actions, "take", item_id, "拾取%s" % _item_name(item_id))
	else:
		_append_action(actions, "drop", carried_item, "放下%s" % _item_name(carried_item))

	if room_id == "power_bay" and bool(flags.get("power_panel_inspected", false)) and not bool(flags.get("grid_online", false)) and not bool(flags.get("phase_cable_connected", false)):
		for cable_id: String in CABLE_TARGETS:
			_append_action(actions, "connect", cable_id, "连接%s" % _target_label(cable_id), true)

	if room_id == "coolant_gallery" and bool(flags.get("manifold_inspected", false)) and not bool(flags.get("valves_aligned", false)):
		for valve_id: String in VALVE_TARGETS:
			_append_action(actions, "toggle", valve_id, "切换%s" % _target_label(valve_id), _valve_role(valve_id) == "purge")

	if room_id == "power_bay" and carried_item == "phase_fuse" and bool(flags.get("phase_cable_connected", false)) and not bool(flags.get("grid_online", false)):
		_append_action(actions, "use", "phase_fuse", "安装相位保险芯")
	if room_id == "coolant_gallery" and carried_item == "sealant_kit" and bool(flags.get("valves_aligned", false)) and not bool(flags.get("leak_sealed", false)):
		_append_action(actions, "use", "sealant_kit", "使用低温密封剂")
	if room_id == "escape_pod" and bool(flags.get("escape_unlocked", false)):
		_append_action(actions, "use", "launch_console", "启动逃生舱")

	_append_action(actions, "wait", "", "等待一个遥测周期")
	return actions


## Propose an action. Safe actions execute immediately; dangerous actions wait for confirm().
func propose(action_id: String, target: String = "", arguments: Dictionary = {}) -> Dictionary:
	if _state.is_empty():
		return _result(false, "invalid", "任务数据不可用。", {})
	if bool(_state.get("is_terminal", false)):
		return _result(false, "terminal", "任务已经结束；请先重新开始。", {})
	if not _pending.is_empty():
		return _result(false, "confirmation_pending", "已有危险动作等待确认。", {})
	var normalized_id: String = action_id.strip_edges().to_lower()
	var normalized_target: String = target.strip_edges().to_lower()
	var action: Dictionary = {
		"id": normalized_id,
		"target": normalized_target,
		"arguments": arguments.duplicate(true),
	}
	var validation: Dictionary = _validate_action(action)
	if not bool(validation.get("ok", false)):
		return _result(false, "invalid", str(validation.get("reason", "当前不能执行该动作。")), action)
	if bool(validation.get("dangerous", false)):
		if bool(arguments.get("risk_acknowledged", false)):
			return _execute_action(action)
		_proposal_counter += 1
		_pending = {
			"proposal_id": _proposal_counter,
			"action": action.duplicate(true),
			"reason": str(validation.get("confirmation_reason", "该动作可能造成不可逆后果。")),
		}
		var pending_result: Dictionary = _result(true, "confirmation_required", str(_pending.get("reason", "")), action)
		pending_result["proposal_id"] = _proposal_counter
		pending_result["dangerous"] = true
		pending_result["action_id"] = normalized_id
		pending_result["target"] = normalized_target
		pending_result["label"] = str(validation.get("label", _available_action_label(normalized_id, normalized_target)))
		pending_result["snapshot"] = snapshot()
		confirmation_required.emit(pending_result.duplicate(true))
		state_changed.emit(snapshot())
		return pending_result
	return _execute_action(action)


## Confirm or cancel the one pending dangerous action.
func confirm(proposal_id: int, accepted: bool = true) -> Dictionary:
	if _pending.is_empty():
		return _result(false, "invalid", "没有等待确认的危险动作。", {})
	if int(_pending.get("proposal_id", -1)) != proposal_id:
		return _result(false, "invalid", "确认编号与当前危险动作不匹配。", {})
	var action: Dictionary = (_pending.get("action", {}) as Dictionary).duplicate(true)
	_pending = {}
	if not accepted:
		var canceled: Dictionary = _result(true, "canceled", "危险动作已取消。", action)
		canceled["snapshot"] = snapshot()
		state_changed.emit(snapshot())
		return canceled
	var validation: Dictionary = _validate_action(action)
	if not bool(validation.get("ok", false)):
		return _result(false, "invalid", "世界状态已经变化，动作不再有效。", action)
	return _execute_action(action)


## Reset all mission state and return the initial snapshot.
func restart() -> Dictionary:
	if _mission_data.is_empty() and not _load_mission():
		return snapshot()
	var start: Dictionary = _mission_data.get("start", {}) as Dictionary
	var room_items: Dictionary = {}
	for room_variant: Variant in (_mission_data.get("rooms", []) as Array):
		var room: Dictionary = room_variant as Dictionary
		room_items[str(room.get("id", ""))] = (room.get("items", []) as Array).duplicate(true)
	_variant_rng.seed = _variant_seed + _restart_index * 104729
	var scenario := _build_scenario()
	_restart_index += 1
	_state = {
		"turn": 0,
		"room_id": str(start.get("room_id", "relay_control")),
		"resources": {
			"oxygen": int(start.get("oxygen", 100)),
			"power": int(start.get("power", 70)),
		},
		"carried_item": "",
		"room_items": room_items,
		"flags": {
			"telemetry_inspected": false,
			"power_panel_inspected": false,
			"phase_cable_connected": false,
			"connected_cable": "",
			"grid_online": false,
			"manifold_inspected": false,
			"valve_step": 0,
			"valves_aligned": false,
			"leak_sealed": false,
			"escape_unlocked": false,
		},
		"puzzles": {
			"power": "unsolved",
			"coolant": "unsolved",
		},
		"scenario": scenario,
		"npc_social": {
			"trust": 50,
			"fear": 35,
			"checkins": 0,
			"last_player_line": "",
			"last_npc_mood": "focused",
		},
		"npc_beliefs": {
			"confirmed_local": [],
			"operator_claims": [],
			"confidence": 0,
		},
		"mistakes": 0,
		"outcome": "ongoing",
		"ending_reason": "",
		"is_terminal": false,
		"log": [{
			"turn": 0,
			"type": "mission",
			"text": "中继建立。林岚位于中继控制室。",
		}],
		"last_event": {},
	}
	_pending = {}
	_proposal_counter = 0
	var initial: Dictionary = snapshot()
	state_changed.emit(initial)
	return initial


## Compatibility aliases for UI/service layers. They do not expose mutable state.
func get_snapshot() -> Dictionary:
	return snapshot()


func restart_mission() -> Dictionary:
	return restart()


func request_action(action_id: String, target: String = "", arguments: Dictionary = {}) -> Dictionary:
	return propose(action_id, target, arguments)


## Build a state-grounded prompt payload containing only Lin Lan's local observation.
func build_npc_context() -> Dictionary:
	var current: Dictionary = snapshot()
	if not bool(current.get("ok", false)):
		return current
	var room: Dictionary = _room(str(current.get("room_id", "")))
	var flags: Dictionary = _state.get("flags", {}) as Dictionary
	var visible: Array[Dictionary] = _visible_observations(room, current)
	var hazards: Array[String] = _visible_hazards(str(current.get("room_id", "")), flags)
	var local_state: Dictionary = {
		"room_id": current.get("room_id", ""),
		"room_name": current.get("room_name", ""),
		"observation": _current_observation_summary(str(current.get("room_id", "")), flags),
		"visible_items": (current.get("room_items", []) as Array).duplicate(true),
		"carried_item": current.get("carried_item", ""),
		"oxygen": (current.get("resources", {}) as Dictionary).get("oxygen", 0),
		"stress": _npc_stress(current),
		"physical_state": _npc_physical_state(current),
		"trust": int((_state.get("npc_social", {}) as Dictionary).get("trust", 50)),
		"fear": int((_state.get("npc_social", {}) as Dictionary).get("fear", 35)),
		"known_facts": _npc_known_facts(flags),
		"beliefs": (_state.get("npc_beliefs", {}) as Dictionary).duplicate(true),
	}
	if str(current.get("room_id", "")) == "power_bay":
		local_state["panel_inspected"] = bool(flags.get("power_panel_inspected", false))
		local_state["phase_cable_connected"] = bool(flags.get("phase_cable_connected", false))
		if bool(flags.get("power_panel_inspected", false)):
			local_state["panel_details"] = _cable_detail_text()
		local_state["grid_online"] = bool(flags.get("grid_online", false))
	elif str(current.get("room_id", "")) == "coolant_gallery":
		local_state["manifold_inspected"] = bool(flags.get("manifold_inspected", false))
		local_state["completed_valve_steps"] = int(flags.get("valve_step", 0))
		local_state["valves_aligned"] = bool(flags.get("valves_aligned", false))
		local_state["leak_sealed"] = bool(flags.get("leak_sealed", false))
		if bool(flags.get("manifold_inspected", false)):
			local_state["manifold_details"] = _valve_detail_text()
	var log: Array = _state.get("log", []) as Array
	var observation: Dictionary = {
		"room_id": current.get("room_id", ""),
		"room_name": current.get("room_name", ""),
		"summary": _current_observation_summary(str(current.get("room_id", "")), flags),
		"visible": visible.duplicate(true),
		"hazards": hazards.duplicate(),
	}
	return {
		"mission": (_mission_data.get("mission", {}) as Dictionary).duplicate(true),
		"npc": (_mission_data.get("npc", {}) as Dictionary).duplicate(true),
		"local_state": local_state,
		"observation": observation,
		"visible_observations": visible,
		"allowed_actions": valid_actions(),
		"recent_events": log.slice(maxi(0, log.size() - 6)),
		"contract": "只可从 allowed_actions 选择候选动作；不得发明物品、房间、资源或直接修改状态。",
	}


## Record social consequences without advancing the facility clock. The model
## expresses the state; the local simulation owns and clamps the values.
func record_conversation(player_text: String, decision: Dictionary) -> Dictionary:
	if _state.is_empty() or bool(_state.get("is_terminal", false)):
		return snapshot()
	var social: Dictionary = _state.get("npc_social", {}) as Dictionary
	var trust := int(social.get("trust", 50))
	var fear := int(social.get("fear", 35))
	var intent := str(decision.get("intent", "conversation"))
	var mood := str(decision.get("mood", "focused"))
	if intent == "reassure":
		trust += 4
		fear -= 3
		social["checkins"] = int(social.get("checkins", 0)) + 1
	elif intent == "report":
		trust += 1
	elif intent == "refuse":
		trust -= 1
	if mood in ["afraid", "hurt"]:
		fear += 1
	var compact := player_text.replace(" ", "")
	if compact.contains("闭嘴") or compact.contains("废物") or compact.contains("快点照做"):
		trust -= 8
		fear += 6
	social["trust"] = clampi(trust, 0, 100)
	social["fear"] = clampi(fear, 0, 100)
	social["last_player_line"] = player_text.left(120)
	social["last_npc_mood"] = mood
	_state["npc_social"] = social
	var beliefs: Dictionary = _state.get("npc_beliefs", {}) as Dictionary
	if compact.contains("Ω") or compact.contains("欧") or (compact.contains("阀") and (compact.contains("顺序") or compact.contains("先"))):
		var claims: Array = beliefs.get("operator_claims", []) as Array
		claims.append(player_text.left(100))
		if claims.size() > 3:
			claims = claims.slice(claims.size() - 3)
		beliefs["operator_claims"] = claims
		beliefs["confidence"] = clampi(int(social.get("trust", 50)), 10, 90)
	_state["npc_beliefs"] = beliefs
	return snapshot()


func _load_mission() -> bool:
	_load_error = ""
	_rooms_by_id = {}
	_action_ids = []
	if not FileAccess.file_exists(_mission_path):
		_load_error = "任务文件不存在：%s" % _mission_path
		push_error(_load_error)
		return false
	var file: FileAccess = FileAccess.open(_mission_path, FileAccess.READ)
	if file == null:
		_load_error = "无法读取任务文件：%s" % _mission_path
		push_error(_load_error)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_error = "任务文件不是有效 JSON 对象。"
		push_error(_load_error)
		return false
	_mission_data = parsed as Dictionary
	var validation_errors: PackedStringArray = _validate_mission_data()
	if not validation_errors.is_empty():
		_load_error = "; ".join(validation_errors)
		_mission_data = {}
		push_error(_load_error)
		return false
	return true


func _validate_mission_data() -> PackedStringArray:
	var errors: PackedStringArray = []
	if int(_mission_data.get("schema_version", 0)) != 1:
		errors.append("schema_version 必须为 1")
	var rooms: Array = _mission_data.get("rooms", []) as Array
	if rooms.size() != 5:
		errors.append("垂直切片必须恰好包含 5 个房间")
	for room_variant: Variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			errors.append("房间条目必须是对象")
			continue
		var room: Dictionary = room_variant as Dictionary
		var room_id: String = str(room.get("id", ""))
		if room_id.is_empty() or _rooms_by_id.has(room_id):
			errors.append("房间 ID 缺失或重复：%s" % room_id)
		else:
			_rooms_by_id[room_id] = room.duplicate(true)
	var actions: Array = _mission_data.get("actions", []) as Array
	for action_variant: Variant in actions:
		var action: Dictionary = action_variant as Dictionary
		_action_ids.append(str(action.get("id", "")))
	if _action_ids.size() != EXPECTED_ACTION_IDS.size():
		errors.append("必须恰好定义 8 类动作")
	for expected_id: String in EXPECTED_ACTION_IDS:
		if expected_id not in _action_ids:
			errors.append("缺少动作：%s" % expected_id)
	var start: Dictionary = _mission_data.get("start", {}) as Dictionary
	if not _rooms_by_id.has(str(start.get("room_id", ""))):
		errors.append("起始房间不存在")
	for room_id_variant: Variant in _rooms_by_id:
		var configured_room: Dictionary = _rooms_by_id[room_id_variant] as Dictionary
		for link_variant: Variant in (configured_room.get("links", []) as Array):
			if not _rooms_by_id.has(str(link_variant)):
				errors.append("%s 指向不存在的房间 %s" % [str(room_id_variant), str(link_variant)])
	return errors


func _validate_action(action: Dictionary) -> Dictionary:
	var action_id: String = str(action.get("id", ""))
	var target: String = str(action.get("target", ""))
	if action_id not in _action_ids:
		return {"ok": false, "reason": "未知动作：%s" % action_id}
	for available: Dictionary in valid_actions():
		if str(available.get("id", "")) == action_id and str(available.get("target", "")) == target:
			return {
				"ok": true,
				"dangerous": bool(available.get("dangerous", false)),
				"label": str(available.get("label", action_id)),
				"confirmation_reason": _danger_reason(action_id, target),
			}
	return {"ok": false, "reason": _invalid_action_reason(action_id, target)}


func _invalid_action_reason(action_id: String, target: String) -> String:
	var room_id: String = str(_state.get("room_id", ""))
	var flags: Dictionary = _state.get("flags", {}) as Dictionary
	if action_id == "move" and target == "escape_pod" and not bool(flags.get("escape_unlocked", false)):
		return "逃生舱仍受电网与冷却联锁控制。"
	if action_id == "take" and not str(_state.get("carried_item", "")).is_empty():
		return "携带槽已满；必须先使用或放下当前物品。"
	if action_id == "connect" and room_id != "power_bay":
		return "当前位置没有可连接的相位电缆。"
	if action_id == "connect" and not bool(flags.get("power_panel_inspected", false)):
		return "必须先检查电缆面板。"
	if action_id == "toggle" and not bool(flags.get("manifold_inspected", false)):
		return "必须先检查冷却阀组。"
	return "当前状态不能执行 %s:%s。" % [action_id, target]


func _danger_reason(action_id: String, target: String) -> String:
	if action_id == "connect":
		return "相位电缆带电。错误连接会消耗大量电力并损伤氧气回路，是否执行？"
	if action_id == "toggle" and _valve_role(target) == "purge":
		return "排放会立即损失舱内氧气；必须确认前两步顺序正确，是否执行？"
	return "该动作可能造成不可逆后果，是否执行？"


func _execute_action(action: Dictionary) -> Dictionary:
	var action_id: String = str(action.get("id", ""))
	var target: String = str(action.get("target", ""))
	var oxygen_before: int = _resource("oxygen")
	_state["turn"] = int(_state.get("turn", 0)) + 1
	_spend_base_resources(action_id)
	var event: Dictionary
	if _resources_depleted():
		event = _finish_failure("oxygen_depleted" if _resource("oxygen") <= 0 else "power_depleted")
	else:
		match action_id:
			"move":
				event = _apply_move(target)
			"inspect":
				event = _apply_inspect(target)
			"take":
				event = _apply_take(target)
			"drop":
				event = _apply_drop(target)
			"connect":
				event = _apply_connect(target)
			"toggle":
				event = _apply_toggle(target)
			"use":
				event = _apply_use(target)
			"wait":
				event = {"type": "wait", "text": "林岚等待了一个遥测周期。"}
			_:
				event = {"type": "error", "text": "动作没有对应的执行器。"}
		if not bool(_state.get("is_terminal", false)) and _resources_depleted():
			event = _finish_failure("oxygen_depleted" if _resource("oxygen") <= 0 else "power_depleted")
	if oxygen_before > 25 and _resource("oxygen") <= 25 and not bool(_state.get("is_terminal", false)):
		event["npc_line"] = "调度，我的呼吸器开始抢气了。别断线——我还能走，但每一步都得算。"
	event["turn"] = int(_state.get("turn", 0))
	event["action"] = action.duplicate(true)
	_state["last_event"] = event.duplicate(true)
	var log: Array = _state.get("log", []) as Array
	log.append(event.duplicate(true))
	_state["log"] = log
	var state_view: Dictionary = snapshot()
	var result: Dictionary = _result(true, "executed", str(event.get("text", "")), action)
	result["event"] = event.duplicate(true)
	result["snapshot"] = state_view
	mission_event.emit(event.duplicate(true))
	state_changed.emit(state_view)
	if bool(_state.get("is_terminal", false)):
		mission_ended.emit(str(_state.get("outcome", "failure")), state_view)
	return result


func _apply_move(target: String) -> Dictionary:
	_state["room_id"] = target
	var event: Dictionary = {
		"type": "movement",
		"text": "林岚抵达%s。%s" % [_room_name(target), str(_room(target).get("observation", ""))],
	}
	match target:
		"power_bay":
			event["npc_line"] = "这里有焦糊味，接头还在轻响。我的手有点抖，先让我看清再碰。"
		"coolant_gallery":
			event["npc_line"] = "冷雾到膝盖了，面罩边上全是霜……我只能看清一小块。你问哪儿，我就凑近看。"
		"central_junction":
			event["npc_line"] = "我到交汇舱了。逃生门就在前面，但两盏锁灯还是红的。"
	return event


func _apply_inspect(target: String) -> Dictionary:
	var flags: Dictionary = _state.get("flags", {}) as Dictionary
	var text: String
	var npc_line: String = ""
	match target:
		"telemetry_console":
			flags["telemetry_inspected"] = true
			text = "遥测深扫完成：两段损坏前的诊断记录已同步到远程操作端。"
			npc_line = "屏幕烧成一片雪花了。你那边还能收到东西吗？我这儿什么都读不出来。"
		"escape_bulkhead":
			text = "隔门联锁状态：电网%s，冷却%s。" % [
				"正常" if bool(flags.get("grid_online", false)) else "离线",
				"正常" if bool(flags.get("leak_sealed", false)) else "失压",
			]
		"cable_panel":
			var first_power_inspection: bool = not bool(flags.get("power_panel_inspected", false))
			flags["power_panel_inspected"] = true
			text = _cable_detail_text()
			_remember_confirmed_local(text)
			if first_power_inspection:
				npc_line = "标签全糊了。我逐个读到：%s……你拿远端启动记录帮我对，别让我凭颜色蒙。" % _cable_detail_text()
		"valve_manifold":
			var first_coolant_inspection: bool = not bool(flags.get("manifold_inspected", false))
			flags["manifold_inspected"] = true
			text = _valve_detail_text()
			_remember_confirmed_local(text)
			if first_coolant_inspection:
				npc_line = "步骤牌整个掉了，但管路还能追：%s你那边按功能顺序告诉我。" % _valve_detail_text()
		"launch_console":
			text = "逃生舱自检完成。启动将立即结束本次任务。"
		_:
			text = "没有发现新的可验证信息。"
	_state["flags"] = flags
	var event: Dictionary = {"type": "inspection", "text": text, "target": target}
	if not npc_line.is_empty():
		event["npc_line"] = npc_line
	return event


func _apply_take(item_id: String) -> Dictionary:
	var room_id: String = str(_state.get("room_id", ""))
	var room_items: Dictionary = _state.get("room_items", {}) as Dictionary
	var items_here: Array = room_items.get(room_id, []) as Array
	items_here.erase(item_id)
	room_items[room_id] = items_here
	_state["room_items"] = room_items
	_state["carried_item"] = item_id
	return {"type": "inventory", "text": "林岚拿起了%s。" % _item_name(item_id), "item": item_id}


func _apply_drop(item_id: String) -> Dictionary:
	var room_id: String = str(_state.get("room_id", ""))
	var room_items: Dictionary = _state.get("room_items", {}) as Dictionary
	var items_here: Array = room_items.get(room_id, []) as Array
	items_here.append(item_id)
	room_items[room_id] = items_here
	_state["room_items"] = room_items
	_state["carried_item"] = ""
	return {"type": "inventory", "text": "林岚把%s留在%s。" % [_item_name(item_id), _room_name(room_id)], "item": item_id}


func _apply_connect(target: String) -> Dictionary:
	var flags: Dictionary = _state.get("flags", {}) as Dictionary
	var resources: Dictionary = _state.get("resources", {}) as Dictionary
	var scenario: Dictionary = _state.get("scenario", {}) as Dictionary
	if target == str(scenario.get("correct_cable", "")):
		flags["phase_cable_connected"] = true
		flags["connected_cable"] = target
		resources["power"] = int(resources.get("power", 0)) - 2
		_state["flags"] = flags
		_state["resources"] = resources
		return {
			"type": "puzzle",
			"text": "控制器接受该接头，闭环相位锁定；现在可以安装保险芯。",
			"puzzle": "power",
			"npc_line": "锁定灯亮了……好。控制器里‘咔’地弹开一个小盖，我看见保险芯槽了。",
		}
	_state["mistakes"] = int(_state.get("mistakes", 0)) + 1
	resources["power"] = int(resources.get("power", 0)) - 18
	resources["oxygen"] = int(resources.get("oxygen", 0)) - 6
	_state["resources"] = resources
	return {
		"type": "hazard",
		"text": "%s触发短路，电力与氧气回路同时受损。相位连接没有建立。" % _target_label(target),
		"puzzle": "power",
		"mistake": true,
		"npc_line": "断开了……冲击把我撞到舱壁。给我两秒，我还在线；下一次别让我猜。",
	}


func _apply_toggle(target: String) -> Dictionary:
	var flags: Dictionary = _state.get("flags", {}) as Dictionary
	var resources: Dictionary = _state.get("resources", {}) as Dictionary
	var step: int = int(flags.get("valve_step", 0))
	var sequence: Array = (_state.get("scenario", {}) as Dictionary).get("valve_sequence", []) as Array
	var expected: String = str(sequence[step]) if step < sequence.size() else ""
	if target == expected:
		step += 1
		flags["valve_step"] = step
		if _valve_role(target) == "purge":
			resources["oxygen"] = int(resources.get("oxygen", 0)) - 6
		if step == sequence.size():
			flags["valves_aligned"] = true
			_state["flags"] = flags
			_state["resources"] = resources
			return {
				"type": "puzzle",
				"text": "排压完成，冷却剂裂口已经暴露；现在可以使用密封剂。",
				"puzzle": "coolant",
				"npc_line": "排气声停了。裂口就在护板后面，我伸手够得到……但得先拿到密封剂。",
			}
		_state["flags"] = flags
		_state["resources"] = resources
		return {"type": "puzzle", "text": "阀门顺序正确：%d/3。" % step, "puzzle": "coolant"}
	_state["mistakes"] = int(_state.get("mistakes", 0)) + 1
	flags["valve_step"] = 0
	resources["oxygen"] = int(resources.get("oxygen", 0)) - 6
	if _valve_role(target) == "purge":
		resources["oxygen"] = int(resources.get("oxygen", 0)) - 6
	_state["flags"] = flags
	_state["resources"] = resources
	return {
		"type": "hazard",
		"text": "阀门顺序错误，联锁复位并泄出额外氧气。控制器已回到初始阶段。",
		"puzzle": "coolant",
		"mistake": true,
		"npc_line": "阀组弹回去了——冷气灌进袖口了。等一下……下次别再让我蒙顺序。",
	}


func _apply_use(target: String) -> Dictionary:
	var flags: Dictionary = _state.get("flags", {}) as Dictionary
	var puzzles: Dictionary = _state.get("puzzles", {}) as Dictionary
	var resources: Dictionary = _state.get("resources", {}) as Dictionary
	if target == "phase_fuse":
		_state["carried_item"] = ""
		flags["grid_online"] = true
		puzzles["power"] = "solved"
		resources["power"] = mini(_max_resource("power"), int(resources.get("power", 0)) + 20)
		_state["flags"] = flags
		_state["puzzles"] = puzzles
		_state["resources"] = resources
		_update_escape_lock()
		return {"type": "puzzle_solved", "text": "相位保险芯接通，主电网恢复。", "puzzle": "power"}
	if target == "sealant_kit":
		_state["carried_item"] = ""
		flags["leak_sealed"] = true
		puzzles["coolant"] = "solved"
		_state["flags"] = flags
		_state["puzzles"] = puzzles
		_update_escape_lock()
		return {
			"type": "puzzle_solved",
			"text": "冷却剂裂口已封闭，压力回路恢复。逃生舱联锁解除。",
			"puzzle": "coolant",
			"npc_line": "两盏锁灯都绿了。我看到逃生舱照明了……先别断线，陪我走完最后一段。",
		}
	if target == "launch_console":
		var rules: Dictionary = _mission_data.get("rules", {}) as Dictionary
		var clean_run: bool = int(_state.get("mistakes", 0)) == 0 \
			and bool(flags.get("telemetry_inspected", false)) \
			and _resource("oxygen") >= int(rules.get("success_oxygen_threshold", 50)) \
			and _resource("power") >= int(rules.get("success_power_threshold", 40))
		_state["outcome"] = "success" if clean_run else "costly_success"
		_state["ending_reason"] = "clean_extraction" if clean_run else "damaged_extraction"
		_state["is_terminal"] = true
		var social: Dictionary = _state.get("npc_social", {}) as Dictionary
		var trust := int(social.get("trust", 50))
		var relationship_line := "林岚在脱离后仍保持着通讯。" if trust >= 60 else "林岚沉默地完成了脱离程序。" if trust < 35 else "林岚确认安全后关闭了中继。"
		return {
			"type": "ending",
			"text": ("逃生舱平稳脱离 K-17。林岚与遥测记录均完整获救。" if clean_run else "逃生舱带伤脱离 K-17。林岚获救，但错误操作造成的损失无法追回。") + relationship_line,
			"outcome": _state["outcome"],
		}
	return {"type": "error", "text": "该目标目前无法使用。"}


func _update_escape_lock() -> void:
	var flags: Dictionary = _state.get("flags", {}) as Dictionary
	flags["escape_unlocked"] = bool(flags.get("grid_online", false)) and bool(flags.get("leak_sealed", false))
	_state["flags"] = flags


func _spend_base_resources(action_id: String) -> void:
	var rules: Dictionary = _mission_data.get("rules", {}) as Dictionary
	var oxygen_costs: Dictionary = rules.get("oxygen_costs", {}) as Dictionary
	var power_costs: Dictionary = rules.get("power_costs", {}) as Dictionary
	var resources: Dictionary = _state.get("resources", {}) as Dictionary
	resources["oxygen"] = int(resources.get("oxygen", 0)) - int(oxygen_costs.get(action_id, 0))
	resources["power"] = int(resources.get("power", 0)) - int(power_costs.get(action_id, 0))
	_state["resources"] = resources


func _resources_depleted() -> bool:
	return _resource("oxygen") <= 0 or _resource("power") <= 0


func _finish_failure(reason: String) -> Dictionary:
	_state["outcome"] = "failure"
	_state["ending_reason"] = reason
	_state["is_terminal"] = true
	var text: String = "氧气耗尽，中继失去林岚的生命体征。" if reason == "oxygen_depleted" else "电力耗尽，舱门与生命维持系统同时离线。"
	return {"type": "ending", "text": text, "outcome": "failure", "reason": reason}


func _resource(resource_id: String) -> int:
	return int((_state.get("resources", {}) as Dictionary).get(resource_id, 0))


func _max_resource(resource_id: String) -> int:
	var rules: Dictionary = _mission_data.get("rules", {}) as Dictionary
	return int(rules.get("max_%s" % resource_id, 100))


func _available_move_targets() -> Array[String]:
	var output: Array[String] = []
	if _state.is_empty():
		return output
	var flags: Dictionary = _state.get("flags", {}) as Dictionary
	for target_variant: Variant in (_room(str(_state.get("room_id", ""))).get("links", []) as Array):
		var target: String = str(target_variant)
		if target != "escape_pod" or bool(flags.get("escape_unlocked", false)):
			output.append(target)
	return output


func _append_action(actions: Array[Dictionary], action_id: String, target: String, label: String, dangerous: bool = false) -> void:
	actions.append({
		"id": action_id,
		"target": target,
		"label": label,
		"dangerous": dangerous,
		"keywords": _action_keywords(action_id, target),
	})


func _available_action_label(action_id: String, target: String) -> String:
	for action: Dictionary in valid_actions():
		if str(action.get("id", "")) == action_id and str(action.get("target", "")) == target:
			return str(action.get("label", action_id))
	# valid_actions() is empty while a proposal is pending, so derive a stable fallback.
	if action_id == "move":
		return "前往%s" % _room_name(target)
	return "%s：%s" % [action_id, _target_label(target)]


func _action_keywords(action_id: String, target: String) -> Array[String]:
	var keywords: Array[String] = [action_id]
	if not target.is_empty():
		keywords.append(target)
		keywords.append(_room_name(target) if _rooms_by_id.has(target) else _target_label(target))
	match action_id:
		"move": keywords.append("去")
		"inspect": keywords.append("检查")
		"take": keywords.append("拿")
		"drop": keywords.append("放下")
		"connect": keywords.append("连接")
		"toggle": keywords.append("阀")
		"use": keywords.append("使用")
		"wait": keywords.append("等待")
	return keywords


func _result(ok: bool, status: String, message: String, action: Dictionary) -> Dictionary:
	return {
		"ok": ok,
		"status": status,
		"message": message,
		"action": action.duplicate(true),
	}


func _room(room_id: String) -> Dictionary:
	return _rooms_by_id.get(room_id, {}) as Dictionary


func _room_name(room_id: String) -> String:
	return str(_room(room_id).get("name", room_id))


func _room_code(room_id: String) -> String:
	var codes: Dictionary = {
		"relay_control": "RLY-01",
		"central_junction": "JNC-02",
		"power_bay": "PWR-03",
		"coolant_gallery": "CLT-04",
		"escape_pod": "ESC-05",
	}
	return str(codes.get(room_id, room_id.to_upper().left(6)))


func _room_status(room_id: String, flags: Dictionary) -> String:
	if room_id == "escape_pod":
		return "open" if bool(flags.get("escape_unlocked", false)) else "locked"
	if room_id == "power_bay":
		return "powered" if bool(flags.get("grid_online", false)) else "offline"
	if room_id == "coolant_gallery":
		return "safe" if bool(flags.get("leak_sealed", false)) else "danger"
	return "safe" if room_id == "relay_control" else "open"


func _build_link_views(flags: Dictionary) -> Array[Dictionary]:
	var links: Array[Dictionary] = []
	var seen: Dictionary = {}
	for room_variant: Variant in (_mission_data.get("rooms", []) as Array):
		var room: Dictionary = room_variant as Dictionary
		var from_id: String = str(room.get("id", ""))
		for target_variant: Variant in (room.get("links", []) as Array):
			var to_id: String = str(target_variant)
			var ordered: Array[String] = [from_id, to_id]
			ordered.sort()
			var key: String = "%s|%s" % [ordered[0], ordered[1]]
			if seen.has(key):
				continue
			seen[key] = true
			links.append({
				"from": from_id,
				"to": to_id,
				"state": "locked" if (from_id == "escape_pod" or to_id == "escape_pod") and not bool(flags.get("escape_unlocked", false)) else "open",
			})
	return links


func _visible_observations(room: Dictionary, current: Dictionary) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	for item_variant: Variant in (current.get("room_items", []) as Array):
		var item_id: String = str(item_variant)
		visible.append({"id": item_id, "name": _item_name(item_id), "kind": "item"})
	for target_variant: Variant in (room.get("inspect_targets", []) as Array):
		var target: String = str(target_variant)
		visible.append({"id": target, "name": _target_label(target), "kind": "fixture"})
	return visible


func _visible_hazards(room_id: String, flags: Dictionary) -> Array[String]:
	var hazards: Array[String] = []
	if room_id == "power_bay" and not bool(flags.get("grid_online", false)):
		hazards.append("裸露相位电缆仍然带电")
	if room_id == "coolant_gallery" and not bool(flags.get("leak_sealed", false)):
		hazards.append("冷却回路失压；排放会消耗氧气")
	if _resource("oxygen") <= 25:
		hazards.append("个人氧气余量过低")
	return hazards


## Operator-only diagnostics. This field is deliberately never copied into
## build_npc_context(); Lin Lan must describe the physical side herself.
func _operator_telemetry(flags: Dictionary) -> Array[String]:
	var telemetry: Array[String] = [
		"本轮事故签名：%s。重开任务会生成新的线路读数与阀门映射。" % str((_state.get("scenario", {}) as Dictionary).get("id", "UNKNOWN")),
		"ESC-05 联锁：主电网握手缺失；冷却压差不稳定。",
	]
	if not bool(flags.get("telemetry_inspected", false)):
		telemetry.append("诊断缓存尚未解码。需要在 RLY-01 执行一次遥测深扫。")
		return telemetry
	var scenario: Dictionary = _state.get("scenario", {}) as Dictionary
	var required_reading := str(scenario.get("required_reading", "未知"))
	if bool(flags.get("grid_online", false)):
		telemetry.append("PWR-03：启动闭环稳定，保险芯在线。")
	elif bool(flags.get("phase_cable_connected", false)):
		telemetry.append("PWR-03：%s 启动闭环已锁定；控制器等待保险芯。" % required_reading)
	else:
		telemetry.append("PWR-03 启动记录：本轮控制器需要 %s 闭环返回；必须与现场三只接头的读数交叉核对。" % required_reading)
	var step: int = int(flags.get("valve_step", 0))
	if bool(flags.get("leak_sealed", false)):
		telemetry.append("CLT-04：压差恢复，裂口监测稳定。")
	elif bool(flags.get("valves_aligned", false)):
		telemetry.append("CLT-04：受控排压完成；维护口处裂口已暴露。")
	elif step == 2:
		telemetry.append("CLT-04 阶段记录：来流与回环均已确认；排气联锁现可授权。")
	elif step == 1:
		telemetry.append("CLT-04 阶段记录：来流已确认；等待辅助回环建立压差平衡。")
	else:
		telemetry.append("CLT-04 旧阶段记录：先建立来流，再经辅助回环平衡；两项确认后才允许向舱外排气。")
	return telemetry


func _build_scenario() -> Dictionary:
	var shuffled_readings := _shuffled_strings(CABLE_READINGS)
	var cable_readings: Dictionary = {}
	for index: int in range(CABLE_TARGETS.size()):
		cable_readings[CABLE_TARGETS[index]] = shuffled_readings[index]
	var correct_cable := CABLE_TARGETS[_variant_rng.randi_range(0, CABLE_TARGETS.size() - 1)]
	var shuffled_roles := _shuffled_strings(VALVE_ROLES)
	var valve_roles: Dictionary = {}
	for index: int in range(VALVE_TARGETS.size()):
		valve_roles[VALVE_TARGETS[index]] = shuffled_roles[index]
	var valve_sequence: Array[String] = []
	for required_role: String in VALVE_ROLES:
		for valve_id: String in VALVE_TARGETS:
			if str(valve_roles.get(valve_id, "")) == required_role:
				valve_sequence.append(valve_id)
				break
	return {
		"id": "K17-%04d" % int(abs(_variant_rng.randi()) % 10000),
		"cable_readings": cable_readings,
		"correct_cable": correct_cable,
		"required_reading": str(cable_readings.get(correct_cable, "")),
		"valve_roles": valve_roles,
		"valve_sequence": valve_sequence,
	}


func _shuffled_strings(source: PackedStringArray) -> Array[String]:
	var result: Array[String] = []
	for value: String in source:
		result.append(value)
	for index: int in range(result.size() - 1, 0, -1):
		var other := _variant_rng.randi_range(0, index)
		var temporary := result[index]
		result[index] = result[other]
		result[other] = temporary
	return result


func _current_observation_summary(room_id: String, flags: Dictionary) -> String:
	var base := str(_room(room_id).get("observation", ""))
	if room_id == "power_bay" and bool(flags.get("power_panel_inspected", false)):
		return "%s\n已确认现场读数：%s" % [base, _cable_detail_text()]
	if room_id == "coolant_gallery" and bool(flags.get("manifold_inspected", false)):
		return "%s\n已确认管路：%s" % [base, _valve_detail_text()]
	return base


func _cable_detail_text() -> String:
	var readings: Dictionary = (_state.get("scenario", {}) as Dictionary).get("cable_readings", {}) as Dictionary
	return "蓝色接头 %s；红色接头 %s；黄色接头 %s。" % [
		str(readings.get("blue_cable", "读数不清")),
		str(readings.get("red_cable", "读数不清")),
		str(readings.get("yellow_cable", "读数不清")),
	]


func _valve_detail_text() -> String:
	return "I 阀接%s；B 阀接%s；P 阀接%s。" % [
		_valve_role_description(_valve_role("valve_i")),
		_valve_role_description(_valve_role("valve_b")),
		_valve_role_description(_valve_role("valve_p")),
	]


func _valve_role(valve_id: String) -> String:
	return str(((_state.get("scenario", {}) as Dictionary).get("valve_roles", {}) as Dictionary).get(valve_id, ""))


func _valve_role_description(role: String) -> String:
	match role:
		"intake": return "结霜的来流管"
		"bypass": return "细窄的辅助回环管"
		"purge": return "通往舱外的排气道"
		_: return "无法辨认的管路"


func _evidence_view(flags: Dictionary) -> Dictionary:
	var evidence: Dictionary = {
		"power_local": "等待林岚检查电缆面板。",
		"coolant_local": "等待林岚检查冷却阀组。",
	}
	if bool(flags.get("power_panel_inspected", false)):
		evidence["power_local"] = _cable_detail_text()
	if bool(flags.get("manifold_inspected", false)):
		evidence["coolant_local"] = _valve_detail_text()
	return evidence


func _npc_known_facts(flags: Dictionary) -> Array[String]:
	var facts: Array[String] = []
	if bool(flags.get("power_panel_inspected", false)):
		facts.append(_cable_detail_text())
	if bool(flags.get("phase_cable_connected", false)):
		facts.append("相位闭环已经被控制器接受。")
	if bool(flags.get("manifold_inspected", false)):
		facts.append(_valve_detail_text())
	if int(flags.get("valve_step", 0)) > 0:
		facts.append("阀门联锁已完成 %d/3 步。" % int(flags.get("valve_step", 0)))
	return facts


func _remember_confirmed_local(fact: String) -> void:
	var beliefs: Dictionary = _state.get("npc_beliefs", {}) as Dictionary
	var confirmed: Array = beliefs.get("confirmed_local", []) as Array
	if fact not in confirmed:
		confirmed.append(fact.left(180))
	beliefs["confirmed_local"] = confirmed
	_state["npc_beliefs"] = beliefs


func _npc_mood() -> String:
	var social: Dictionary = _state.get("npc_social", {}) as Dictionary
	var fear := int(social.get("fear", 35))
	if _resource("oxygen") <= 25:
		return "hurt"
	if fear >= 70:
		return "afraid"
	if fear >= 45 or int(_state.get("mistakes", 0)) > 0:
		return "nervous"
	if bool(_state.get("is_terminal", false)) and str(_state.get("outcome", "")) != "failure":
		return "relieved"
	return "focused"


func _hazard_stage(turn: int) -> String:
	if turn >= 14 or _resource("oxygen") <= 25:
		return "critical"
	if turn >= 8 or _resource("oxygen") <= 55:
		return "degrading"
	return "unstable"


func _ending_debrief() -> Dictionary:
	if not bool(_state.get("is_terminal", false)):
		return {}
	var outcome := str(_state.get("outcome", "failure"))
	var social: Dictionary = _state.get("npc_social", {}) as Dictionary
	var trust := int(social.get("trust", 50))
	var relationship := "互相信任" if trust >= 60 else "关系紧张" if trust < 35 else "保持专业"
	var title := "完整撤离" if outcome == "success" else "代价撤离" if outcome == "costly_success" else "通讯终止"
	var body := "林岚与事故遥测完整获救。" if outcome == "success" else "林岚获救，但设施损失被记录在案。" if outcome == "costly_success" else str(_state.get("ending_reason", "任务失败"))
	return {
		"title": title,
		"body": body,
		"relationship": relationship,
		"trust": trust,
		"checkins": int(social.get("checkins", 0)),
		"mistakes": int(_state.get("mistakes", 0)),
		"scenario_id": str((_state.get("scenario", {}) as Dictionary).get("id", "")),
	}


func _npc_stress(current: Dictionary) -> String:
	var oxygen: int = int((current.get("resources", {}) as Dictionary).get("oxygen", 100))
	var mistakes: int = int(current.get("mistakes", 0))
	var fear: int = int((_state.get("npc_social", {}) as Dictionary).get("fear", 35))
	if oxygen <= 25:
		return "critical_but_functional"
	if oxygen <= 50 or mistakes >= 2 or fear >= 70:
		return "strained"
	if mistakes > 0 or str(current.get("room_id", "")) in ["power_bay", "coolant_gallery"]:
		return "tense"
	return "controlled"


func _npc_physical_state(current: Dictionary) -> String:
	var oxygen: int = int((current.get("resources", {}) as Dictionary).get("oxygen", 100))
	if oxygen <= 25:
		return "呼吸器供气断续，讲话需要停顿；左肩挫伤，但仍能行走和单手操作。"
	if oxygen <= 50:
		return "呼吸明显加快，面罩起雾；左肩挫伤，精细操作变慢。"
	if str(current.get("room_id", "")) == "coolant_gallery":
		return "低温冷雾正在面罩边缘结霜；左肩挫伤，仍可单手操作。"
	return "左肩挫伤、抬臂受限；呼吸尚可控制，仍能行走和单手操作。"


func _item_name(item_id: String) -> String:
	var items: Dictionary = _mission_data.get("items", {}) as Dictionary
	var item: Dictionary = items.get(item_id, {}) as Dictionary
	return str(item.get("name", item_id))


func _target_label(target: String) -> String:
	var labels: Dictionary = {
		"telemetry_console": "遥测台",
		"escape_bulkhead": "逃生舱隔门",
		"cable_panel": "电缆面板",
		"valve_manifold": "冷却阀组",
		"launch_console": "发射控制器",
		"blue_cable": "蓝色套管接头",
		"red_cable": "红色陶瓷接头",
		"yellow_cable": "黄色编织接头",
		"valve_i": "I 阀",
		"valve_b": "B 阀",
		"valve_p": "P 阀",
	}
	return str(labels.get(target, target))
