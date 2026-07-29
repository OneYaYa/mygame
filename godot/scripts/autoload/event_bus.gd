extends Node

signal data_loaded()
signal state_changed(state: Dictionary)
signal scene_change_requested(place_id: String)
signal scene_changed(scene: Dictionary)
signal interaction_changed(target: Dictionary)
signal inventory_changed(inventory: Dictionary)
signal knowledge_changed(knowledge: Dictionary)
signal clock_changed(day_label: String, minute: int, loop_count: int)
signal loop_warning(loop_count: int)
signal loop_reset(loop_count: int)
signal dialogue_opened(npc_id: String)
signal dialogue_closed(npc_id: String)
signal save_completed(path: String)
signal save_failed(message: String)
signal ending_reached(ending_id: String)

