class_name Bullet
extends Area2D

## Projectile fired by regular players.
## Spawned and owned by the server. Despawns on first hit or lifetime expiry.

const PLAYER_HIT_SCENE: PackedScene = preload("uid://2f8twwxlgbxf")
const TERRAIN_HIT_SCENE: PackedScene = preload("uid://dre7ej5sq8d2g")

var lifetime: float = 0.0
var direction: Vector2 = Vector2.RIGHT
var speed: float = 0.0
var damage: int = 0
var knockback_force: float = 0.0
var owner_peer_id: int = -1
var owner_team: String = ""

var _alive: bool  = true
var _timer: float = 0.0
var _impact_played: bool = false
var _configured: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if not _configured:
		push_error("Bullet.setup() missing required runtime payload")
		queue_free()
		return
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	if not _alive: return
	_timer += delta
	if _timer >= lifetime:
		_despawn()
		return
	position += direction * speed * delta
	queue_redraw()
	
## Called immediately after the node is added to the scene tree.
func setup(data: Dictionary) -> void:
	if not _has_required_keys(data, [
		"position",
		"direction",
		"speed",
		"damage",
		"knockback",
		"owner_id",
		"team",
		"lifetime",
	]):
		return

	var pos_data = data["position"]
	if not (pos_data is Vector2):
		push_error("Bullet.setup() requires Vector2 position")
		return
	var dir_data = data["direction"]
	if not (dir_data is Vector2):
		push_error("Bullet.setup() requires Vector2 direction")
		return

	global_position = pos_data
	direction = dir_data.normalized()
	if direction.length_squared() < 0.0001:
		push_error("Bullet.setup() received zero direction")
		return
	speed = float(data["speed"])
	damage = int(data["damage"])
	knockback_force = float(data["knockback"])
	owner_peer_id = int(data["owner_id"])
	owner_team = str(data["team"])
	lifetime = float(data["lifetime"])
	if lifetime <= 0.0:
		push_error("Bullet.setup() requires lifetime > 0")
		return
	rotation = direction.angle()
	_configured = true

func _on_body_entered(body: Node) -> void:
	if not _alive: return
	if body.get("team") == owner_team: return
	if body.has_method("apply_server_damage"):
		_apply_hit(body, "player")
	else:
		_despawn("terrain")

func _apply_hit(target: Node, hit_type: String) -> void:
	if not _is_server(): return
	if target.has_method("apply_server_damage"):
		target.apply_server_damage(damage, direction, knockback_force, owner_peer_id)
	_despawn(hit_type)

func _despawn(hit_type: String = "terrain") -> void:
	if not _alive:
		return
	_alive = false
	if _is_server():
		play_impact_effect.rpc(global_position, hit_type)
		queue_free()
	else:
		play_impact_effect(global_position, hit_type)

@rpc("authority", "call_local", "reliable")
func play_impact_effect(at_position: Vector2, hit_type: String = "terrain") -> void:
	if _impact_played:
		return
	_impact_played = true
	
	var explosion_effect: PackedScene
	if hit_type == "player":
		explosion_effect = PLAYER_HIT_SCENE
	else:
		explosion_effect = TERRAIN_HIT_SCENE
		
	var explosion := explosion_effect.instantiate()
	explosion.global_position = at_position
	var game := get_tree().root.get_node_or_null("Game")
	if game:
		game.add_child(explosion)

func _is_server() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var mp := tree.get_multiplayer()
	return mp != null and mp.is_server()


func _has_required_keys(data: Dictionary, keys: Array[String]) -> bool:
	for key in keys:
		if not data.has(key):
			push_error("Bullet.setup() missing required key: " + key)
			return false
	return true
