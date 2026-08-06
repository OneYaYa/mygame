class_name CoolantPressurePuzzle
extends RefCounted


const TARGETS: PackedStringArray = ["valve_i", "valve_b", "valve_p"]
const PRESSURE_DELTAS: PackedInt32Array = [11, 6, -4]


static func build_scenario(rng: RandomNumberGenerator) -> Dictionary:
	var shuffled_deltas := _shuffled_ints(PRESSURE_DELTAS, rng)
	var deltas: Dictionary = {}
	for index: int in range(TARGETS.size()):
		deltas[TARGETS[index]] = shuffled_deltas[index]
	var required_targets: Array[String] = []
	var shuffled_targets: Array[String] = []
	for target: String in TARGETS:
		shuffled_targets.append(target)
	for index: int in range(shuffled_targets.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var temporary := shuffled_targets[index]
		shuffled_targets[index] = shuffled_targets[other]
		shuffled_targets[other] = temporary
	required_targets.assign(shuffled_targets.slice(0, 2))
	var start_pressure := rng.randi_range(38, 44)
	var target_pressure := start_pressure
	for target: String in required_targets:
		target_pressure += int(deltas.get(target, 0))
	return {
		"valve_deltas": deltas,
		"coolant_start_pressure": start_pressure,
		"coolant_target_pressure": target_pressure,
		"coolant_required_targets": required_targets,
	}


static func detail_text(scenario: Dictionary) -> String:
	var deltas: Dictionary = scenario.get("valve_deltas", {}) as Dictionary
	return "I 阀铭牌 %s；B 阀铭牌 %s；P 阀铭牌 %s。" % [
		_delta_text(int(deltas.get("valve_i", 0))),
		_delta_text(int(deltas.get("valve_b", 0))),
		_delta_text(int(deltas.get("valve_p", 0))),
	]


static func delta_for(scenario: Dictionary, target: String) -> int:
	return int((scenario.get("valve_deltas", {}) as Dictionary).get(target, 0))


static func is_vent(scenario: Dictionary, target: String) -> bool:
	return delta_for(scenario, target) < 0


static func resolve_toggle(target: String, scenario: Dictionary, flags: Dictionary) -> Dictionary:
	var states: Dictionary = (flags.get("valve_states", {}) as Dictionary).duplicate(true)
	var was_active := bool(states.get(target, false))
	states[target] = not was_active
	var signed_delta := delta_for(scenario, target) * (-1 if was_active else 1)
	var pressure := int(flags.get("coolant_pressure", scenario.get("coolant_start_pressure", 40))) + signed_delta
	var target_pressure := int(scenario.get("coolant_target_pressure", pressure))
	var aligned := pressure == target_pressure
	var adjustments := int(flags.get("coolant_adjustments", 0)) + 1
	var corrected := was_active
	var unsafe := pressure < 28 or pressure > 68
	var mistake := corrected or unsafe
	var event_text := "%s%s后，回路压力变为 %d kPa；目标稳定值为 %d kPa。" % [
		target_label(target),
		"复位" if was_active else "接入",
		pressure,
		target_pressure,
	]
	if aligned:
		event_text += " 压差窗口已经锁定，可以暴露并密封裂口。"
	elif unsafe:
		event_text += " 压力越过安全边界，联锁发出尖锐警报。"
	return {
		"states": states,
		"pressure": pressure,
		"aligned": aligned,
		"adjustments": adjustments,
		"oxygen_delta": -4 if is_vent(scenario, target) and not was_active else 0,
		"mistake": mistake,
		"event": {
			"type": "hazard" if unsafe else "puzzle",
			"text": event_text,
			"puzzle": "coolant",
			"mistake": mistake,
			"npc_line": (
				"压力针停住了。护板后的裂口露出来了，我现在够得到。"
				if aligned
				else "表针还没进目标刻度。我能把刚才那只复位，但每次调节都在耗气。"
			),
		},
	}


static func target_label(target: String) -> String:
	match target:
		"valve_i": return "I 阀"
		"valve_b": return "B 阀"
		"valve_p": return "P 阀"
		_: return target


static func _delta_text(value: int) -> String:
	return "%+d kPa" % value


static func _shuffled_ints(source: PackedInt32Array, rng: RandomNumberGenerator) -> Array[int]:
	var result: Array[int] = []
	for value: int in source:
		result.append(value)
	for index: int in range(result.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var temporary := result[index]
		result[index] = result[other]
		result[other] = temporary
	return result
