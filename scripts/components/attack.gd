class_name Attack
extends Node

## Base class for all attack types.
## Subclass this and override _perform_attack() to add new weapons or abilities.

signal attack_executed(attack_data: Dictionary)
signal attack_ready
signal cooldown_updated(ratio: float)  # 0.0 = just used, 1.0 = ready

@export var cooldown: float = 1
@export var damage: int = 1

var is_ready: bool = true
var _cooldown_timer: float = 0.0

## Reference to the owning character (set in _ready)
var owner_character: Player

func _ready() -> void:
	owner_character = get_parent() as Player


func _process(delta: float) -> void:
	if not is_ready:
		_cooldown_timer -= delta
		cooldown_updated.emit(get_cooldown_ratio())
		if _cooldown_timer <= 0.0:
			is_ready = true
			_cooldown_timer = 0.0
			attack_ready.emit()
			cooldown_updated.emit(1.0)


# --- Public API ---

## Call this from the owning character's input handler (authority peer only).
## Returns true if the attack fired.
func try_attack(direction: Vector2) -> bool:
	if not is_ready:
		return false
	is_ready = false
	_cooldown_timer = cooldown
	_perform_attack(direction)
	return true


func get_cooldown_ratio() -> float:
	if is_ready:
		return 1.0
	return 1.0 - (_cooldown_timer / cooldown)


func reset() -> void:
	is_ready = true
	_cooldown_timer = 0.0


# --- Override in subclasses ---

## Override this in subclasses to implement specific attack behaviour.
func _perform_attack(_direction: Vector2) -> void:
	push_error("AttackComponent._perform_attack() not implemented in " + get_script().resource_path)
