extends Node

const PHOTO_ITEMS: PackedStringArray = ["unfinished_portrait", "fixed_portrait"]


func add_item(state: Dictionary, item_id: String, amount: int = 1) -> int:
	var inventory: Dictionary = state.get("inventory", {}) as Dictionary
	var total: int = maxi(0, int(inventory.get(item_id, 0)) + amount)
	inventory[item_id] = total
	state["inventory"] = inventory
	EventBus.inventory_changed.emit(inventory)
	return total


func has_item(state: Dictionary, item_id: String) -> bool:
	return int((state.get("inventory", {}) as Dictionary).get(item_id, 0)) > 0


func remove_item(state: Dictionary, item_id: String, amount: int = 1) -> bool:
	if not has_item(state, item_id):
		return false
	add_item(state, item_id, -amount)
	return true


func display_entries(state: Dictionary) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	var inventory: Dictionary = state.get("inventory", {}) as Dictionary
	for item_id: Variant in inventory.keys():
		var count: int = int(inventory[item_id])
		if count <= 0:
			continue
		var data: Dictionary = DataManager.get_item(str(item_id))
		output.append({
			"id": str(item_id),
			"name": str(data.get("name", item_id)),
			"description": str(data.get("description", "")),
			"count": count,
		})
	return output

