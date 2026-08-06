class_name NpcContextCompiler
extends RefCounted


const TEMPLATE_VERSION := "blindspot-context-v2"
const MAX_HISTORY_ITEMS := 10
const MAX_BELIEF_ITEMS := 12
const MAX_MEMORY_ITEMS := 6

const LOCAL_STATE_KEYS: Array[String] = [
	"room_id", "room_name", "observation", "visible_items", "carried_item",
	"oxygen", "stress", "physical_state", "trust", "fear", "known_facts",
	"beliefs", "panel_inspected", "panel_details", "phase_cable_connected",
	"grid_online", "manifold_inspected", "manifold_details", "coolant_pressure",
	"valve_states", "valves_aligned", "leak_sealed",
]


## Compile one immutable, least-privilege NPC view. The simulation remains the
## authority; this object only decides which already-safe facts enter each prompt
## partition and records why they were included or dropped.
func compile(
	raw_context: Dictionary,
	public_snapshot: Dictionary,
	actions: Array[Dictionary],
	history: Array[Dictionary],
	memory: Dictionary,
	player_text: String
) -> Dictionary:
	var raw_local: Dictionary = _dictionary(raw_context.get("local_state", raw_context.get("state", {})))
	var local_state := _pick_local_state(raw_local, public_snapshot)
	var npc: Dictionary = _dictionary(raw_context.get("npc", public_snapshot.get("npc", {}))).duplicate(true)
	var observation := _compile_observation(raw_context, local_state)
	var clean_actions := _compile_actions(actions)
	var recent_dialogue := _compile_history(history)
	var known_beliefs := _compile_beliefs(local_state)
	var relevant_memories := _compile_memories(memory)
	var relationship := {
		"trust": clampi(int(local_state.get("trust", 50)), 0, 100),
		"fear": clampi(int(local_state.get("fear", 35)), 0, 100),
		"source": "authoritative_simulation",
	}
	var scene_mode := _scene_mode(local_state)
	var snapshot_version := int(public_snapshot.get("turn", 0))
	var turn_id := "mission:%s:dialogue:%d" % [
		str(public_snapshot.get("scenario_id", "unknown")),
		int(public_snapshot.get("npc_social", {}).get("communication_cycles", 0)) + history.size() + 1,
	]
	var protocol := {
		"protocol_version": 2,
		"turn_id": turn_id,
		"snapshot_version": snapshot_version,
		"system_contract": {
			"authority": "The simulation owns facts and mutations; the NPC may only perform and propose.",
			"unknown_policy": "Admit uncertainty, ask one grounded question, and never infer a puzzle answer.",
			"mutation_policy": "Only propose an exact available action; never claim it already happened.",
		},
		"character_core": {
			"id": str(npc.get("id", "lin_lan")),
			"name": str(npc.get("name", "林岚")),
			"role": str(npc.get("role", "维护技术员")),
			"long_term_goal": "活着离开设施，并让每一步维修都有现场或远端证据。",
			"default_strategy": "先报告亲眼所见，再区分调度员说法与已确认事实。",
			"voice": "受伤、克制、具体；先回应，再补一个当下感官或动作细节。",
			"stable_boundaries": ["不替调度员猜谜题", "不把转述当作客观事实", "不宣称候选动作已经执行"],
		},
		"active_scene_mode": scene_mode,
		"current_scene": {
			"room_id": str(local_state.get("room_id", "")),
			"room_name": str(local_state.get("room_name", "未知舱段")),
			"local_observation": str(local_state.get("observation", "")),
			"physical_state": str(local_state.get("physical_state", "")),
			"oxygen": int(local_state.get("oxygen", 0)),
			"visible_observations": observation.get("visible", []),
		},
		"known_beliefs": known_beliefs,
		"relevant_memories": relevant_memories,
		"relationship_state": relationship,
		"director_intent": _director_intent(local_state, player_text),
		"recent_dialogue": recent_dialogue,
		"valid_actions": clean_actions,
	}
	var partitions := {
		"character_core": _estimate_tokens(protocol.get("character_core", {})),
		"current_scene": _estimate_tokens(protocol.get("current_scene", {})),
		"known_beliefs": _estimate_tokens(known_beliefs),
		"relevant_memories": _estimate_tokens(relevant_memories),
		"recent_dialogue": _estimate_tokens(recent_dialogue),
		"director_intent": _estimate_tokens(protocol.get("director_intent", {})),
	}
	var included_ids: Array[String] = []
	for belief: Dictionary in known_beliefs:
		included_ids.append(str(belief.get("belief_id", "")))
	for memory_item: Dictionary in relevant_memories:
		included_ids.append(str(memory_item.get("memory_id", "")))
	var dropped: Array[Dictionary] = []
	if history.size() > recent_dialogue.size():
		dropped.append({"partition": "recent_dialogue", "reason": "quota", "count": history.size() - recent_dialogue.size()})
	var prompt_trace := {
		"trace_id": turn_id,
		"template_version": TEMPLATE_VERSION,
		"snapshot_version": snapshot_version,
		"included_ids": included_ids,
		"dropped": dropped,
		"partition_token_estimates": partitions,
		"hard_filters": ["npc_local_scope", "current_room", "current_mission", "enabled_actions_only"],
	}
	return {
		"mission": _dictionary(raw_context.get("mission", {})).duplicate(true),
		"npc": npc,
		"local_state": local_state,
		"state": local_state.duplicate(true),
		"snapshot": local_state.duplicate(true),
		"observation": observation,
		"visible_observations": observation.get("visible", []),
		"available_actions": clean_actions,
		"actions": clean_actions.duplicate(true),
		"history": recent_dialogue,
		"conversation_memory": memory.duplicate(true),
		"context_protocol": protocol,
		"prompt_trace": prompt_trace,
	}


func _pick_local_state(raw_local: Dictionary, public_snapshot: Dictionary) -> Dictionary:
	var clean: Dictionary = {}
	for key: String in LOCAL_STATE_KEYS:
		if raw_local.has(key):
			clean[key] = _copy_value(raw_local[key])
	if clean.is_empty():
		for key: String in ["room_id", "room_name", "carried_item"]:
			if public_snapshot.has(key):
				clean[key] = _copy_value(public_snapshot[key])
		var resources: Dictionary = _dictionary(public_snapshot.get("resources", {}))
		clean["oxygen"] = int(resources.get("oxygen", 0))
		clean["observation"] = str(public_snapshot.get("observation_summary", "等待局部观察。"))
		clean["visible_items"] = _array(public_snapshot.get("room_items", [])).duplicate(true)
	return clean


func _compile_observation(raw_context: Dictionary, local_state: Dictionary) -> Dictionary:
	var source: Dictionary = _dictionary(raw_context.get("observation", {}))
	var visible: Array = []
	for value: Variant in _array(source.get("visible", raw_context.get("visible_observations", []))):
		if value is Dictionary:
			var item: Dictionary = value as Dictionary
			var text := str(item.get("text", item.get("label", item.get("id", "")))).strip_edges().left(240)
			if not text.is_empty():
				visible.append(text)
		else:
			var text := str(value).strip_edges().left(240)
			if not text.is_empty():
				visible.append(text)
	if visible.is_empty():
		var summary := str(local_state.get("observation", "")).strip_edges()
		if not summary.is_empty():
			visible.append(summary.left(240))
	for value: Variant in _array(local_state.get("visible_items", [])):
		var item_text := str(value).strip_edges().left(120)
		if not item_text.is_empty() and item_text not in visible:
			visible.append(item_text)
	return {
		"room_id": str(local_state.get("room_id", "")),
		"room_name": str(local_state.get("room_name", "未知舱段")),
		"summary": str(source.get("summary", local_state.get("observation", "等待局部观察。"))).left(400),
		"visible": visible.slice(0, mini(20, visible.size())),
		"hazards": _array(source.get("hazards", [])).slice(0, 8),
	}


func _compile_actions(actions: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action: Dictionary in actions:
		if not bool(action.get("enabled", true)):
			continue
		result.append({
			"action": str(action.get("action", action.get("id", ""))).left(80),
			"target": str(action.get("target", "")).left(80),
			"label": str(action.get("label", "")).left(120),
			"dangerous": bool(action.get("dangerous", action.get("requires_confirmation", false))),
			"enabled": true,
		})
	return result.slice(0, mini(30, result.size()))


func _compile_history(history: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in history.slice(maxi(0, history.size() - MAX_HISTORY_ITEMS)):
		if not value is Dictionary:
			continue
		var entry: Dictionary = value as Dictionary
		var role := str(entry.get("role", ""))
		var content := str(entry.get("content", entry.get("text", ""))).strip_edges().left(240)
		if role in ["player", "npc"] and not content.is_empty():
			result.append({"role": role, "content": content})
	return result


func _compile_beliefs(local_state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var beliefs: Dictionary = _dictionary(local_state.get("beliefs", {}))
	var index := 0
	for value: Variant in _array(beliefs.get("confirmed_local", [])):
		result.append({
			"belief_id": "local:%d" % index,
			"content": str(value).left(240),
			"truth_status": "confirmed_local",
			"confidence": 1.0,
			"source": "direct_observation",
		})
		index += 1
	for value: Variant in _array(local_state.get("known_facts", [])):
		result.append({
			"belief_id": "known:%d" % index,
			"content": str(value).left(240),
			"truth_status": "confirmed_local",
			"confidence": 1.0,
			"source": "local_state_projection",
		})
		index += 1
	var claim_confidence := clampf(float(beliefs.get("confidence", local_state.get("trust", 50))) / 100.0, 0.1, 0.9)
	var claim_index := 0
	for value: Variant in _array(beliefs.get("operator_claims", [])):
		result.append({
			"belief_id": "operator_claim:%d" % claim_index,
			"content": str(value).left(200),
			"truth_status": "unverified_claim",
			"confidence": claim_confidence,
			"source": "operator_statement",
		})
		claim_index += 1
	return result.slice(0, mini(MAX_BELIEF_ITEMS, result.size()))


func _compile_memories(memory: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var player_name := str(memory.get("player_name", "")).strip_edges().left(32)
	if not player_name.is_empty():
		result.append({
			"memory_id": "memory:player_name",
			"subjective_text": "调度员自称%s。" % player_name,
			"event_ref": "conversation:self_identification",
			"tier": "working",
			"salience": 0.8,
		})
	var promise_index := 0
	for value: Variant in _array(memory.get("promises", [])):
		result.append({
			"memory_id": "memory:promise:%d" % promise_index,
			"subjective_text": str(value).left(120),
			"event_ref": "conversation:operator_promise",
			"tier": "working",
			"salience": 0.65,
		})
		promise_index += 1
	return result.slice(0, mini(MAX_MEMORY_ITEMS, result.size()))


func _scene_mode(local_state: Dictionary) -> Dictionary:
	var oxygen := int(local_state.get("oxygen", 100))
	var fear := int(local_state.get("fear", 35))
	if oxygen <= 20:
		return {
			"id": "hypoxic_emergency", "trigger": "oxygen<=20", "energy": "failing",
			"emotion": "afraid", "behavior_rules": ["短句", "先报告呼吸和手边风险", "不做多目标猜测"],
		}
	if fear >= 70:
		return {
			"id": "panic_containment", "trigger": "fear>=70", "energy": "shaky",
			"emotion": "afraid", "behavior_rules": ["承认手抖或停顿", "要求一次只确认一件事", "危险动作必须等待授权"],
		}
	return {
		"id": "field_maintenance", "trigger": "default", "energy": "strained",
		"emotion": str(local_state.get("stress", "focused")), "behavior_rules": ["先回应玩家", "只说局部所见", "清楚区分观察与转述"],
	}


func _director_intent(local_state: Dictionary, player_text: String) -> Dictionary:
	var oxygen := int(local_state.get("oxygen", 100))
	var fear := int(local_state.get("fear", 35))
	var goal := "回答调度员当前问题，并在不知道时请求一个可核对的信息。"
	var urgency := "guidance"
	var priority := 30
	var preconditions: Array[String] = ["mission_active"]
	if oxygen <= 25:
		goal = "优先让调度员理解低氧正在收紧选择，但不替其决定路线。"
		urgency = "emergency"
		priority = 100
		preconditions = ["oxygen<=25"]
	elif fear >= 70:
		goal = "把交流收束到一个明确、可确认的下一步，避免恐慌性误操作。"
		urgency = "urgent"
		priority = 80
		preconditions = ["fear>=70"]
	return {
		"goal": goal,
		"urgency": urgency,
		"priority": priority,
		"preconditions": preconditions,
		"forbidden_moves": ["泄露谜题答案", "替玩家选择多目标动作", "声称候选动作已经完成"],
		"ttl_turns": 1,
		"max_mentions": 1,
		"cooldown_turns": 1 if player_text.length() > 0 else 0,
	}


func _estimate_tokens(value: Variant) -> int:
	return ceili(float(JSON.stringify(value).length()) / 3.0)


func _copy_value(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value


func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value as Array if value is Array else []
