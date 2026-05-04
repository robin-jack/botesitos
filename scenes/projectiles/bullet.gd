class_name Bullet
extends Area2D

## Projectile fired by regular players.
## Spawned and owned by the server. Despawns on first hit or lifetime expiry.

const EXPLOSION_SCENE = preload("uid://2f8twwxlgbxf")

@export var lifetime: float = 2.5

var direction:      Vector2 = Vector2.RIGHT
var speed:          float   = 340.0
var damage:         int     = 20
var knockback_force: float  = 220.0
var owner_peer_id:  int     = -1
var owner_team:     String  = "botinis"

var _alive: bool  = true
var _timer: float = 0.0
var _impact_played: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
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
	global_position = data.get("position",  Vector2.ZERO)
	direction       = data.get("direction", Vector2.RIGHT).normalized()
	speed           = data.get("speed",     340.0)
	damage          = data.get("damage",    20)
	knockback_force = data.get("knockback", 220.0)
	owner_peer_id   = data.get("owner_id",  -1)
	owner_team      = data.get("team",      "botinis")
	rotation        = direction.angle()

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
	var explosion := EXPLOSION_SCENE.instantiate()
	explosion.global_position = at_position
	if explosion is CanvasItem:
		var fx := explosion as CanvasItem
		if hit_type == "player":
			fx.modulate = Color(1.0, 1.0, 1.0, 1.0)
			fx.scale = Vector2.ONE
		else:
			fx.modulate = Color(1.0, 0.82, 0.42, 1.0)
			fx.scale = Vector2(0.85, 0.85)
	var game := get_tree().root.get_node_or_null("Game")
	if game:
		game.add_child(explosion)

func _is_server() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	var mp := tree.get_multiplayer()
	return mp != null and mp.is_server()
