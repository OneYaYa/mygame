class_name AIProvider
extends RefCounted

var provider_name: String = "unavailable"


func is_available() -> bool:
	return false


func request_decision(_payload: Dictionary) -> Dictionary:
	return {}

