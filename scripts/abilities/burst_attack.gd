class_name BurstAttack
extends "res://scripts/abilities/ability.gd"

## Tap-to-fire burst ammo.
## Each valid attack press spends 1 ammo.
## When ammo reaches 0, cooldown starts; then ammo replenishes one-by-one.

@export var projectile_scene: PackedScene = preload("uid://b8mmf48321hp")
@export var projectile_speed: float = 480.0
@export var knockback_force: float = 220.0
@export var projectile_lifetime: float = 3.0
@export var spawn_point_path: NodePath = NodePath("")

@export var burst_size: int = 5
@export var burst_cooldown: float = 0.95
@export var replenish_interval: float = 0.08

var _spawn_point: Node2D = null
var _local_ammo: int = 0
var _cooldown_left: float = 0.0
var _replenish_left: float = 0.0
var _local_replenishing: bool = false

var _server_ammo: int = 0
var _server_cooldown_until_msec: int = 0
var _server_next_replenish_msec: int = 0
var _server_is_replenishing: bool = false

func _ready() -> void:
	super()
	_local_ammo = _get_max_ammo()
	_server_ammo = _local_ammo
	if spawn_point_path != NodePath("") and owner_character:
		_spawn_point = owner_character.get_node_or_null(spawn_point_path)


func _process(delta: float) -> void:
	_tick_local_state(delta)


func client_try_execute(input_data: Dictionary, owner_char: CharacterBody2D, sequence: int) -> bool:
	if _local_ammo <= 0:
		return false

	_local_ammo -= 1
	if _local_ammo <= 0:
		_local_ammo = 0
		_local_replenishing = false
		_cooldown_left = max(0.0, burst_cooldown)
		_replenish_left = 0.0
	cooldown_updated.emit(slot_id, _get_local_ratio())
	prediction_started.emit(slot_id, sequence)
	_client_execute(input_data, owner_char, sequence)
	return true


func server_try_execute(input_data: Dictionary, owner_char: CharacterBody2D, context, sequence: int) -> Dictionary:
	if context == null or not context.can_player_use_abilities(owner_char):
		return _server_response(false, sequence)

	var now_msec := Time.get_ticks_msec()
	_tick_server_replenish(now_msec)
	if now_msec < _server_cooldown_until_msec or _server_ammo <= 0:
		return _server_response(false, sequence)

	_server_ammo -= 1
	if _server_ammo <= 0:
		_server_ammo = 0
		_server_is_replenishing = false
		_server_next_replenish_msec = 0
		_server_cooldown_until_msec = now_msec + int(max(0.0, burst_cooldown) * 1000.0)

	var accepted := _server_execute(input_data, owner_char, context, sequence, now_msec)
	return _server_response(accepted, sequence)


func server_get_state() -> Dictionary:
	var now_msec := Time.get_ticks_msec()
	_tick_server_replenish(now_msec)
	var cooldown_remaining: float = max(0.0, float(_server_cooldown_until_msec - now_msec) / 1000.0)
	var replenish_remaining: float = max(0.0, float(_server_next_replenish_msec - now_msec) / 1000.0)
	return {
		"ready": _server_ammo > 0 and cooldown_remaining <= 0.0,
		"ammo": _server_ammo,
		"max_ammo": _get_max_ammo(),
		"cooldown_remaining": cooldown_remaining,
		"replenish_remaining": replenish_remaining,
	}


func client_apply_state(state: Dictionary) -> void:
	_local_ammo = int(state.get("ammo", _local_ammo))
	_cooldown_left = float(state.get("cooldown_remaining", 0.0))
	_replenish_left = float(state.get("replenish_remaining", 0.0))
	_local_replenishing = _local_ammo < _get_max_ammo() and _cooldown_left <= 0.0
	is_ready = _local_ammo > 0
	cooldown_updated.emit(slot_id, _get_local_ratio())
	if is_ready:
		ability_ready.emit(slot_id)
	prediction_corrected.emit(slot_id, state)


func reset() -> void:
	super()
	_local_ammo = _get_max_ammo()
	_cooldown_left = 0.0
	_replenish_left = 0.0
	_local_replenishing = false
	_server_ammo = _local_ammo
	_server_cooldown_until_msec = 0
	_server_next_replenish_msec = 0
	_server_is_replenishing = false
	cooldown_updated.emit(slot_id, 1.0)
	ability_ready.emit(slot_id)


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


func _tick_local_state(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
		if _cooldown_left <= 0.0:
			_cooldown_left = 0.0
			if _local_ammo <= 0:
				_local_replenishing = true
				_replenish_left = max(0.01, replenish_interval)
		return

	if not _local_replenishing:
		return

	var max_ammo := _get_max_ammo()
	_replenish_left -= delta
	while _local_replenishing and _local_ammo < max_ammo and _replenish_left <= 0.0:
		_local_ammo += 1
		_replenish_left += max(0.01, replenish_interval)
		cooldown_updated.emit(slot_id, _get_local_ratio())
		if _local_ammo >= max_ammo:
			_local_replenishing = false
			ability_ready.emit(slot_id)
			break


func _tick_server_replenish(now_msec: int) -> void:
	var max_ammo := _get_max_ammo()
	if _server_ammo >= max_ammo:
		_server_is_replenishing = false
		_server_next_replenish_msec = 0
		return
	if now_msec < _server_cooldown_until_msec:
		return
	if not _server_is_replenishing:
		if _server_ammo <= 0:
			_server_is_replenishing = true
			_server_next_replenish_msec = now_msec + int(max(0.01, replenish_interval) * 1000.0)
		else:
			return
	if _server_next_replenish_msec <= 0 or now_msec < _server_next_replenish_msec:
		return

	var replenish_msec := int(max(0.01, replenish_interval) * 1000.0)
	while _server_ammo < max_ammo and now_msec >= _server_next_replenish_msec:
		_server_ammo += 1
		_server_next_replenish_msec += replenish_msec
		if _server_ammo >= max_ammo:
			_server_is_replenishing = false
			_server_next_replenish_msec = 0
			break


func _server_response(accepted: bool, sequence: int) -> Dictionary:
	return {
		"accepted": accepted,
		"sequence": sequence,
		"state": server_get_state(),
	}


func _get_max_ammo() -> int:
	return max(1, burst_size)


func _get_local_ratio() -> float:
	return float(_local_ammo) / float(_get_max_ammo())
