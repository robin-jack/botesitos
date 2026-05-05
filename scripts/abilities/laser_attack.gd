class_name LaserAttack
extends "res://scripts/abilities/ability.gd"

@export var laser_scene: PackedScene = preload("res://scenes/projectiles/laser.tscn")
@export var knockback_force: float = 400.0
@export var lifetime: float = 0.35
@export var beam_range: float = 1000.0
@export var spawn_point_path: NodePath = NodePath("")

var _spawn_point: Node2D = null

func _ready() -> void:
	super()
	if spawn_point_path != NodePath("") and owner_character:
		_spawn_point = owner_character.get_node_or_null(spawn_point_path)


func _server_execute(input_data: Dictionary, owner_char: CharacterBody2D, context, _sequence: int, _now_msec: int) -> bool:
	if laser_scene == null:
		return false

	var dir := _direction_from_input(input_data, owner_char)
	var spawn_pos: Vector2 = owner_char.global_position
	if _spawn_point:
		spawn_pos = _spawn_point.global_position
	spawn_pos += dir * 8.0

	context.spawn_combat_scene(laser_scene, {
		"position": spawn_pos,
		"direction": dir,
		"damage": damage,
		"knockback": knockback_force,
		"lifetime": lifetime,
		"range": beam_range,
		"owner_id": int(owner_char.peer_id),
		"team": str(owner_char.team),
	})
	return true
