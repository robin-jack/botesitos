class_name Dash
extends Node

## Reusable dash behaviour. Attach to any CharacterBody2D character.
## Parent must expose `velocity: Vector2`.

signal dash_started(direction: Vector2)
signal dash_ended
signal cooldown_finished

@export var dash_speed: float = 520.0
@export var dash_duration: float = 0.13
@export var cooldown: float = 1.2
@export var invincible_during_dash: bool = true

var is_dashing: bool = false
var is_on_cooldown: bool = false
var can_dash: bool = true:
	get: return !is_dashing and !is_on_cooldown

var _dash_timer: float = 0.0
var _cooldown_timer: float = 0.0
var _dash_direction: Vector2 = Vector2.RIGHT

func _process(delta: float) -> void:
	if is_dashing:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_end_dash()

	if is_on_cooldown:
		_cooldown_timer -= delta
		if _cooldown_timer <= 0.0:
			is_on_cooldown = false
			cooldown_finished.emit()

# Public API
## Returns true if the dash was started, false if on cooldown.
func try_dash(direction: Vector2) -> bool:
	if not can_dash:
		return false
	_dash_direction = direction.normalized()
	if _dash_direction == Vector2.ZERO:
		_dash_direction = Vector2.RIGHT
	is_dashing = true
	_dash_timer = dash_duration
	dash_started.emit(_dash_direction)
	return true

## Apply dash velocity to a given velocity vector and return the result.
## Call this from the parent's _physics_process while is_dashing is true.
func apply_dash_velocity(velocity: Vector2) -> Vector2:
	if is_dashing:
		velocity.x = _dash_direction.x * dash_speed
		velocity.y = 0.0  # cancel vertical movement during dash
	return velocity

func get_cooldown_ratio() -> float:
	if !is_on_cooldown:
		return 1.0
	return 1.0 - (_cooldown_timer / cooldown)

# Internal
func _end_dash() -> void:
	is_dashing = false
	is_on_cooldown = true
	_cooldown_timer = cooldown
	dash_ended.emit()
