class_name MeleeAttack
extends "res://scripts/abilities/ability.gd"

@export var hitbox_scene: PackedScene = preload("res://scenes/abilities/melee_hitbox.tscn")
@export var nrange: float = 32.0
@export var hitbox_size: Vector2 = Vector2(34.0, 22.0)
@export var knockback_force: float = 180.0
@export var lifetime: float = 0.08

func _server_execute(input_data: Dictionary, owner_char: CharacterBody2D, context, _sequence: int, _now_msec: int) -> bool:
	if hitbox_scene == null:
		return false

	var dir := _direction_from_input(input_data, owner_char)
	var spawn_pos := owner_char.global_position + dir * nrange
	context.spawn_combat_scene(hitbox_scene, {
		"position": spawn_pos,
		"direction": dir,
		"size": hitbox_size,
		"damage": damage,
		"knockback": knockback_force,
		"owner_id": int(owner_char.peer_id),
		"team": str(owner_char.team),
		"lifetime": lifetime,
	})
	return true
