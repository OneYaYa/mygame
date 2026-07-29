extends Node

var transitioning: bool = false


func can_reveal_portal(portal: Dictionary, state: Dictionary) -> bool:
	var flag_id: String = str(portal.get("revealFlag", ""))
	if flag_id.is_empty():
		return true
	return bool((state.get("flags", {}) as Dictionary).get(flag_id, false))


func travel(state: Dictionary, portal: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = TimeManager.advance_travel(state, float(portal.get("travelSeconds", 0.0)))
	state["regionId"] = str(portal.get("targetRegionId", state.get("regionId", "town")))
	state["placeId"] = str(portal.get("targetPlaceId", state["regionId"]))
	var spawn: Dictionary = portal.get("spawn", {}) as Dictionary
	var player: Dictionary = state.get("player", {}) as Dictionary
	player["x"] = float(spawn.get("x", 384.0))
	player["y"] = float(spawn.get("y", 350.0))
	player["facing"] = str(spawn.get("facing", "down"))
	state["player"] = player
	TimeManager.sync_world_flags(state)
	TimeManager.sync_npc_schedules(state)
	var scene: Dictionary = DataManager.get_scene_data(str(state["placeId"]))
	EventBus.scene_changed.emit(scene)
	return events


func request_scene(place_id: String) -> void:
	if DataManager.get_scene_data(place_id).is_empty():
		push_error("请求了不存在的地点：%s" % place_id)
		return
	EventBus.scene_change_requested.emit(place_id)

