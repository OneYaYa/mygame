class_name PowerRoutingPuzzle
extends RefCounted


const TARGETS: PackedStringArray = ["blue_cable", "red_cable", "yellow_cable"]
const READINGS: PackedStringArray = ["4.2 Ω", "6.8 Ω", "2.4 Ω"]


static func build_scenario(rng: RandomNumberGenerator) -> Dictionary:
	var shuffled_readings := _shuffled(READINGS, rng)
	var readings: Dictionary = {}
	for index: int in range(TARGETS.size()):
		readings[TARGETS[index]] = shuffled_readings[index]
	var correct := TARGETS[rng.randi_range(0, TARGETS.size() - 1)]
	return {
		"cable_readings": readings,
		"correct_cable": correct,
		"required_reading": str(readings.get(correct, "")),
	}


static func detail_text(scenario: Dictionary) -> String:
	var readings: Dictionary = scenario.get("cable_readings", {}) as Dictionary
	return "蓝色接头 %s；红色接头 %s；黄色接头 %s。" % [
		str(readings.get("blue_cable", "读数不清")),
		str(readings.get("red_cable", "读数不清")),
		str(readings.get("yellow_cable", "读数不清")),
	]


static func resolve_connection(target: String, scenario: Dictionary) -> Dictionary:
	if target == str(scenario.get("correct_cable", "")):
		return {
			"success": true,
			"power_delta": -2,
			"oxygen_delta": 0,
			"event": {
				"type": "puzzle",
				"text": "控制器接受该接头，闭环相位锁定；现在可以安装保险芯。",
				"puzzle": "power",
				"npc_line": "锁定灯亮了……好。控制器里‘咔’地弹开一个小盖，我看见保险芯槽了。",
			},
		}
	return {
		"success": false,
		"power_delta": -18,
		"oxygen_delta": -6,
		"event": {
			"type": "hazard",
			"text": "%s触发短路，电力与氧气回路同时受损。相位连接没有建立。" % target_label(target),
			"puzzle": "power",
			"mistake": true,
			"npc_line": "断开了……冲击把我撞到舱壁。给我两秒，我还在线",
		},
	}


static func target_label(target: String) -> String:
	match target:
		"blue_cable": return "蓝色接头"
		"red_cable": return "红色接头"
		"yellow_cable": return "黄色接头"
		_: return target


static func _shuffled(source: PackedStringArray, rng: RandomNumberGenerator) -> Array[String]:
	var result: Array[String] = []
	for value: String in source:
		result.append(value)
	for index: int in range(result.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var temporary := result[index]
		result[index] = result[other]
		result[other] = temporary
	return result
