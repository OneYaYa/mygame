class_name GameFlowStateMachine
extends RefCounted

signal transitioned(previous: int, current: int)

enum State {
	TITLE,
	PROLOGUE,
	PLAYING,
	DIALOGUE,
	PUZZLE,
	PAUSED,
	RESETTING,
	ENDING,
}

var current: int = State.TITLE


func transition(next: int) -> bool:
	if next == current:
		return false
	var previous: int = current
	current = next
	transitioned.emit(previous, current)
	return true


func accepts_world_input() -> bool:
	return current == State.PLAYING
