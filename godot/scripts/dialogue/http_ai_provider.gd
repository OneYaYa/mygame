class_name HttpAIProvider
extends AIProvider

var endpoint: String = ""
var timeout_seconds: float = 12.0
var _request: HTTPRequest


func _init(request_node: HTTPRequest, configured_endpoint: String) -> void:
	provider_name = "http-backend"
	_request = request_node
	endpoint = configured_endpoint
	_request.timeout = timeout_seconds


func is_available() -> bool:
	return _request != null and not endpoint.is_empty()


func request_decision(payload: Dictionary) -> Dictionary:
	if not is_available():
		return {}
	var headers: PackedStringArray = ["Accept: application/json", "Content-Type: application/json"]
	var error: Error = _request.request(endpoint, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if error != OK:
		return {}
	var completed: Array = await _request.request_completed
	if completed.size() < 4 or int(completed[0]) != HTTPRequest.RESULT_SUCCESS:
		return {}
	var status_code: int = int(completed[1])
	if status_code < 200 or status_code >= 300:
		return {}
	var body: PackedByteArray = completed[3] as PackedByteArray
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var envelope: Dictionary = parsed as Dictionary
	var decision: Variant = envelope.get("decision", envelope)
	if typeof(decision) != TYPE_DICTIONARY:
		return {}
	return decision as Dictionary

