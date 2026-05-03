class_name GunAttack
extends Attack

## Fires a projectile in the given direction.
## Requests the server to spawn the projectile via RPC.

## Path to the projectile scene
@export var projectile_scene: PackedScene
@export_enum("projectile", "laser") var projectile_type: String = "projectile"
@export var projectile_speed: float = 340.0
@export var knockback_force: float = 220.0

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
	spawn_pos += direction * 8

	# Build attack data for the server spawn request
	var attack_data := {
		"type": projectile_type,
		"direction": direction,
		# The server computes damage, speed, team, and spawn position from trusted state.
		"position_hint": spawn_pos,
	}
	attack_executed.emit(attack_data)

	# Request the server to spawn — game.gd listens to this signal
	# (Works even for the authority peer because signals are local)
