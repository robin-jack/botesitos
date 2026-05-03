extends Area2D

@export var lifetime: float = 0.35

@onready var rect_top: ColorRect = $RectTop
@onready var rect_bot: ColorRect = $RectBottom
@onready var shape_top: CollisionShape2D = $ShapeTop
@onready var shape_bot: CollisionShape2D = $ShapeBottom
@onready var ray_top: RayCast2D = $RayTop
@onready var ray_bot: RayCast2D = $RayBottom

var facing_dir: float = 1.0
var shooter_id: int = -1
var owner_team: String = "botinis"
var damage: int = 5
var knockback: float = 120.0
var _hit_peer_ids := {}

func setup(data: Dictionary) -> void:
	var dir_data = data.get("direction", Vector2.RIGHT)
	var dir: Vector2 = dir_data if dir_data is Vector2 else Vector2.RIGHT
	if dir.length_squared() < 0.0001:
		dir = Vector2.RIGHT
	facing_dir = signf(dir.x)
	if facing_dir == 0.0:
		facing_dir = 1.0
	global_position = data.get("position", Vector2.ZERO)
	shooter_id = int(data.get("owner_id", -1))
	owner_team = str(data.get("team", "botinis"))
	damage = int(data.get("damage", 5))
	knockback = float(data.get("knockback", 120.0))

func _ready() -> void:
	await get_tree().physics_frame
	if multiplayer.is_server():
		_configure_laser_geometry()
	await get_tree().create_timer(lifetime).timeout
	if multiplayer.is_server():
		queue_free()

func _configure_laser_geometry() -> void:
	var max_len := 1000.0
	ray_top.target_position = Vector2(facing_dir * max_len, 0.0)
	ray_bot.target_position = Vector2(facing_dir * max_len, 0.0)
	ray_top.force_raycast_update()
	ray_bot.force_raycast_update()

	var len_top := max_len
	var len_bot := max_len
	if ray_top.is_colliding():
		len_top = ray_top.global_position.distance_to(ray_top.get_collision_point())
	if ray_bot.is_colliding():
		len_bot = ray_bot.global_position.distance_to(ray_bot.get_collision_point())
	draw_laser.rpc(len_top, len_bot, facing_dir)

@rpc("authority", "call_local", "reliable")
func draw_laser(len_top: float, len_bot: float, dir: float) -> void:
	var st = RectangleShape2D.new()
	st.size = Vector2(len_top, 10.0)
	shape_top.shape = st
	rect_top.size = Vector2(len_top, 10.0)

	var sb = RectangleShape2D.new()
	sb.size = Vector2(len_bot, 10.0)
	shape_bot.shape = sb
	rect_bot.size = Vector2(len_bot, 10.0)

	if dir < 0.0:
		shape_top.position = Vector2(-len_top / 2.0, -5.0)
		rect_top.position = Vector2(-len_top, -10.0)
		shape_bot.position = Vector2(-len_bot / 2.0, 5.0)
		rect_bot.position = Vector2(-len_bot, 0.0)
	else:
		shape_top.position = Vector2(len_top / 2.0, -5.0)
		rect_top.position = Vector2(0.0, -10.0)
		shape_bot.position = Vector2(len_bot / 2.0, 5.0)
		rect_bot.position = Vector2(0.0, 0.0)

func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	for body in get_overlapping_bodies():
		if body is CharacterBody2D:
			if not body.has_method("apply_server_damage"):
				continue
			if body.get("team") == owner_team:
				continue
			var target_peer := int(body.get("peer_id"))
			if target_peer == shooter_id or _hit_peer_ids.has(target_peer):
				continue
			_hit_peer_ids[target_peer] = true
			body.apply_server_damage(damage, Vector2(facing_dir, 0.0), knockback, shooter_id)
