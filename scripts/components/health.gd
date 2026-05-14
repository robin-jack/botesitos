class_name Health
extends Node

## Reusable health/damage node. Attach to any character.
## Damage and healing are authoritative on the server; state is synced to clients.

signal health_changed(old_value: int, new_value: int)
signal died

@export var max_health: int = 10

var current_health: int = max_health:
	set(v):
		var old := current_health
		current_health = clamp(v, 0, max_health)
		if current_health != old:
			health_changed.emit(old, current_health)

var is_dead: bool = false

func _ready() -> void:
	current_health = max_health

# Public API
func take_damage(amount: int, source: Node = null) -> void:
	if is_dead:
		return
	current_health -= amount
	if current_health <= 0:
		_die(source)

func heal(amount: int) -> void:
	if is_dead:
		return
	current_health += amount

func reset() -> void:
	is_dead = false
	current_health = max_health

func get_health_ratio() -> float:
	return float(current_health) / float(max_health)

# Internal
func _die(_source: Node) -> void:
	if is_dead:
		return
	is_dead = true
	died.emit()
