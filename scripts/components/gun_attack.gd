class_name GunAttack
extends Attack

## Node path to the spawn point (relative to owner); falls back to owner position
@export var spawn_point_path: NodePath = NodePath("")

var _spawn_point: Node2D = null

func _ready() -> void:
	super()
	if spawn_point_path != NodePath(""):
		_spawn_point = owner_character.get_node_or_null(spawn_point_path)

func _perform_attack(direction: Vector2) -> void:
	var spawn_pos: Vector2 = owner_character.global_position
	if _spawn_point:
		spawn_pos = _spawn_point.global_position
	spawn_pos += direction * 14

	# Build attack data for the server spawn request
	var attack_data := {
		"attack_id": "gun_attack",
		"position": spawn_pos,
		"direction": direction,
		"rotation": direction.angle(),
		"owner_id": owner_character.get_multiplayer_authority(),
		"team": owner_character.get("team"),
	}
	attack_executed.emit(attack_data)
