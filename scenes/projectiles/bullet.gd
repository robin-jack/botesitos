class_name Bullet
extends Area2D

## Projectile fired by regular players.
## Spawned and owned by the server. Despawns on first hit or lifetime expiry.

@export var lifetime: float = 2.5

var direction:      Vector2 = Vector2.RIGHT
var speed:          float   = 340.0
var damage:         int     = 20
var knockback_force: float  = 220.0
var owner_peer_id:  int     = -1
var owner_team:     int  = -1

var _alive: bool  = true
var _timer: float = 0.0

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
	owner_team      = data.get("team",      -1)
	rotation        = direction.angle()

func _on_body_entered(body: Node) -> void:
	if not _alive: return
	if body.get("team") == owner_team: return
	_apply_hit(body)

func _apply_hit(target: Node) -> void:
	if not multiplayer.is_server(): return
	if target.has_method("receive_damage"):
		target.receive_damage.rpc(damage, direction, knockback_force)
	_despawn()

func _despawn() -> void:
	_alive = false
	if multiplayer.is_server():
		queue_free()
