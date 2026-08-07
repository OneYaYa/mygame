class_name LocalNpcProvider
extends RefCounted


const DEFAULT_NAME := "林岚"

const ACTION_VERBS: Dictionary = {
	"move": ["前往", "移动到", "走到", "过去", "回到", "进入", "去"],
	"inspect": ["检查", "查看", "看看", "观察", "核对", "扫描", "读一下"],
	"take": ["拿起", "拿上", "拾取", "捡起", "带上", "拿"],
	"drop": ["放下", "留下", "丢下"],
	"connect": ["连接", "接上", "插上", "接入"],
	"toggle": ["切换", "调节", "接入", "复位", "扳动", "旋转", "拧开", "开阀", "开启阀", "打开阀"],
	"use": ["使用", "安装", "接入", "启动", "发射", "涂上", "密封"],
	"wait": ["等待", "原地等", "保持原位", "别动"],
}

const TARGET_ALIASES: Dictionary = {
	"relay_control": ["中继控制室", "控制室", "中继室", "rly-01"],
	"central_junction": ["中央交汇舱", "交汇舱", "中央舱", "路口", "jnc-02"],
	"power_bay": ["主电网舱", "电网舱", "电力舱", "pwr-03"],
	"coolant_gallery": ["冷却回廊", "冷却舱", "回廊", "clt-04"],
	"escape_pod": ["逃生舱", "救生舱", "esc-05"],
	"telemetry_console": ["遥测台", "遥测", "控制台", "诊断包"],
	"escape_bulkhead": ["逃生舱隔门", "逃生门", "隔门", "锁灯"],
	"cable_panel": ["电缆面板", "接头面板", "面板", "电缆"],
	"valve_manifold": ["冷却阀组", "阀组", "阀门面板", "管路"],
	"launch_console": ["发射控制器", "发射台", "逃生舱控制器"],
	"phase_fuse": ["相位保险芯", "保险芯", "保险栓", "熔芯"],
	"sealant_kit": ["低温密封剂", "密封剂", "修补剂", "密封包"],
	"emergency_cell": ["应急旁路电芯", "旁路电芯", "应急电芯", "备用电芯"],
	"oxygen_canister": ["便携氧气罐", "氧气罐", "供氧罐"],
	"blue_cable": ["蓝色套管接头", "蓝色接头", "蓝接头", "蓝线", "蓝色", "4.2Ω", "4.2欧"],
	"red_cable": ["红色陶瓷接头", "红色接头", "红接头", "红线", "红色", "陶瓷"],
	"yellow_cable": ["黄色编织接头", "黄色接头", "黄接头", "黄线", "黄色", "编织线"],
	"valve_i": ["i阀", "i 阀", "字母i"],
	"valve_b": ["b阀", "b 阀", "字母b"],
	"valve_p": ["p阀", "p 阀", "字母p"],
}


func decide(context: Dictionary, player_text: String) -> Dictionary:
	var npc: Dictionary = _dictionary(context.get("npc", {}))
	var observation: Dictionary = _dictionary(context.get("observation", {}))
	var state: Dictionary = _dictionary(context.get("state", context.get("snapshot", {})))
	var memory: Dictionary = _dictionary(context.get("conversation_memory", {}))
	var actions: Array[Dictionary] = _action_list(context)
	var text := player_text.strip_edges()
	var lower := _compact(text)
	var npc_name := str(npc.get("name", DEFAULT_NAME))
	var room_name := str(observation.get("room_name", observation.get("location", state.get("room_name", "未知舱段"))))
	var mood := _mood_from_state(state)
	var intent := "conversation"
	var reply := _idle_reply(room_name, state)
	var candidate := ""
	var target := ""

	if _is_unsupported_time_jump(lower):
		intent = "refuse"
		reply = "不对。舱内计时只走了几个通讯周期，我仍在%s。这里没有过去一年——告诉我现在要看哪里或往哪走。" % room_name
	elif _contains_any(lower, ["我叫什么", "我的名字", "记得我吗"]):
		intent = "report"
		var player_name := str(memory.get("player_name", "")).strip_edges()
		reply = "记得。你叫%s。信号再抖我也不会把这个弄丢。" % player_name if not player_name.is_empty() else "你还没告诉我名字……信号里只有你的声音。"
	elif _contains_any(lower, ["别怕", "坚持", "我在", "你还好吗", "还撑得住", "放心"]):
		intent = "reassure"
		reply = _reassurance_reply(state)
	elif _contains_any(lower, ["受伤了吗", "哪里受伤", "伤得", "呼吸还稳", "呼吸怎么样", "身体怎么样", "感觉怎么样", "哪里最难受"]):
		intent = "report"
		reply = _health_reply(state)
	elif _contains_any(lower, ["什么声音", "声音", "气味", "闻到", "听到", "不安的东西"]):
		intent = "report"
		reply = _sensory_reply(room_name, observation)
	elif _contains_any(lower, ["最后清楚记得", "最后记得", "发生了什么", "怎么被困"]):
		intent = "report"
		reply = "我记得压力警报先响，照明灭了一次，接着隔门落下。我撞上遥测台，醒来时线路图已经烧黑。之后的顺序我不敢保证。"
	elif _contains_any(lower, ["只检查一件", "最想先确认", "最想确认", "最担心什么"]):
		intent = "report"
		reply = _concern_reply(room_name, observation, state)
	elif _contains_any(lower, ["看见", "看到", "观察到", "周围", "什么情况", "报告", "whatdoyousee"]):
		intent = "report"
		reply = _observation_reply(room_name, observation, state)
	elif _contains_any(lower, ["在哪里", "你在哪", "位置", "哪个房间", "whereareyou"]):
		intent = "report"
		reply = "我在%s。门外还有通道，可我从这里看不到尽头……你那边能看见整张图吗？" % room_name
	elif _contains_any(lower, ["氧气", "oxygen", "o2"]):
		intent = "report"
		var oxygen := _number(state, ["oxygen", "oxygen_percent", "o2"], -1.0)
		if oxygen < 0.0:
			reply = "面罩上的数字一直跳，我读不出来。供气声也不对……但我还能走。"
		elif oxygen <= 25.0:
			reply = "面罩上只剩%s。每吸一口都会断一下……我还能走，别让我白跑。" % _format_percent(oxygen)
		else:
			reply = "面罩显示%s。供气声有点发颤，不过我现在还能正常走。" % _format_percent(oxygen)
	elif _contains_any(lower, ["危险", "风险", "先别", "不要", "别动", "停止", "取消", "不用", "hold", "risk"]):
		intent = "report"
		reply = "好，我不动。最让我怕的是%s……你那边慢慢看，别把我丢在这儿。" % _risk_summary(observation, state)
	else:
		var parsed: Dictionary = _match_action(actions, lower)
		match str(parsed.get("status", "none")):
			"match":
				var action: Dictionary = parsed.get("action", {}) as Dictionary
				candidate = str(action.get("action", action.get("id", action.get("action_id", ""))))
				target = str(action.get("target", ""))
				intent = "propose_action"
				reply = "好，你是让我%s，对吗？" % str(action.get("label", candidate))
			"ambiguous":
				intent = "clarify"
				reply = "等等，你说的是哪一个？这里有不止一个。"
			"unavailable":
				intent = "clarify"
				reply = "我这儿做不了这个……没有你说的东西。"
			_:
				if _contains_any(lower, ["哪个", "哪根", "顺序", "先开", "接什么", "怎么修", "怎么办"]):
					intent = "clarify"
					reply = _puzzle_uncertainty_reply(room_name, observation)
				else:
					reply = _general_reply(text, npc_name, room_name, observation, state)

	return {
		"reply": reply,
		"intent": intent,
		"action": candidate,
		"target": target,
		"mood": mood,
		"provider": "local",
	}


func _match_action(actions: Array[Dictionary], text: String) -> Dictionary:
	if text.ends_with("吗"):
		return {"status": "none"}
	if _contains_any(text, [
		"不要", "先别", "先不要", "别动", "停止", "取消", "不用", "不许", "不是让你",
		"如果", "假如", "除非", "要是", "哪个", "哪根", "哪一个", "什么", "怎么", "应该",
		"能不能", "是否", "可以吗", "行吗", "要不要", "为什么",
	]):
		return {"status": "none"}
	var requested_ids: Array[String] = _requested_action_ids(text)
	if requested_ids.is_empty():
		return {"status": "none"}
	var candidates: Array[Dictionary] = []
	for action: Dictionary in actions:
		if not bool(action.get("enabled", true)):
			continue
		var action_id := str(action.get("action", action.get("id", action.get("action_id", "")))).to_lower()
		if action_id not in requested_ids:
			continue
		var score: int = _target_score(action, text)
		candidates.append({"action": action, "score": score})
	if candidates.is_empty():
		return {"status": "unavailable"}
	var best_score: int = -1
	for candidate: Dictionary in candidates:
		best_score = maxi(best_score, int(candidate.get("score", 0)))
	var best: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		if int(candidate.get("score", 0)) == best_score:
			best.append(candidate.get("action", {}) as Dictionary)
	if best_score > 0 and best.size() == 1:
		return {"status": "match", "action": best[0]}
	if candidates.size() == 1:
		return {"status": "match", "action": candidates[0].get("action", {}) as Dictionary}
	return {"status": "ambiguous"}


func _requested_action_ids(text: String) -> Array[String]:
	var result: Array[String] = []
	for action_id: String in ACTION_VERBS:
		for verb: Variant in ACTION_VERBS[action_id] as Array:
			if text.contains(_compact(str(verb))):
				result.append(action_id)
				break
	# “打开/开启”只在明确提到阀时解释为 toggle，避免把开门问题当动作。
	if (text.contains("打开") or text.contains("开启")) and (text.contains("阀") or text.contains("红帽")) and "toggle" not in result:
		result.append("toggle")
	return result


func _target_score(action: Dictionary, text: String) -> int:
	var label: String = _compact(str(action.get("label", "")))
	if label.length() >= 3 and text.contains(label):
		return 120 + label.length()
	var target: String = str(action.get("target", ""))
	if not target.is_empty() and text.contains(_compact(target)):
		return 110
	var best: int = 0
	for alias: Variant in TARGET_ALIASES.get(target, []) as Array:
		var clean_alias: String = _compact(str(alias))
		if clean_alias.length() >= 1 and text.contains(clean_alias):
			best = maxi(best, 60 + clean_alias.length())
	return best


func _observation_reply(room_name: String, observation: Dictionary, state: Dictionary) -> String:
	var detail := str(observation.get("summary", "")).strip_edges()
	var hazards: Array = _array(observation.get("hazards", []))
	var suffix := ""
	if not hazards.is_empty():
		suffix = " 还有%s……我没敢靠太近。" % _display_value(hazards[0])
	elif str(state.get("stress", "")) in ["strained", "critical_but_functional"]:
		suffix = " 面罩一直起雾，小字我真看不清。"
	return "我在%s。%s%s再细一点的，你问我，我凑近看。" % [room_name, detail, suffix]


func _puzzle_uncertainty_reply(room_name: String, observation: Dictionary) -> String:
	var detail := str(observation.get("summary", "")).strip_edges()
	return "我在%s，眼前只有这些：%s远端目标值不在我这块屏上。" % [room_name, detail]


func _sensory_reply(room_name: String, observation: Dictionary) -> String:
	match str(observation.get("room_id", "")):
		"relay_control": return "应急灯每隔几秒嗡一声，空气里有烧焦塑料味。隔门后没有脚步声——这比警报更让我不安。"
		"power_bay": return "有臭氧和焦糊味，三个接头都在轻微噼啪响。左边控制器的风扇转一下就停。"
		"coolant_gallery": return "冷却剂有甜腥味，脚边一直有泄气声。面罩边缘在结霜，我的视野不完整。"
		"central_junction": return "冷雾沿地面流，逃生门后有低频泵声。两盏锁灯没有变化。"
		_: return "这里主要是风机和我自己的呼吸声。%s" % str(observation.get("summary", ""))


func _concern_reply(room_name: String, observation: Dictionary, state: Dictionary) -> String:
	if str(state.get("stress", "")) in ["strained", "critical_but_functional"]:
		return "先帮我确认下一步是不是非做不可。每走一段，面罩里的数字都在掉……我不想把气浪费在猜上。"
	match str(observation.get("room_id", "")):
		"relay_control": return "那台遥测台还在响，可屏幕已经黑了。我不知道它有没有把东西送出去。"
		"power_bay": return "这三个接头一直在噼啪响。标签全烧了，我只认得它们通向哪里。"
		"coolant_gallery": return "I、B、P 的增减量我能读到，可目标压力只在你那边。我不敢随便碰。"
		_: return "我最怕身后那道联锁再落下来。它现在怎么样，我从这里看不全。"


func _general_reply(text: String, npc_name: String, room_name: String, observation: Dictionary, state: Dictionary) -> String:
	if text.is_empty():
		return "我在。信号有点杂，不过听得见。"
	var stress := str(state.get("stress", "controlled"))
	if stress in ["strained", "critical_but_functional"]:
		return "我听到了……你是要我看哪儿，还是往哪儿走？"
	var detail := str(observation.get("summary", "")).strip_edges()
	if not detail.is_empty():
		return "听见了。我还在%s……刚才那句我没弄明白。你是在问我，还是要我动？" % room_name
	return "我没太听明白。你是让我做什么？"


func _is_unsupported_time_jump(text: String) -> bool:
	return _contains_any(text, [
		"过了一年", "一年后", "已经一年", "一年过去", "转眼一年",
		"过了几年", "几年后", "数年后", "多年后",
		"过了一个月", "一个月后", "过了一周", "一周后", "第二天", "隔天",
	])


func _idle_reply(room_name: String, state: Dictionary) -> String:
	if str(state.get("stress", "controlled")) in ["strained", "critical_but_functional"]:
		return "我还在%s……呼吸有点跟不上。" % room_name
	return "我在%s。这里的线路图看不见了，" % room_name


func _reassurance_reply(state: Dictionary) -> String:
	if str(state.get("stress", "controlled")) in ["strained", "critical_but_functional"]:
		return "……好。你还在就好。别停太久，我一安静下来就只听得见自己的呼吸。"
	return "听到了。谢谢……你继续说话就好，这里安静得让我发慌。"


func _health_reply(state: Dictionary) -> String:
	match str(state.get("stress", "controlled")):
		"critical_but_functional":
			return "左肩完全抬不起来。每吸一口都会断一下……别催，我得先把这口气接上。"
		"strained":
			return "左肩疼得厉害，面罩里全是雾。右手还稳……先让我喘口气。"
		_:
			return "左肩一动就疼，应该是刚才撞的。没流血……至少我摸到的地方没有。"


func _risk_summary(observation: Dictionary, state: Dictionary) -> String:
	var hazards: Array = _array(observation.get("hazards", []))
	if not hazards.is_empty():
		return _display_value(hazards[0])
	var oxygen := _number(state, ["oxygen", "oxygen_percent", "o2"], 100.0)
	if oxygen <= 25.0:
		return "呼吸器供气断续"
	return "我不知道哪一下会把剩下的氧气也放掉"


func _mood_from_state(state: Dictionary) -> String:
	match str(state.get("stress", "controlled")):
		"critical_but_functional": return "hurt"
		"strained": return "afraid"
		"tense": return "nervous"
		_: return "focused"


func _action_list(context: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source: Array = _array(context.get("available_actions", context.get("actions", [])))
	for value: Variant in source:
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result


func _number(source: Dictionary, keys: Array[String], fallback: float) -> float:
	for key: String in keys:
		if source.has(key):
			return float(source[key])
	var resources: Dictionary = _dictionary(source.get("resources", {}))
	for key: String in keys:
		if resources.has(key):
			return float(resources[key])
	return fallback


func _format_percent(value: float) -> String:
	return "%d%%" % int(round(value))


func _contains_any(text: String, values: Array[String]) -> bool:
	for value: String in values:
		if text.contains(_compact(value)):
			return true
	return false


func _compact(value: String) -> String:
	return value.to_lower().replace(" ", "").replace("\t", "").replace("，", "").replace("。", "").replace("！", "").replace("？", "")


func _display_value(value: Variant) -> String:
	if value is Dictionary:
		var item := value as Dictionary
		return str(item.get("label", item.get("name", item.get("id", "未知"))))
	return str(value)


func _dictionary(value: Variant) -> Dictionary:
	return value as Dictionary if value is Dictionary else {}


func _array(value: Variant) -> Array:
	return value as Array if value is Array else []
