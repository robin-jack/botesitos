class_name Ability
extends Node

## Base class for player-triggered abilities.
## Subclass this to add weapons, melee swings, shields, traps, or summons.

signal prediction_started(slot_id: String, sequence: int)
signal prediction_corrected(slot_id: String, state: Dictionary)
signal ability_ready(slot_id: String)
signal cooldown_updated(slot_id: String, ratio: float)  # 0.0 = just used, 1.0 = ready

@export var slot_id: String = "primary"
@export var cooldown: float = 1.0
@export var damage: int = 1

var is_ready: bool = true
var _local_cooldown_left: float = 0.0
var _server_next_allowed_msec: int = 0

var owner_character: CharacterBody2D

func _ready() -> void:
	owner_character = _find_owner_character()


func _process(delta: float) -> void:
	if not is_ready:
		_local_cooldown_left -= delta
		cooldown_updated.emit(slot_id, get_cooldown_ratio())
		if _local_cooldown_left <= 0.0:
			is_ready = true
			_local_cooldown_left = 0.0
			ability_ready.emit(slot_id)
			cooldown_updated.emit(slot_id, 1.0)


func client_try_execute(input_data: Dictionary, owner_char: CharacterBody2D, sequence: int) -> bool:
	if not is_ready:
		return false
	_start_local_cooldown()
	prediction_started.emit(slot_id, sequence)
	_client_execute(input_data, owner_char, sequence)
	return true


func server_try_execute(input_data: Dictionary, owner_char: CharacterBody2D, context, sequence: int) -> Dictionary:
	if context == null or not context.can_player_use_abilities(owner_char):
		return _server_response(false, sequence)

	var now_msec := Time.get_ticks_msec()
	if now_msec < _server_next_allowed_msec:
		return _server_response(false, sequence)

	_server_next_allowed_msec = now_msec + int(max(0.0, cooldown) * 1000.0)
	var accepted := _server_execute(input_data, owner_char, context, sequence, now_msec)
	if not accepted:
		_server_next_allowed_msec = now_msec
	return _server_response(accepted, sequence)


func server_get_state() -> Dictionary:
	var now_msec := Time.get_ticks_msec()
	var remaining: float = max(0.0, float(_server_next_allowed_msec - now_msec) / 1000.0)
	return {
		"ready": remaining <= 0.0,
		"cooldown_remaining": remaining,
	}


func client_apply_state(state: Dictionary) -> void:
	var remaining := float(state.get("cooldown_remaining", 0.0))
	is_ready = remaining <= 0.0
	_local_cooldown_left = remaining
	cooldown_updated.emit(slot_id, get_cooldown_ratio())
	if is_ready:
		ability_ready.emit(slot_id)
	prediction_corrected.emit(slot_id, state)


func get_cooldown_ratio() -> float:
	if is_ready:
		return 1.0
	if cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - (_local_cooldown_left / cooldown), 0.0, 1.0)


func reset() -> void:
	is_ready = true
	_local_cooldown_left = 0.0
	_server_next_allowed_msec = 0
	cooldown_updated.emit(slot_id, 1.0)
	ability_ready.emit(slot_id)


func _start_local_cooldown() -> void:
	is_ready = false
	_local_cooldown_left = max(0.0, cooldown)
	cooldown_updated.emit(slot_id, 0.0 if cooldown > 0.0 else 1.0)
	if cooldown <= 0.0:
		is_ready = true
		ability_ready.emit(slot_id)


func _server_response(accepted: bool, sequence: int) -> Dictionary:
	return {
		"accepted": accepted,
		"sequence": sequence,
		"state": server_get_state(),
	}


func _direction_from_input(input_data: Dictionary, owner_char: CharacterBody2D) -> Vector2:
	var dir_data = input_data.get("direction", Vector2.RIGHT)
	var dir: Vector2 = dir_data if dir_data is Vector2 else Vector2.RIGHT
	if dir.length_squared() < 0.0001:
		dir = Vector2(1.0 if owner_char.get("facing_right") else -1.0, 0.0)
	return dir.normalized()


func _find_owner_character() -> CharacterBody2D:
	var node := get_parent()
	while node:
		if node is CharacterBody2D:
			return node as CharacterBody2D
		node = node.get_parent()
	return null


func _client_execute(_input_data: Dictionary, _owner: CharacterBody2D, _sequence: int) -> void:
	pass


func _server_execute(_input_data: Dictionary, _owner: CharacterBody2D, _context, _sequence: int, _now_msec: int) -> bool:
	push_error("Ability._server_execute() not implemented in " + get_script().resource_path)
	return false
