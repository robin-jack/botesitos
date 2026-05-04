extends Area2D

const EXPLOSION_SCENE = preload("uid://2f8twwxlgbxf")

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
var _terrain_impact_emitted: bool = false

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
	if not _can_run():
		return
	await get_tree().physics_frame
	if not _can_run():
		return
	if _is_server():
		_configure_laser_geometry()
	if not _can_run():
		return
	var tree := get_tree()
	if tree == null:
		return
	await tree.create_timer(lifetime).timeout
	if not _can_run():
		return
	if _is_server():
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

	var terrain_hit := _get_terrain_hit_point()
	if terrain_hit.get("hit", false):
		_spawn_impact_effect(terrain_hit.get("point", global_position), "terrain")

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
	if not _can_run() or not _is_server():
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
			_spawn_impact_effect(body.global_position, "player")

func _spawn_impact_effect(at_position: Vector2, hit_type: String) -> void:
	if not _is_server():
		return
	if hit_type == "terrain":
		if _terrain_impact_emitted:
			return
		_terrain_impact_emitted = true
	play_impact_effect.rpc(at_position, hit_type)

@rpc("authority", "call_local", "reliable")
func play_impact_effect(at_position: Vector2, hit_type: String = "terrain") -> void:
	if not is_inside_tree():
		return
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

func _get_terrain_hit_point() -> Dictionary:
	var points: Array[Vector2] = []
	if ray_top.is_colliding():
		var top_collider := ray_top.get_collider()
		if not (top_collider is CharacterBody2D):
			points.append(ray_top.get_collision_point())
	if ray_bot.is_colliding():
		var bot_collider := ray_bot.get_collider()
		if not (bot_collider is CharacterBody2D):
			points.append(ray_bot.get_collision_point())
	if points.is_empty():
		return {"hit": false}

	var selected := points[0]
	for point in points:
		if point.distance_to(global_position) < selected.distance_to(global_position):
			selected = point
	return {"hit": true, "point": selected}

func _can_run() -> bool:
	return is_instance_valid(self) and is_inside_tree() and not is_queued_for_deletion()

func _is_server() -> bool:
	if not _can_run():
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var mp := tree.get_multiplayer()
	return mp != null and mp.is_server()
