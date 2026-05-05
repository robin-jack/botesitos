extends Area2D

var direction: Vector2 = Vector2.RIGHT
var damage: int = 0
var knockback: float = 0.0
var owner_peer_id: int = -1
var owner_team: String = ""
var lifetime: float = 0.0

var _hit_peer_ids := {}
var _configured: bool = false

func setup(data: Dictionary) -> void:
	if not _has_required_keys(data, [
		"position",
		"direction",
		"damage",
		"knockback",
		"owner_id",
		"team",
		"lifetime",
		"size",
	]):
		return

	var pos_data = data["position"]
	if not (pos_data is Vector2):
		push_error("MeleeHitbox.setup() requires Vector2 position")
		return
	global_position = pos_data
	var dir_data = data["direction"]
	direction = (dir_data if dir_data is Vector2 else Vector2.ZERO).normalized()
	if direction.length_squared() < 0.0001:
		push_error("MeleeHitbox.setup() received zero direction")
		return
	damage = int(data["damage"])
	knockback = float(data["knockback"])
	owner_peer_id = int(data["owner_id"])
	owner_team = str(data["team"])
	lifetime = float(data["lifetime"])
	if lifetime <= 0.0:
		push_error("MeleeHitbox.setup() requires lifetime > 0")
		return

	var size_data = data["size"]
	var hitbox_size: Vector2 = size_data if size_data is Vector2 else Vector2.ZERO
	if hitbox_size == Vector2.ZERO:
		push_error("MeleeHitbox.setup() requires non-zero hitbox size")
		return
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision and collision.shape is RectangleShape2D:
		collision.shape = collision.shape.duplicate()
		var rect := collision.shape as RectangleShape2D
		rect.size = hitbox_size
	rotation = direction.angle()
	_configured = true


func _ready() -> void:
	if not _is_server():
		return
	if not _configured:
		push_error("MeleeHitbox.setup() missing required runtime payload")
		queue_free()
		return
	await get_tree().physics_frame
	if not is_inside_tree():
		return
	_apply_overlaps()
	await get_tree().create_timer(max(0.01, lifetime)).timeout
	if is_inside_tree():
		queue_free()


func _apply_overlaps() -> void:
	for body in get_overlapping_bodies():
		if not body is CharacterBody2D:
			continue
		if not body.has_method("apply_server_damage"):
			continue
		if body.get("team") == owner_team:
			continue
		var target_peer := int(body.get("peer_id"))
		if target_peer == owner_peer_id or _hit_peer_ids.has(target_peer):
			continue
		_hit_peer_ids[target_peer] = true
		body.apply_server_damage(damage, direction, knockback, owner_peer_id)


func _is_server() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var mp := tree.get_multiplayer()
	return mp != null and mp.is_server()


func _has_required_keys(data: Dictionary, keys: Array[String]) -> bool:
	for key in keys:
		if not data.has(key):
			push_error("MeleeHitbox.setup() missing required key: " + key)
			return false
	return true
