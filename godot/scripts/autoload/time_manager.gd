extends Node

const LOOP_START_MINUTE: int = 6 * 60
const LOOP_GAME_MINUTES: int = 24 * 60
const LOOP_REAL_SECONDS: float = 12.0 * 60.0
const GAME_MINUTES_PER_REAL_SECOND: float = LOOP_GAME_MINUTES / LOOP_REAL_SECONDS
const RESET_WARNING_AT: int = LOOP_GAME_MINUTES - 5


func advance(state: Dictionary, delta_real_seconds: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.get("endingId") not in [null, ""] or state.get("cinematic") not in [null, ""]:
		return events
	if float(state.get("speed", 1.0)) <= 0.0:
		return events
	var previous: float = float(state.get("loopElapsed", 0.0))
	var modal_scale: float = 0.25 if bool(state.get("conversationOpen", false)) else 1.0
	var scene_scale: float = 0.0 if scene_pauses_time(str(state.get("placeId", ""))) else 1.0
	var elapsed: float = previous + maxf(0.0, delta_real_seconds) * GAME_MINUTES_PER_REAL_SECOND * float(state.get("speed", 1.0)) * modal_scale * scene_scale
	state["loopElapsed"] = minf(LOOP_GAME_MINUTES, elapsed)
	sync_clock(state)
	sync_world_flags(state)
	sync_npc_schedules(state)
	if previous < RESET_WARNING_AT and elapsed >= RESET_WARNING_AT:
		events.append({"type": "reset-warning"})
		EventBus.loop_warning.emit(int(state.get("loopCount", 0)))
	if previous < LOOP_GAME_MINUTES and elapsed >= LOOP_GAME_MINUTES:
		events.append({"type": "loop-reset"})
	return events


func advance_travel(state: Dictionary, real_seconds: float) -> Array[Dictionary]:
	if scene_pauses_time(str(state.get("placeId", ""))):
		return []
	var was_open: bool = bool(state.get("conversationOpen", false))
	state["conversationOpen"] = false
	var events: Array[Dictionary] = advance(state, real_seconds)
	state["conversationOpen"] = was_open
	return events


func sync_clock(state: Dictionary) -> void:
	var elapsed: float = clampf(float(state.get("loopElapsed", 0.0)), 0.0, LOOP_GAME_MINUTES)
	state["minute"] = int(LOOP_START_MINUTE + elapsed) % LOOP_GAME_MINUTES
	state["dayLabel"] = "SATURDAY" if elapsed < 18.0 * 60.0 else "SUNDAY"
	EventBus.clock_changed.emit(str(state["dayLabel"]), int(state["minute"]), int(state.get("loopCount", 0)))


func sync_world_flags(state: Dictionary) -> void:
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	var elapsed: float = float(state.get("loopElapsed", 0.0))
	flags["low_tide"] = elapsed >= 20.0 * 60.0 and elapsed < 21.0 * 60.0
	flags["basement_open"] = repair_count(state) == 3
	flags["hidden_darkroom_open"] = bool(flags.get("counterweight_raised", false)) \
		and bool(flags.get("light_route_inn_studio", false)) \
		and InventoryManager.has_item(state, "unnumbered_key")
	var photos: Dictionary = state.get("photos", {}) as Dictionary
	flags["slot_seven_filled"] = bool(flags.get("slot_seven_filled", false)) or bool(photos.get("fixed_portrait_installed", false))
	state["flags"] = flags


func sync_npc_schedules(state: Dictionary) -> void:
	var elapsed: float = float(state.get("loopElapsed", 0.0))
	var wander: float = 22.0 if int(elapsed / 35.0) % 2 != 0 else -18.0
	var schedule_flags: Dictionary = state.get("flags", {}) as Dictionary
	_move_npc(state, "dorothea", "inn-lobby" if elapsed < 16.0 * 60.0 else "inn-upstairs", 430.0 + wander if elapsed < 16.0 * 60.0 else 470.0, 275.0 if elapsed < 16.0 * 60.0 else 335.0)
	if bool(schedule_flags.get("arthur_stops_clock", false)):
		_move_npc(state, "arthur", "clock-basement", 310.0, 326.0)
	else:
		_move_npc(state, "arthur", "clock-cabin" if elapsed < 17.0 * 60.0 else "inn-upstairs", 385.0 + wander if elapsed < 17.0 * 60.0 else 130.0, 300.0 if elapsed < 17.0 * 60.0 else 335.0)
	var beatrice_committed: bool = bool(schedule_flags.get("beatrice_rings_seventh", false))
	if beatrice_committed:
		_move_npc(state, "beatrice", "chapel-belfry", 548.0, 368.0)
	else:
		_move_npc(state, "beatrice", "chapel-interior" if elapsed < 17.5 * 60.0 else "inn-upstairs", 545.0 if elapsed < 17.5 * 60.0 else 240.0, 320.0 + wander * 0.5 if elapsed < 17.5 * 60.0 else 335.0)
	_move_npc(state, "conrad", "harbor" if elapsed < 19.0 * 60.0 else "harbor-control", 770.0 + wander * 2.0 if elapsed < 19.0 * 60.0 else 560.0, 465.0 if elapsed < 19.0 * 60.0 else 315.0)
	_move_npc(state, "elias", "photo-studio" if elapsed < 18.0 * 60.0 else "inn-upstairs", 430.0 + wander if elapsed < 18.0 * 60.0 else 590.0, 315.0 if elapsed < 18.0 * 60.0 else 335.0)
	_move_npc(state, "florence", "archive-room" if elapsed < 18.0 * 60.0 else "inn-upstairs", 430.0 + wander if elapsed < 18.0 * 60.0 else 700.0, 270.0 if elapsed < 18.0 * 60.0 else 335.0)
	var flags: Dictionary = state.get("flags", {}) as Dictionary
	if bool(flags.get("slot_seven_filled", false)) and str(state.get("placeId", "")) == "hidden-darkroom":
		_move_npc(state, "ada", "hidden-darkroom", 560.0, 280.0, "left")
	else:
		_move_npc(state, "ada", "erased-space", 560.0, 280.0, "left")


func _move_npc(state: Dictionary, npc_id: String, place_id: String, x: float, y: float, facing: String = "down") -> void:
	var npcs: Dictionary = state.get("npcs", {}) as Dictionary
	if not npcs.has(npc_id):
		return
	var npc: Dictionary = npcs[npc_id] as Dictionary
	var changed_place: bool = str(npc.get("placeId", "")) != place_id
	npc["regionId"] = "town"
	npc["placeId"] = place_id
	if changed_place or not is_finite(float(npc.get("x", NAN))) or not is_finite(float(npc.get("y", NAN))):
		npc["x"] = x
		npc["y"] = y
	npc["targetX"] = x
	npc["targetY"] = y
	npc["facing"] = facing
	npcs[npc_id] = npc
	state["npcs"] = npcs


func repair_count(state: Dictionary) -> int:
	var repairs: Dictionary = state.get("repairs", {}) as Dictionary
	var total: int = 0
	for repair_id: String in ["master", "chapel", "tide"]:
		if bool(repairs.get(repair_id, false)):
			total += 1
	return total


func scene_pauses_time(place_id: String) -> bool:
	return place_id in ["hidden-darkroom", "low-tide-cave"]


func format_time(total_minutes: int) -> String:
	var normalized: int = posmod(total_minutes, 1440)
	return "%02d:%02d" % [normalized / 60, normalized % 60]
