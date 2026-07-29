class_name WebAIProvider
extends AIProvider


func _init() -> void:
	provider_name = "javascript-bridge"


func is_available() -> bool:
	if not OS.has_feature("web"):
		return false
	var available: Variant = JavaScriptBridge.eval("typeof window.TIME_ECHO_GODOT_AI === 'function'", true)
	return bool(available)


func request_decision(payload: Dictionary) -> Dictionary:
	if not is_available():
		return {}
	# Optional browser hook. It must synchronously return a JSON string; secrets
	# remain in the hosting page/server and never enter the exported PCK.
	var encoded: String = Marshalls.utf8_to_base64(JSON.stringify(payload))
	var expression: String = "window.TIME_ECHO_GODOT_AI(JSON.parse(new TextDecoder().decode(Uint8Array.from(atob('%s'),c=>c.charCodeAt(0)))))" % encoded
	var result: Variant = JavaScriptBridge.eval(expression, true)
	if typeof(result) != TYPE_STRING:
		return {}
	var parsed: Variant = JSON.parse_string(result as String)
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}
