extends Area2D

@export var facing_dir: float = 1.0

@onready var rect_top = $RectTop
@onready var rect_bot = $RectBottom
@onready var shape_top = $ShapeTop
@onready var shape_bot = $ShapeBottom
@onready var ray_top = $RayTop
@onready var ray_bot = $RayBottom

var shooter_id: int = 0
var hit_players = []

func _ready():
	await get_tree().physics_frame
	
	if multiplayer.is_server():
		var players_node = get_tree().root.get_node_or_null("Game/Players")
		if players_node:
			for player in players_node.get_children():
				ray_top.add_exception(player)
				ray_bot.add_exception(player)
		
		# Shoot both raycasts to max distance
		ray_top.target_position = Vector2(facing_dir * 1000.0, 0)
		ray_bot.target_position = Vector2(facing_dir * 1000.0, 0)
		ray_top.force_raycast_update()
		ray_bot.force_raycast_update()
		
		var len_top = 1000.0
		var len_bot = 1000.0
		
		if ray_top.is_colliding():
			len_top = ray_top.global_position.distance_to(ray_top.get_collision_point())
		if ray_bot.is_colliding():
			len_bot = ray_bot.global_position.distance_to(ray_bot.get_collision_point())
			
		# Sync the dual-length drawing to all screens
		draw_laser.rpc(len_top, len_bot, facing_dir)
		
		await get_tree().create_timer(2.0).timeout
		queue_free()

@rpc("call_local", "reliable")
func draw_laser(len_top: float, len_bot: float, dir: float):
	# 1. Setup Top Half (Y position -5, height 10)
	var st = RectangleShape2D.new()
	st.size = Vector2(len_top, 10)
	shape_top.shape = st
	rect_top.size = Vector2(len_top, 10)
	
	# 2. Setup Bottom Half (Y position 5, height 10)
	var sb = RectangleShape2D.new()
	sb.size = Vector2(len_bot, 10)
	shape_bot.shape = sb
	rect_bot.size = Vector2(len_bot, 10)
	
	# Adjust positioning based on direction
	if dir < 0:
		shape_top.position = Vector2(-len_top / 2.0, -5)
		rect_top.position = Vector2(-len_top, -10)
		
		shape_bot.position = Vector2(-len_bot / 2.0, 5)
		rect_bot.position = Vector2(-len_bot, 0)
	else:
		shape_top.position = Vector2(len_top / 2.0, -5)
		rect_top.position = Vector2(0, -10)
		
		shape_bot.position = Vector2(len_bot / 2.0, 5)
		rect_bot.position = Vector2(0, 0)

func _physics_process(_delta):
	if not multiplayer.is_server(): return
	
	for body in get_overlapping_bodies():
		if body is CharacterBody2D and body.name != str(shooter_id):
			if body not in hit_players: 
				hit_players.append(body)
				if body.has_method("take_damage"):
					body.take_damage(5, facing_dir)
