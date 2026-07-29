class_name TimeEchoAIService
extends Node

var local_provider := LocalAIProvider.new()
var web_provider := WebAIProvider.new()
var http_provider: HttpAIProvider
var online_enabled: bool = true
var last_provider: String = "local-rules"


func _ready() -> void:
	var request_node := HTTPRequest.new()
	request_node.name = "NPCDecisionRequest"
	add_child(request_node)
	var endpoint: String = OS.get_environment("TIME_ECHO_AI_ENDPOINT").strip_edges()
	if endpoint.is_empty() and OS.has_feature("web"):
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		if typeof(origin) == TYPE_STRING:
			endpoint = str(origin).trim_suffix("/") + "/api/npc/decide"
	http_provider = HttpAIProvider.new(request_node, endpoint)


func talk(npc_id: String, message: String, state: Dictionary) -> Dictionary:
	var local_result: Dictionary = local_provider.talk(npc_id, message, state)
	if str(local_result.get("action", "continue_conversation")) != "continue_conversation":
		last_provider = "local-rules"
		return local_result
	if not online_enabled:
		last_provider = "local-rules"
		return local_result
	var payload: Dictionary = _build_payload(npc_id, message, state)
	var remote: Dictionary = {}
	if web_provider.is_available():
		remote = web_provider.request_decision(payload)
		last_provider = web_provider.provider_name
	elif http_provider != null and http_provider.is_available():
		remote = await http_provider.request_decision(payload)
		last_provider = http_provider.provider_name
	if remote.is_empty():
		last_provider = "local-rules"
		return local_result
	var reply: String = str(remote.get("reply", "")).strip_edges()
	var action: String = str(remote.get("action", "continue_conversation"))
	if reply.is_empty() or action != "continue_conversation":
		last_provider = "local-rules"
		return local_result
	return {
		"speaker": npc_id,
		"text": reply.left(4000),
		"action": "continue_conversation",
		"provider": str(remote.get("provider", last_provider)),
		"memory": str(remote.get("memory", reply)).left(1000),
		"puzzle": "",
	}


func _build_payload(npc_id: String, message: String, state: Dictionary) -> Dictionary:
	var npc: Dictionary = DataManager.get_npc(npc_id)
	var npc_state: Dictionary = (state.get("npcs", {}) as Dictionary).get(npc_id, {}) as Dictionary
	var public_facts: Array = ((npc.get("knowledge", {}) as Dictionary).get("public", []) as Array).duplicate(true)
	var notes: Array = ((state.get("npcNotes", {}) as Dictionary).get(npc_id, []) as Array)
	var recent_dialogue: Array = notes.slice(maxi(0, notes.size() - 8))
	return {
		"npc_profile": {
			"id": npc_id if npc_id != "ada" or bool((state.get("flags", {}) as Dictionary).get("ada_duty_anchored", false)) else "hidden_figure",
			"name": str(npc.get("name", "镇民")) if npc_id != "ada" or bool((state.get("flags", {}) as Dictionary).get("ada_name_anchored", false)) else "暗房中的潜影",
			"role": str(npc.get("role", "")),
			"goal": str(npc.get("goal", "")),
			"traits": npc.get("traits", []),
			"voice": str(npc.get("voice", "")),
			"concern": str(npc.get("concern", "")),
			"knowledge": {"public": public_facts},
			"allowedActions": [{"id": "continue_conversation", "label": "只继续对话，不改变世界状态"}],
		},
		"world_state": {
			"day": state.get("dayLabel", "SATURDAY"),
			"minute": state.get("minute", 360),
			"loop": int(state.get("loopCount", 0)) + 1,
			"story_context": {"public": DataManager.get_story_context().get("publicFacts", [])},
			"repairs": (state.get("repairs", {}) as Dictionary).duplicate(true),
			"flags": {},
			"recent_dialogue": recent_dialogue,
		},
		"player_message": message.left(2000),
		"memories": (npc_state.get("memories", []) as Array).slice(0, 8),
	}

