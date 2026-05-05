class_name GunAttack
extends "res://scripts/abilities/ability.gd"

@export var projectile_scene: PackedScene = preload("uid://b8mmf48321hp")
@export var projectile_speed: float = 380.0
@export var knockback_force: float = 220.0
@export var projectile_lifetime: float = 3.0
@export var spawn_point_path: NodePath = NodePath("")

var _spawn_point: Node2D = null

func _ready() -> void:
	super()
	if spawn_point_path != NodePath("") and owner_character:
		_spawn_point = owner_character.get_node_or_null(spawn_point_path)


func _server_execute(input_data: Dictionary, owner_char: CharacterBody2D, context, _sequence: int, _now_msec: int) -> bool:
	if projectile_scene == null:
		return false

	var dir := _direction_from_input(input_data, owner_char)
	var spawn_pos: Vector2 = owner_char.global_position
	if _spawn_point:
		spawn_pos = _spawn_point.global_position
	spawn_pos += dir * 8.0

	context.spawn_combat_scene(projectile_scene, {
		"position": spawn_pos,
		"direction": dir,
		"speed": projectile_speed,
		"damage": damage,
		"knockback": knockback_force,
		"lifetime": projectile_lifetime,
		"owner_id": int(owner_char.peer_id),
		"team": str(owner_char.team),
	})
	return true
