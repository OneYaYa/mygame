class_name LocalAIProvider
extends AIProvider


func _init() -> void:
	provider_name = "local-rules"


func is_available() -> bool:
	return true


func talk(npc_id: String, message: String, state: Dictionary) -> Dictionary:
	return DialogueManager.local_free_reply(npc_id, message, state)

