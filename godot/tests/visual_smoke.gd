extends Node

@onready var main: TimeEchoMain = $Main


func _ready() -> void:
	call_deferred("_show_town_square")


func _show_town_square() -> void:
	await get_tree().process_frame
	var state: Dictionary = GameManager.new_game()
	state["cinematic"] = null
	state["placeId"] = "town"
	var player_state: Dictionary = state.get("player", {}) as Dictionary
	player_state["x"] = 420.0
	player_state["y"] = 300.0
	player_state["facing"] = "down"
	state["player"] = player_state
	main.ui.close_modal(false)
	main.ui.show_game()
	main.world.load_state(state, true)
	for _frame: int in range(5):
		await get_tree().process_frame
	AudioManager.shutdown()
	await get_tree().process_frame
	get_tree().quit(0)
