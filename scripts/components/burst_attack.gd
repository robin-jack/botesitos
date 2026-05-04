class_name BurstAttack
extends Attack

## Tap-to-fire burst ammo.
## Each valid attack press spends 1 ammo.
## When ammo reaches 0, cooldown starts; then ammo replenishes one-by-one.

@export_enum("projectile", "laser") var projectile_type: String = "projectile"
@export var projectile_speed: float = 340.0
@export var knockback_force: float = 220.0
@export var spawn_point_path: NodePath = NodePath("")

@export var burst_size: int = 4
@export var burst_cooldown: float = 0.35
@export var replenish_interval: float = 0.2

var _spawn_point: Node2D = null
var _local_ammo: int = 0
var _cooldown_left: float = 0.0
var _replenish_left: float = 0.0
var _local_replenishing: bool = false

# Server-side authoritative burst state.
var _server_ammo: int = 0
var _server_cooldown_until_msec: int = 0
var _server_next_replenish_msec: int = 0
var _server_is_replenishing: bool = false

func _ready() -> void:
	super()
	_local_ammo = _get_max_ammo()
	_server_ammo = _local_ammo
	if spawn_point_path != NodePath(""):
		_spawn_point = owner_character.get_node_or_null(spawn_point_path)

func _process(delta: float) -> void:
	_tick_local_state(delta)

func try_attack(direction: Vector2) -> bool:
	if _local_ammo <= 0:
		return false

	_local_ammo -= 1
	if _local_ammo <= 0:
		_local_ammo = 0
		_local_replenishing = false
		_cooldown_left = max(0.0, burst_cooldown)
		_replenish_left = 0.0
	cooldown_updated.emit(_get_local_ratio())
	_emit_shot_request(direction)
	return true

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
	cooldown_updated.emit(1.0)
	attack_ready.emit()

func server_consume_one_shot(now_msec: int) -> bool:
	_tick_server_replenish(now_msec)
	if now_msec < _server_cooldown_until_msec:
		return false
	if _server_ammo <= 0:
		return false

	_server_ammo -= 1
	if _server_ammo <= 0:
		_server_ammo = 0
		_server_is_replenishing = false
		_server_next_replenish_msec = 0
		var cooldown_msec := int(max(0.0, burst_cooldown) * 1000.0)
		_server_cooldown_until_msec = now_msec + cooldown_msec
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
		cooldown_updated.emit(_get_local_ratio())
		if _local_ammo >= max_ammo:
			_local_replenishing = false
			attack_ready.emit()
			break

func _tick_server_replenish(now_msec: int) -> void:
	var max_ammo: int = _get_max_ammo()
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

func _emit_shot_request(direction: Vector2) -> void:
	var spawn_pos: Vector2 = owner_character.global_position
	if _spawn_point:
		spawn_pos = _spawn_point.global_position
	spawn_pos += direction * 8.0

	var attack_data := {
		"type": projectile_type,
		"direction": direction,
		"position_hint": spawn_pos,
	}
	attack_executed.emit(attack_data)

func _get_max_ammo() -> int:
	return max(1, burst_size)

func _get_local_ratio() -> float:
	return float(_local_ammo) / float(_get_max_ammo())
