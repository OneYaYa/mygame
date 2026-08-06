class_name NpcDecisionService
extends Node


signal decision_ready(decision: Dictionary)
signal status_changed(status: String, detail: String)


const LocalProvider := preload("res://scripts/services/local_npc_provider.gd")

@export var endpoint := "http://127.0.0.1:8787/api/npc/decide"
@export_range(2.0, 45.0, 0.5) var request_timeout_seconds := 32.0
@export var online_enabled := true

var _http: HTTPRequest
var _local := LocalProvider.new()
var _context: Dictionary = {}
var _player_text := ""
var _busy := false
var _consecutive_failures := 0
var _circuit_open_until_msec := 0
var _trace_history: Array[Dictionary] = []


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "NpcDecisionHttp"
	_http.timeout = request_timeout_seconds
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	status_changed.emit("local_ready", "在线服务未探测；故障时自动使用本地规则")


func request_decision(context: Dictionary, player_text: String) -> void:
	var clean := player_text.strip_edges().left(400)
	if clean.is_empty():
		return
	if _busy:
		var queued_local := _sanitize_decision(_local.decide(context, clean), context, "local_busy_fallback")
		_record_trace(context, queued_local, "busy_fallback")
		decision_ready.emit(queued_local)
		return
	if not online_enabled or Time.get_ticks_msec() < _circuit_open_until_msec:
		var provider := "local_forced" if not online_enabled else "local_circuit_breaker"
		var local_decision := _sanitize_decision(_local.decide(context, clean), context, provider)
		_record_trace(context, local_decision, provider)
		status_changed.emit("local", "已固定使用本地规则" if not online_enabled else "远端链路暂时熔断；本轮使用本地规则")
		decision_ready.emit(local_decision)
		return

	_context = context.duplicate(true)
	_player_text = clean
	_busy = true
	var payload := _build_payload(_context, clean)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
	])
	status_changed.emit("connecting", "信号远程传输中……")
	var error := _http.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		_fallback("HTTP 请求无法启动（%s）" % error_string(error))


func cancel_pending() -> void:
	if not _busy:
		return
	_http.cancel_request()
	_busy = false
	_context.clear()
	_player_text = ""
	status_changed.emit("cancelled", "已取消等待中的 NPC 请求")


func is_busy() -> bool:
	return _busy


func set_online_enabled(enabled: bool) -> void:
	online_enabled = enabled
	if not enabled:
		cancel_pending()
	status_changed.emit("local" if not enabled else "local_ready", "本地规则模式" if not enabled else "在线增强已启用；失败时自动降级")


func _build_payload(context: Dictionary, player_text: String) -> Dictionary:
	var npc: Dictionary = _dictionary(context.get("npc", {}))
	var observation: Dictionary = _dictionary(context.get("observation", {}))
	var state: Dictionary = _dictionary(context.get("state", context.get("snapshot", {})))
	var actions: Array = _array(context.get("available_actions", context.get("actions", [])))
	var visible_observations: Array = _array(context.get("visible_observations", observation.get("visible", observation.get("objects", []))))
	var valid_actions: Array[Dictionary] = []
	for value: Variant in actions:
		if not value is Dictionary:
			continue
		var action := value as Dictionary
		valid_actions.append({
			"action": str(action.get("action", action.get("id", action.get("action_id", "")))),
			"target": str(action.get("target", "")),
			"label": str(action.get("label", action.get("action", action.get("id", "")))),
			"dangerous": bool(action.get("dangerous", action.get("requires_confirmation", false))),
			"enabled": bool(action.get("enabled", true)),
		})
	return {
		"message": player_text,
		"player_text": player_text,
		"npc": npc,
		"observation": observation,
		"state": state,
		"visible_observations": visible_observations,
		"valid_actions": valid_actions,
		"history": _history(context),
		"conversation_memory": _dictionary(context.get("conversation_memory", {})).duplicate(true),
		"context_protocol": _dictionary(context.get("context_protocol", {})).duplicate(true),
		"prompt_trace": _dictionary(context.get("prompt_trace", {})).duplicate(true),
		"available_actions": actions,
		"client": {
			"name": "blindspot-relay-godot",
			"protocol": 2,
			"candidate_only": true,
		},
	}


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _busy:
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_fallback("网络失败（result=%d）" % result)
		return
	if response_code < 200 or response_code >= 300:
		_fallback("服务返回 HTTP %d" % response_code)
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		_fallback("服务响应不是 JSON 对象")
		return
	var raw := _unwrap_response(parsed as Dictionary)
	if raw.is_empty() or str(raw.get("reply", "")).strip_edges().is_empty():
		_fallback("服务响应缺少 reply")
		return
	var decision := _sanitize_decision(raw, _context, "http")
	_record_trace(_context, decision, "online")
	_busy = false
	_consecutive_failures = 0
	_circuit_open_until_msec = 0
	_context.clear()
	_player_text = ""
	status_changed.emit("online", "远端回复已接收；动作仍等待本地确认")
	decision_ready.emit(decision)


func _unwrap_response(response: Dictionary) -> Dictionary:
	for key: String in ["decision", "data", "result", "output"]:
		var nested: Variant = response.get(key)
		if nested is Dictionary and (nested as Dictionary).has("reply"):
			var decision := (nested as Dictionary).duplicate(true)
			decision["provider"] = str(response.get("provider", decision.get("provider", "http")))
			decision["model"] = str(response.get("model", ""))
			decision["prompt_trace"] = _dictionary(response.get("trace", decision.get("prompt_trace", {}))).duplicate(true)
			return decision
	return response.duplicate(true)


func _history(context: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source: Array = _array(context.get("history", context.get("recent_events", [])))
	for value: Variant in source.slice(maxi(0, source.size() - 12)):
		if value is Dictionary:
			var entry := value as Dictionary
			var content := str(entry.get("content", entry.get("text", entry.get("message", "")))).left(240)
			if not content.is_empty():
				result.append({"role": str(entry.get("role", "system")), "content": content})
		elif not str(value).is_empty():
			result.append({"role": "system", "content": str(value).left(240)})
	return result


func _fallback(reason: String) -> void:
	if not _busy:
		return
	var context := _context.duplicate(true)
	var message := _player_text
	_busy = false
	_context.clear()
	_player_text = ""
	var decision := _sanitize_decision(_local.decide(context, message), context, "local_fallback")
	decision["fallback_reason"] = reason
	_record_trace(context, decision, "local_fallback")
	_consecutive_failures += 1
	if _consecutive_failures >= 2:
		_circuit_open_until_msec = Time.get_ticks_msec() + 30000
	status_changed.emit("local", "%s；已切换本地规则%s" % [reason, "，远端暂停 30 秒" if _consecutive_failures >= 2 else ""])
	decision_ready.emit(decision)


func _sanitize_decision(raw: Dictionary, context: Dictionary, provider: String) -> Dictionary:
	var reply := str(raw.get("reply", "")).strip_edges().left(1200)
	var intent := str(raw.get("intent", "conversation")).strip_edges().left(80)
	var mood := str(raw.get("mood", "focused")).strip_edges().left(40)
	var requested_action := str(raw.get("action", raw.get("action_id", ""))).strip_edges().left(80)
	var requested_target := str(raw.get("target", "")).strip_edges().left(80)
	var candidate := _allowed_candidate(requested_action, requested_target, context)
	var referenced_ids: Array[String] = []
	for value: Variant in _array(raw.get("referenced_ids", [])):
		var reference := str(value).strip_edges().left(100)
		if not reference.is_empty() and reference not in referenced_ids:
			referenced_ids.append(reference)
	return {
		"reply": reply if not reply.is_empty() else "通讯中断。我保持原位，等待你的下一条指令。",
		"intent": intent if not intent.is_empty() else "conversation",
		"action": str(candidate.get("id", "")),
		"target": str(candidate.get("target", "")),
		"mood": mood if not mood.is_empty() else "focused",
		"provider": str(raw.get("provider", provider)),
		"referenced_ids": referenced_ids.slice(0, mini(12, referenced_ids.size())),
		"quality_guard": str(raw.get("quality_guard", "")).strip_edges().left(120),
		"prompt_trace": _dictionary(raw.get("prompt_trace", context.get("prompt_trace", {}))).duplicate(true),
		"candidate_valid": not candidate.is_empty(),
		"candidate_only": true,
	}


func _allowed_candidate(action_id: String, target: String, context: Dictionary) -> Dictionary:
	if action_id.is_empty() or action_id in ["none", "null", "talk", "conversation"]:
		return {}
	var actions: Array = _array(context.get("available_actions", context.get("actions", [])))
	var matches: Array[Dictionary] = []
	for value: Variant in actions:
		if not value is Dictionary:
			continue
		var action := value as Dictionary
		var allowed_id := str(action.get("action", action.get("id", action.get("action_id", ""))))
		if allowed_id != action_id or not bool(action.get("enabled", true)):
			continue
		var allowed_target := str(action.get("target", target))
		if not target.is_empty():
			if target == allowed_target:
				return {"id": allowed_id, "target": allowed_target}
			continue
		matches.append({"id": allowed_id, "target": allowed_target})
	# Targetless outputs are accepted only when the action is truly unambiguous.
	# This prevents an empty model target from silently selecting the first cable
	# or pressure regulator in the local whitelist.
	if matches.size() == 1:
		return matches[0]
	return {}


func get_trace_history() -> Array[Dictionary]:
	return _trace_history.duplicate(true)


func _record_trace(context: Dictionary, decision: Dictionary, outcome: String) -> void:
	var entry := _dictionary(context.get("prompt_trace", {})).duplicate(true)
	var remote_trace := _dictionary(decision.get("prompt_trace", {}))
	entry.merge(remote_trace, true)
	entry["provider"] = str(decision.get("provider", "local"))
	entry["selected_action"] = str(decision.get("action", ""))
	entry["selected_target"] = str(decision.get("target", ""))
	entry["referenced_ids"] = _array(decision.get("referenced_ids", [])).duplicate(true)
	entry["quality_guard"] = str(decision.get("quality_guard", ""))
	entry["outcome"] = outcome
	_trace_history.append(entry)
	if _trace_history.size() > 64:
		_trace_history = _trace_history.slice(_trace_history.size() - 64)


func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value as Array if value is Array else []
