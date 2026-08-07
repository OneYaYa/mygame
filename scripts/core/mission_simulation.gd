class_name MissionSimulation
extends RefCounted

signal state_changed(state_snapshot: Dictionary)
signal mission_event(event: Dictionary)
signal confirmation_required(proposal: Dictionary)
signal mission_ended(outcome: String, state_snapshot: Dictionary)

const DEFAULT_MISSION_PATH: String = "res://data/mission.json"
const PowerPuzzle := preload("res://scripts/core/puzzles/power_routing_puzzle.gd")
const CoolantPuzzle := preload("res://scripts/core/puzzles/coolant_pressure_puzzle.gd")
const EXPECTED_ACTION_IDS: PackedStringArray = [
	"move", "inspect", "take", "drop", "connect", "toggle", "use", "wait"
]
const CABLE_TARGETS: PackedStringArray = PowerPuzzle.TARGETS
const VALVE_TARGETS: PackedStringArray = CoolantPuzzle.TARGETS

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
	var carried_item: String = str(_state.get("carried_item", ""))
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
		"carried_item": carried_item,
		"carried_item_name": _item_name(carried_item) if not carried_item.is_empty() else "无",
		"room_items": (room_items.get(room_id, []) as Array).duplicate(true),
		"guidance": _guidance_view(flags, room_id, carried_item, room_items),
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
			_append_action(actions, "connect", cable_id, "连接%s" % _target_label(cable_id), true, _npc_can_attempt_dangerous(), "林岚现在过于恐惧，先稳定通讯再让他接触带电线路。")

	if room_id == "coolant_gallery" and bool(flags.get("manifold_inspected", false)) and not bool(flags.get("valves_aligned", false)):
		for valve_id: String in VALVE_TARGETS:
			var vents_oxygen := CoolantPuzzle.is_vent(_state.get("scenario", {}) as Dictionary, valve_id)
			var active := bool((flags.get("valve_states", {}) as Dictionary).get(valve_id, false))
			var valve_label := "%s%s" % ["复位" if active else "接入", _target_label(valve_id)]
			_append_action(actions, "toggle", valve_id, valve_label, vents_oxygen and not active, _npc_can_attempt_dangerous() or not vents_oxygen or active, "林岚的呼吸已经乱了，无法安全执行排气调节。")

	if room_id == "power_bay" and carried_item == "phase_fuse" and bool(flags.get("phase_cable_connected", false)) and not bool(flags.get("grid_online", false)):
		_append_action(actions, "use", "phase_fuse", "安装相位保险芯")
	if room_id == "power_bay" and carried_item == "emergency_cell" and bool(flags.get("power_panel_inspected", false)) and not bool(flags.get("grid_online", false)):
		_append_action(actions, "use", "emergency_cell", "接入应急旁路电芯", true, _npc_can_attempt_dangerous(), "林岚现在无法稳定完成一次不可逆的旁路接线。")
	if room_id == "coolant_gallery" and carried_item == "sealant_kit" and bool(flags.get("valves_aligned", false)) and not bool(flags.get("leak_sealed", false)):
		_append_action(actions, "use", "sealant_kit", "使用低温密封剂")
	if carried_item == "oxygen_canister" and _resource("oxygen") < _max_resource("oxygen"):
		_append_action(actions, "use", "oxygen_canister", "使用便携氧气罐")
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
			"power_route": "uncommitted",
			"emergency_power": false,
			"manifold_inspected": false,
			"valve_states": {"valve_i": false, "valve_b": false, "valve_p": false},
			"coolant_pressure": int(scenario.get("coolant_start_pressure", 40)),
			"coolant_adjustments": 0,
			"valves_aligned": false,
			"leak_sealed": false,
			"escape_unlocked": false,
			"oxygen_boost_used": false,
			"focused_scan_ready": false,
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
			"conversation_since_cycle": 0,
			"communication_cycles": 0,
			"first_reassurance_free": true,
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
		local_state["coolant_pressure"] = int(flags.get("coolant_pressure", 0))
		local_state["valve_states"] = (flags.get("valve_states", {}) as Dictionary).duplicate(true)
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
	var advances_cycle := intent in ["conversation", "report", "clarify", "refuse", "reassure"]
	if intent == "reassure":
		trust += 5
		fear -= 8
		social["checkins"] = int(social.get("checkins", 0)) + 1
		var flags: Dictionary = _state.get("flags", {}) as Dictionary
		flags["focused_scan_ready"] = true
		_state["flags"] = flags
		if bool(social.get("first_reassurance_free", true)):
			advances_cycle = false
			social["first_reassurance_free"] = false
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
	if advances_cycle:
		social["conversation_since_cycle"] = int(social.get("conversation_since_cycle", 0)) + 1
		if int(social.get("conversation_since_cycle", 0)) >= 3:
			social["conversation_since_cycle"] = 0
			social["communication_cycles"] = int(social.get("communication_cycles", 0)) + 1
			var resources: Dictionary = _state.get("resources", {}) as Dictionary
			resources["oxygen"] = int(resources.get("oxygen", 0)) - 1
			_state["resources"] = resources
			var log: Array = _state.get("log", []) as Array
			log.append({
				"id": "comm:%d" % int(social.get("communication_cycles", 0)),
				"turn": int(_state.get("turn", 0)),
				"type": "communication",
				"text": "通讯持续占用呼吸调节器：氧气消耗 1%。",
			})
			_state["log"] = log
	social["trust"] = clampi(trust, 0, 100)
	social["fear"] = clampi(fear, 0, 100)
	social["last_player_line"] = player_text.left(120)
	social["last_npc_mood"] = mood
	_state["npc_social"] = social
	var beliefs: Dictionary = _state.get("npc_beliefs", {}) as Dictionary
	if compact.contains("Ω") or compact.contains("欧") or compact.contains("kPa") or compact.contains("千帕") or compact.contains("压力"):
		var claims: Array = beliefs.get("operator_claims", []) as Array
		claims.append(player_text.left(100))
		if claims.size() > 3:
			claims = claims.slice(claims.size() - 3)
		beliefs["operator_claims"] = claims
		beliefs["confidence"] = clampi(int(social.get("trust", 50)), 10, 90)
	_state["npc_beliefs"] = beliefs
	if _resource("oxygen") <= 0:
		var ending := _finish_failure("oxygen_depleted")
		var ending_log: Array = _state.get("log", []) as Array
		ending["turn"] = int(_state.get("turn", 0))
		ending_log.append(ending)
		_state["log"] = ending_log
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
			if not bool(available.get("enabled", true)):
				return {"ok": false, "reason": str(available.get("disabled_reason", "林岚现在无法安全执行该动作。"))}
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
	if action_id == "toggle" and CoolantPuzzle.is_vent(_state.get("scenario", {}) as Dictionary, target):
		return "该调节器会向舱外泄压并消耗氧气；请先核对目标压力，是否执行？"
	if action_id == "use" and target == "emergency_cell":
		return "旁路电芯会烧毁事故遥测并锁定为代价撤离路线，是否执行？"
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
		event["npc_line"] = "调度，我的呼吸器开始抢气了。"
	_apply_social_consequence(event)
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


func _apply_social_consequence(event: Dictionary) -> void:
	var social: Dictionary = _state.get("npc_social", {}) as Dictionary
	var trust := int(social.get("trust", 50))
	var fear := int(social.get("fear", 35))
	if bool(event.get("mistake", false)):
		trust -= 6
		fear += 12
	elif str(event.get("type", "")) == "puzzle_solved":
		trust += 2
		fear -= 6
	elif str(event.get("type", "")) == "resource":
		fear -= 5
	social["trust"] = clampi(trust, 0, 100)
	social["fear"] = clampi(fear, 0, 100)
	_state["npc_social"] = social


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
	if target in ["cable_panel", "valve_manifold"] and bool(flags.get("focused_scan_ready", false)):
		flags["focused_scan_ready"] = false
		var resources: Dictionary = _state.get("resources", {}) as Dictionary
		resources["oxygen"] = mini(_max_resource("oxygen"), int(resources.get("oxygen", 0)) + 1)
		_state["resources"] = resources
		text += " 林岚在稳定呼吸后完成了聚焦细扫，本次检查未额外消耗氧气。"
		if npc_line.is_empty():
			npc_line = "我把呼吸压稳了，刻度这次看得很清楚。你慢慢对，我保持这个位置。"
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
	var resolution: Dictionary = PowerPuzzle.resolve_connection(target, scenario)
	resources["power"] = int(resources.get("power", 0)) + int(resolution.get("power_delta", 0))
	resources["oxygen"] = int(resources.get("oxygen", 0)) + int(resolution.get("oxygen_delta", 0))
	if bool(resolution.get("success", false)):
		flags["phase_cable_connected"] = true
		flags["connected_cable"] = target
		flags["power_route"] = "phase_fuse"
		_state["flags"] = flags
		_state["resources"] = resources
		return (resolution.get("event", {}) as Dictionary).duplicate(true)
	_state["mistakes"] = int(_state.get("mistakes", 0)) + 1
	_state["resources"] = resources
	return (resolution.get("event", {}) as Dictionary).duplicate(true)


func _apply_toggle(target: String) -> Dictionary:
	var flags: Dictionary = _state.get("flags", {}) as Dictionary
	var resources: Dictionary = _state.get("resources", {}) as Dictionary
	var resolution := CoolantPuzzle.resolve_toggle(target, _state.get("scenario", {}) as Dictionary, flags)
	flags["valve_states"] = (resolution.get("states", {}) as Dictionary).duplicate(true)
	flags["coolant_pressure"] = int(resolution.get("pressure", flags.get("coolant_pressure", 0)))
	flags["coolant_adjustments"] = int(resolution.get("adjustments", 0))
	flags["valves_aligned"] = bool(resolution.get("aligned", false))
	resources["oxygen"] = int(resources.get("oxygen", 0)) + int(resolution.get("oxygen_delta", 0))
	if bool(resolution.get("mistake", false)):
		_state["mistakes"] = int(_state.get("mistakes", 0)) + 1
	_state["flags"] = flags
	_state["resources"] = resources
	return (resolution.get("event", {}) as Dictionary).duplicate(true)


func _apply_use(target: String) -> Dictionary:
	var flags: Dictionary = _state.get("flags", {}) as Dictionary
	var puzzles: Dictionary = _state.get("puzzles", {}) as Dictionary
	var resources: Dictionary = _state.get("resources", {}) as Dictionary
	if target == "phase_fuse":
		_state["carried_item"] = ""
		flags["grid_online"] = true
		flags["power_route"] = "phase_fuse"
		puzzles["power"] = "solved"
		resources["power"] = mini(_max_resource("power"), int(resources.get("power", 0)) + 20)
		_state["flags"] = flags
		_state["puzzles"] = puzzles
		_state["resources"] = resources
		_update_escape_lock()
		return {"type": "puzzle_solved", "text": "相位保险芯接通，主电网恢复。", "puzzle": "power"}
	if target == "emergency_cell":
		_state["carried_item"] = ""
		flags["grid_online"] = true
		flags["emergency_power"] = true
		flags["power_route"] = "emergency_bypass"
		puzzles["power"] = "bypassed"
		resources["power"] = mini(_max_resource("power"), int(resources.get("power", 0)) + 8)
		_state["flags"] = flags
		_state["puzzles"] = puzzles
		_state["resources"] = resources
		_update_escape_lock()
		return {
			"type": "puzzle_solved",
			"text": "应急电芯烧穿诊断缓存并建立临时母线。电网已恢复，但本轮只能获得代价撤离评价。",
			"puzzle": "power",
			"route": "emergency_bypass",
			"npc_line": "旁路线亮了，遥测屏也彻底黑了……至少门有电。我们得接受这个代价。",
		}
	if target == "oxygen_canister":
		_state["carried_item"] = ""
		flags["oxygen_boost_used"] = true
		resources["oxygen"] = mini(_max_resource("oxygen"), int(resources.get("oxygen", 0)) + 24)
		_state["flags"] = flags
		_state["resources"] = resources
		return {
			"type": "resource",
			"text": "便携氧气罐接入呼吸器，恢复 24% 个人供氧。",
			"npc_line": "供气稳下来了……这口气真像重新活了一次。好，继续。",
		}
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
			and not bool(flags.get("emergency_power", false)) \
			and _resource("oxygen") >= int(rules.get("success_oxygen_threshold", 50)) \
			and _resource("power") >= int(rules.get("success_power_threshold", 40))
		_state["outcome"] = "success" if clean_run else "costly_success"
		_state["ending_reason"] = "clean_extraction" if clean_run else "damaged_extraction"
		_state["is_terminal"] = true
		var social: Dictionary = _state.get("npc_social", {}) as Dictionary
		var trust := int(social.get("trust", 50))
		var relationship_line := "林岚在脱离后仍保持着通讯，并主动报出自己的生命体征。" if trust >= 60 else "林岚沉默地完成了脱离程序。" if trust < 35 else "林岚确认安全后关闭了中继。"
		var route_line := "应急旁路保存了他的生命，但事故诊断记录已被烧毁。" if bool(flags.get("emergency_power", false)) else "相位闭环与事故记录均被完整保留。"
		return {
			"type": "ending",
			"text": ("逃生舱平稳脱离 K-17。林岚与遥测记录均完整获救。" if clean_run else "逃生舱带伤脱离 K-17。林岚获救，但任务代价已经写入记录。") + route_line + relationship_line,
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


## Player-facing route guidance. It describes the next operation without exposing
## randomized puzzle answers, and is derived from the same authoritative state as
## valid_actions() so it cannot point at an impossible step.
func _guidance_view(flags: Dictionary, room_id: String, carried_item: String, room_items: Dictionary) -> Dictionary:
	if bool(_state.get("is_terminal", false)):
		return _guide("complete", "本轮任务已经结束。可使用右上角 RESTART 生成新的事故变体。", "", [])

	if not bool(flags.get("telemetry_inspected", false)):
		if room_id == "relay_control":
			return _guide(
				"restore_telemetry",
				"先取得调度端线索：让林岚检查中继控制室的遥测台。",
				"检查遥测台",
				["遥测台", "中继控制室"]
			)
		return _guide(
			"return_for_telemetry",
			"遥测数据还没恢复，后续无法判断接头和压力。先返回中继控制室检查遥测台。",
			"回到中继控制室",
			["中继控制室", "遥测台"]
		)

	if not bool(flags.get("grid_online", false)):
		match room_id:
			"relay_control":
				if carried_item == "phase_fuse":
					return _guide("carry_fuse", "保险芯已带上。先去中央交汇舱，再进入主电网舱。", "前往中央交汇舱", ["相位保险芯", "中央交汇舱", "主电网舱"])
				if carried_item.is_empty():
					return _guide("take_fuse", "完整修复路线需要相位保险芯；先拿起它，再前往中央交汇舱。", "拿起相位保险芯", ["相位保险芯", "中央交汇舱"])
				return _guide("free_slot_for_fuse", "林岚一次只能带一件。先放下或使用当前物品，再拿相位保险芯。", "放下%s" % _item_name(carried_item), [_item_name(carried_item), "相位保险芯"])
			"central_junction":
				if carried_item in ["phase_fuse", "emergency_cell"]:
					return _guide("enter_power_bay", "供电部件已经选好。现在进入主电网舱，先检查电缆面板。", "前往主电网舱", [_item_name(carried_item), "主电网舱", "电缆面板"])
				if carried_item.is_empty():
					return _guide(
						"choose_power_route",
						"两条供电路线：返回中继控制室拿相位保险芯可完整修复；或拿这里的应急旁路电芯快速恢复，但结局会付出代价。选好后去主电网舱。",
						"拿起应急旁路电芯",
						["相位保险芯", "应急旁路电芯", "中继控制室", "主电网舱"]
					)
				return _guide("free_slot_for_route", "唯一携带槽已被%s占用。先使用或放下它，再选择供电部件。" % _item_name(carried_item), "放下%s" % _item_name(carried_item), [_item_name(carried_item), "相位保险芯", "应急旁路电芯"])
			"power_bay":
				if not bool(flags.get("power_panel_inspected", false)):
					return _guide("inspect_power", "先让林岚检查电缆面板，取得三只接头的现场读数。", "检查电缆面板", ["电缆面板", "蓝色套管接头", "红色陶瓷接头", "黄色编织接头"])
				if carried_item == "emergency_cell":
					return _guide("use_bypass", "旁路路线已就绪。接入应急旁路电芯会立即恢复电网，但这是不可逆的代价选择。", "接入应急旁路电芯", ["应急旁路电芯"])
				if bool(flags.get("phase_cable_connected", false)):
					if carried_item == "phase_fuse":
						return _guide("install_fuse", "相位接头已经对齐。现在安装相位保险芯，恢复主电网。", "安装相位保险芯", ["相位保险芯"])
					return _guide("retrieve_fuse", "接头已经对齐，但林岚没有携带保险芯。返回中继控制室取回它。", "返回中央交汇舱", ["中央交汇舱", "中继控制室", "相位保险芯"])
				if carried_item == "phase_fuse":
					return _guide(
						"match_power_clues",
						"点击右侧一条 PWR-03 遥测和一条现场接头读数固定到工作台；找出阻值相同的接头，再明确下令连接。",
						"连接蓝色套管接头",
						["PWR-03", "蓝色套管接头", "红色陶瓷接头", "黄色编织接头"]
					)
				return _guide("retrieve_power_part", "电缆面板已检查，但缺少供电部件。经中央交汇舱返回中继控制室拿保险芯，或在中央舱拿旁路电芯。", "返回中央交汇舱", ["中央交汇舱", "相位保险芯", "应急旁路电芯"])
			_:
				return _guide("power_first", "逃生舱首先需要恢复电网。返回中央交汇舱，然后前往主电网舱。", "返回中央交汇舱", ["中央交汇舱", "主电网舱"])

	if not bool(flags.get("leak_sealed", false)):
		var sealant_room: String = _item_room_id(room_items, "sealant_kit")
		match room_id:
			"power_bay":
				if carried_item == "sealant_kit":
					return _guide("carry_sealant", "密封剂已带上。经中央交汇舱前往冷却回廊。", "返回中央交汇舱", ["低温密封剂", "中央交汇舱", "冷却回廊"])
				if carried_item.is_empty():
					if sealant_room == "power_bay":
						return _guide("take_sealant", "电网已恢复。拿起主电网舱里的低温密封剂，再去冷却回廊。", "拿起低温密封剂", ["低温密封剂", "冷却回廊"])
					return _guide("find_dropped_sealant", "低温密封剂留在%s。先经中央交汇舱取回它，再前往冷却回廊。" % _room_name(sealant_room), "返回中央交汇舱", [_room_name(sealant_room), "低温密封剂", "冷却回廊"])
				return _guide("free_slot_for_sealant", "下一阶段需要低温密封剂，它现在位于%s。先腾出唯一携带槽再去取回。" % _room_name(sealant_room), "放下%s" % _item_name(carried_item), [_item_name(carried_item), _room_name(sealant_room), "低温密封剂"])
			"central_junction":
				if carried_item == "sealant_kit":
					return _guide("enter_coolant", "低温密封剂已带上。现在进入冷却回廊，先检查冷却阀组。", "前往冷却回廊", ["低温密封剂", "冷却回廊", "冷却阀组"])
				if carried_item.is_empty() and sealant_room == "central_junction":
					return _guide("take_dropped_sealant", "低温密封剂就在中央交汇舱。先拿起它，再进入冷却回廊。", "拿起低温密封剂", ["低温密封剂", "冷却回廊"])
				if carried_item.is_empty():
					return _guide("retrieve_sealant", "冷却裂口需要低温密封剂，它现在位于%s。先去取回，再进入冷却回廊。" % _room_name(sealant_room), "前往%s" % _room_name(sealant_room), [_room_name(sealant_room), "低温密封剂", "冷却回廊"])
				return _guide("free_slot_for_sealant_route", "唯一携带槽已被%s占用。先放下或使用它，再去%s取低温密封剂。" % [_item_name(carried_item), _room_name(sealant_room)], "放下%s" % _item_name(carried_item), [_item_name(carried_item), _room_name(sealant_room), "低温密封剂"])
			"coolant_gallery":
				if not bool(flags.get("manifold_inspected", false)):
					return _guide("inspect_coolant", "先检查冷却阀组，读取 I、B、P 三只调节器的现场增减量。", "检查冷却阀组", ["冷却阀组", "I 阀", "B 阀", "P 阀"])
				if not bool(flags.get("valves_aligned", false)):
					return _guide(
						"match_coolant_clues",
						"点击右侧 CLT-04 目标压力和现场阀组读数固定到工作台；从当前压力组合增减量，明确下令接入或复位 I/B/P 阀。",
						"接入 I 阀",
						["CLT-04", "I 阀", "B 阀", "P 阀"]
					)
				if carried_item == "sealant_kit":
					return _guide("seal_leak", "压力已经稳定。使用低温密封剂封住裂口，解除第二道联锁。", "使用低温密封剂", ["低温密封剂"])
				if carried_item.is_empty() and sealant_room == "coolant_gallery":
					return _guide("take_local_sealant", "压力已经稳定，低温密封剂就在这里。先拿起它，再封住裂口。", "拿起低温密封剂", ["低温密封剂"])
				return _guide("retrieve_missing_sealant", "压力已经稳定，但缺少密封剂。它现在位于%s，先经中央交汇舱取回。" % _room_name(sealant_room), "返回中央交汇舱", ["中央交汇舱", _room_name(sealant_room), "低温密封剂"])
			_:
				return _guide("coolant_next", "电网已经恢复。经中央交汇舱前往冷却回廊，稳定压力并密封裂口。", "前往中央交汇舱", ["中央交汇舱", "冷却回廊", "低温密封剂"])

	if room_id == "escape_pod":
		return _guide("launch", "两道联锁均已解除。启动逃生舱即可完成撤离。", "启动逃生舱", ["发射控制器", "逃生舱"])
	if room_id == "central_junction":
		return _guide("enter_escape", "两道联锁均已解除。现在前往逃生舱。", "前往逃生舱", ["逃生舱"])
	return _guide("return_to_escape", "两道联锁均已解除。先返回中央交汇舱，再进入逃生舱。", "返回中央交汇舱", ["中央交汇舱", "逃生舱"])


func _guide(stage: String, instruction: String, example_command: String, keywords: Array) -> Dictionary:
	return {
		"stage": stage,
		"instruction": instruction,
		"example_command": example_command,
		"keywords": keywords.duplicate(),
	}


func _room_contains_item(room_items: Dictionary, room_id: String, item_id: String) -> bool:
	return item_id in (room_items.get(room_id, []) as Array)


func _item_room_id(room_items: Dictionary, item_id: String) -> String:
	for room_id_variant: Variant in room_items:
		var room_id: String = str(room_id_variant)
		if _room_contains_item(room_items, room_id, item_id):
			return room_id
	return "power_bay"


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


func _append_action(actions: Array[Dictionary], action_id: String, target: String, label: String, dangerous: bool = false, enabled: bool = true, disabled_reason: String = "") -> void:
	actions.append({
		"id": action_id,
		"target": target,
		"label": label,
		"dangerous": dangerous,
		"enabled": enabled,
		"disabled_reason": disabled_reason,
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
		"本轮事故签名：%s。重开任务会生成新的线路读数与压力标定。" % str((_state.get("scenario", {}) as Dictionary).get("id", "UNKNOWN")),
		"ESC-05 联锁：主电网握手缺失；冷却压差不稳定。",
	]
	if not bool(flags.get("telemetry_inspected", false)):
		telemetry.append("诊断缓存尚未解码。需要在 RLY-01 执行一次遥测深扫。")
		return telemetry
	var scenario: Dictionary = _state.get("scenario", {}) as Dictionary
	var required_reading := str(scenario.get("required_reading", "未知"))
	if bool(flags.get("grid_online", false)):
		telemetry.append("PWR-03：%s。" % ("应急旁路供电；事故缓存已损坏" if bool(flags.get("emergency_power", false)) else "启动闭环稳定，保险芯在线"))
	elif bool(flags.get("phase_cable_connected", false)):
		telemetry.append("PWR-03：%s 启动闭环已锁定；控制器等待保险芯。" % required_reading)
	else:
		telemetry.append("PWR-03 启动记录：本轮控制器需要 %s 闭环返回；必须与现场三只接头的读数交叉核对。" % required_reading)
	var current_pressure := int(flags.get("coolant_pressure", scenario.get("coolant_start_pressure", 0)))
	var target_pressure := int(scenario.get("coolant_target_pressure", 0))
	if bool(flags.get("leak_sealed", false)):
		telemetry.append("CLT-04：压差恢复，裂口监测稳定。")
	elif bool(flags.get("valves_aligned", false)):
		telemetry.append("CLT-04：%d kPa 目标窗口已锁定；维护口处裂口已暴露。" % target_pressure)
	else:
		telemetry.append("CLT-04 压力模型：当前 %d kPa；必须调节到 %d kPa。现场三只调节器的增减量只能由林岚读取。" % [current_pressure, target_pressure])
	return telemetry


func _build_scenario() -> Dictionary:
	var scenario := PowerPuzzle.build_scenario(_variant_rng)
	scenario.merge(CoolantPuzzle.build_scenario(_variant_rng), true)
	scenario["id"] = "K17-%04d" % int(abs(_variant_rng.randi()) % 10000)
	return scenario


func _current_observation_summary(room_id: String, flags: Dictionary) -> String:
	var base := str(_room(room_id).get("observation", ""))
	var room_items: Dictionary = _state.get("room_items", {}) as Dictionary
	var items_here: Array = room_items.get(room_id, []) as Array
	if not items_here.is_empty():
		var item_names: Array[String] = []
		for value: Variant in items_here:
			item_names.append(_item_name(str(value)))
		base += "\n可见物资：%s。" % "、".join(item_names)
	if room_id == "power_bay" and bool(flags.get("power_panel_inspected", false)):
		return "%s\n已确认现场读数：%s" % [base, _cable_detail_text()]
	if room_id == "coolant_gallery" and bool(flags.get("manifold_inspected", false)):
		return "%s\n已确认管路：%s" % [base, _valve_detail_text()]
	return base


func _cable_detail_text() -> String:
	return PowerPuzzle.detail_text(_state.get("scenario", {}) as Dictionary)


func _valve_detail_text() -> String:
	return CoolantPuzzle.detail_text(_state.get("scenario", {}) as Dictionary)


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
	if int(flags.get("coolant_adjustments", 0)) > 0:
		facts.append("冷却回路当前为 %d kPa，已经执行 %d 次调节。" % [int(flags.get("coolant_pressure", 0)), int(flags.get("coolant_adjustments", 0))])
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


func _npc_can_attempt_dangerous() -> bool:
	var social: Dictionary = _state.get("npc_social", {}) as Dictionary
	return int(social.get("fear", 35)) < 70 and int(social.get("trust", 50)) >= 25


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
	var flags: Dictionary = _state.get("flags", {}) as Dictionary
	var route := str(flags.get("power_route", "uncommitted"))
	var body := "林岚与事故遥测完整获救。" if outcome == "success" else "林岚获救，但设施损失被记录在案。" if outcome == "costly_success" else str(_state.get("ending_reason", "任务失败"))
	return {
		"title": title,
		"body": body,
		"relationship": relationship,
		"trust": trust,
		"checkins": int(social.get("checkins", 0)),
		"mistakes": int(_state.get("mistakes", 0)),
		"power_route": route,
		"oxygen_boost_used": bool(flags.get("oxygen_boost_used", false)),
		"communication_cycles": int(social.get("communication_cycles", 0)),
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
