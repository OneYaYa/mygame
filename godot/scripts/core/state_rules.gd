class_name StateRules
extends RefCounted


static func rule_met(rule: Dictionary, state: Dictionary) -> bool:
	if rule.is_empty():
		return true
	var expected: bool = bool(rule.get("value", true))
	var id: String = str(rule.get("id", ""))
	match str(rule.get("type", "")):
		"flag":
			return bool((state.get("flags", {}) as Dictionary).get(id, false)) == expected
		"repair":
			return bool((state.get("repairs", {}) as Dictionary).get(id, false)) == expected
		"item":
			return InventoryManager.has_item(state, id) == expected
		"evidence":
			return KnowledgeManager.has_evidence(state, id) == expected
		"knowledge":
			return KnowledgeManager.knows(state, id) == expected
		"photo":
			return bool((state.get("photos", {}) as Dictionary).get(id, false)) == expected
		"repairCount":
			return TimeManager.repair_count(state) >= int(rule.get("value", 0))
		"timeBetween":
			var elapsed: float = float(state.get("loopElapsed", 0.0))
			return elapsed >= float(rule.get("start", 0.0)) and elapsed < float(rule.get("end", 0.0))
	return true


static func requirements_met(subject: Dictionary, state: Dictionary) -> Dictionary:
	var missing: Array[Dictionary] = []
	for raw: Variant in subject.get("requirements", []):
		if typeof(raw) == TYPE_DICTIONARY and not rule_met(raw as Dictionary, state):
			missing.append(raw as Dictionary)
	return {"ok": missing.is_empty(), "missing": missing}

