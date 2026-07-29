class_name BrowserBridge
extends RefCounted


static func is_web() -> bool:
	return OS.has_feature("web")


static func browser_origin() -> String:
	if not is_web():
		return ""
	var value: Variant = JavaScriptBridge.eval("window.location.origin", true)
	return str(value) if typeof(value) == TYPE_STRING else ""


static func legacy_local_storage_save_key() -> String:
	# Read-only compatibility aid for a hosting page that deliberately exposes
	# the old save. Desktop and normal Web builds use user:// JSON exclusively.
	if not is_web():
		return ""
	var value: Variant = JavaScriptBridge.eval("localStorage.getItem('time-echo-save-v1') || ''", true)
	return str(value) if typeof(value) == TYPE_STRING else ""
