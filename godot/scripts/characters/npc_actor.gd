class_name TimeEchoNPCActor
extends Node2D

var npc_id: String = ""
var target_position: Vector2


func configure(profile: Dictionary, npc_state: Dictionary) -> void:
	npc_id = str(profile.get("id", ""))
	name = "NPC_%s" % npc_id
	position = Vector2(float(npc_state.get("x", 0.0)), float(npc_state.get("y", 0.0)))
	target_position = Vector2(float(npc_state.get("targetX", position.x)), float(npc_state.get("targetY", position.y)))
	var texture_path: String = "res://assets/images/processed/spr_%s.png" % npc_id
	if ResourceLoader.exists(texture_path):
		$Sprite2D.texture = load(texture_path) as Texture2D
	$NameLabel.text = str(profile.get("name", npc_id))
	$Sprite2D.flip_h = str(npc_state.get("facing", "down")) == "left"
	z_index = clampi(int(round(position.y)), 0, 4096)


func update_from_state(npc_state: Dictionary, delta: float) -> void:
	target_position = Vector2(float(npc_state.get("targetX", position.x)), float(npc_state.get("targetY", position.y)))
	position = position.move_toward(target_position, 34.0 * delta)
	$Sprite2D.flip_h = str(npc_state.get("facing", "down")) == "left"
	z_index = clampi(int(round(position.y)), 0, 4096)
