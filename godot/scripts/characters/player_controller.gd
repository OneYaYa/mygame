class_name TimeEchoPlayer
extends CharacterBody2D

signal interact_pressed()
signal moved(world_position: Vector2, facing: String, running: bool)

@export var walk_speed: float = 96.0
@export var run_speed: float = 164.0

var active: bool = false
var world_bounds: Rect2 = Rect2(0, 0, 768, 480)
var facing: String = "down"


func _physics_process(_delta: float) -> void:
	if not active:
		velocity = Vector2.ZERO
		return
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var running: bool = Input.is_action_pressed("run")
	velocity = direction * (run_speed if running else walk_speed)
	if direction != Vector2.ZERO:
		if absf(direction.x) > absf(direction.y):
			facing = "right" if direction.x > 0.0 else "left"
		else:
			facing = "down" if direction.y > 0.0 else "up"
		var sprite: Sprite2D = $Sprite2D
		sprite.flip_h = facing == "left"
	move_and_slide()
	position.x = clampf(position.x, world_bounds.position.x + 12.0, world_bounds.end.x - 12.0)
	position.y = clampf(position.y, world_bounds.position.y + 12.0, world_bounds.end.y - 12.0)
	if direction != Vector2.ZERO:
		moved.emit(position, facing, running)


func _unhandled_input(event: InputEvent) -> void:
	if active and event.is_action_pressed("interact"):
		interact_pressed.emit()
		get_viewport().set_input_as_handled()


func configure(position_value: Vector2, facing_value: String, bounds: Rect2) -> void:
	position = position_value
	facing = facing_value
	world_bounds = bounds
	$Sprite2D.flip_h = facing == "left"

