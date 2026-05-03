extends CharacterBody2D

const EXPLOSION_SCENE = preload("uid://2f8twwxlgbxf")
const GRAVITY := 980.0
const COYOTE_TIME_MAX = 0.12

var facing_right: bool = true:
	set(value):
		facing_right = value
		if is_inside_tree() and sprite:
			sprite.flip_h = not value
var is_alive: bool = true

@export var team: String = "botinis"
var peer_id: int = 1
var player_name: String = "Player"

var move_speed: float = 180.0
var jump_force: float = -310.0
var gravity_scale: float = 1.0

var _jump_req: bool = false
var _dash_req: bool = false
var _atk_req: bool = false
var _input_dir: float = 0.0
var coyote_timer: float = 0.0

@onready var sprite: Sprite2D = $Sprite
@onready var health: Health = $Health
@onready var attack: Attack = $Attack
@onready var dash: Dash = $Dash

func _enter_tree() -> void:
	var pid_str := name.trim_prefix("Player_")
	if pid_str.is_valid_int():
		peer_id = pid_str.to_int()
		set_multiplayer_authority(peer_id)

func _ready() -> void:
	health.died.connect(_on_died)
	attack.attack_executed.connect(_on_attack_executed)
	set_physics_process(is_multiplayer_authority())

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	_apply_gravity(delta)
	_gather_input()
	_handle_jump()
	_handle_dash()
	_handle_movement(delta)
	_handle_attack()
	move_and_slide()
	_update_facing()

func _gather_input() -> void:
	_input_dir = Input.get_axis("ui_left", "ui_right")
	_jump_req = Input.is_action_just_pressed("ui_up")
	_dash_req = Input.is_action_just_pressed("ui_accept")
	_atk_req = Input.is_action_just_pressed("attack")

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * gravity_scale * delta
		coyote_timer -= delta
	else:
		coyote_timer = COYOTE_TIME_MAX

func _handle_jump() -> void:
	if _jump_req and coyote_timer > 0.0:
		velocity.y = jump_force
		coyote_timer = 0.0
	_jump_req = false

func _handle_dash() -> void:
	if _dash_req:
		var dir := Vector2(_input_dir if _input_dir != 0.0 else (1.0 if facing_right else -1.0), 0.0)
		dash.try_dash(dir)
	_dash_req = false
	if dash.is_dashing:
		velocity = dash.apply_dash_velocity(velocity)

func _handle_movement(delta: float) -> void:
	if dash.is_dashing:
		return
	var speed := move_speed
	velocity.x = move_toward(velocity.x, _input_dir * speed, speed * delta * 12.0)

func _handle_attack() -> void:
	if _atk_req:
		attack.try_attack(Vector2(1.0 if facing_right else -1.0, 0.0))
	_atk_req = false

func _update_facing() -> void:
	if velocity.x > 5.0:
		facing_right = true
	elif velocity.x < -5.0:
		facing_right = false

func apply_server_damage(amount: int, direction: Vector2, knockback: float, _source_peer_id: int = -1) -> void:
	if not multiplayer.is_server():
		return
	if not is_alive:
		return
	health.take_damage(amount)
	apply_damage_feedback.rpc(direction, knockback, is_alive)

@rpc("authority", "call_local", "reliable")
func apply_damage_feedback(hit_direction: Vector2, knockback: float, alive_after_hit: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if is_multiplayer_authority() and alive_after_hit:
		velocity += hit_direction.normalized() * knockback
	_play_damage_effects(hit_direction)

@rpc("authority", "call_local", "reliable")
func set_alive(alive: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	is_alive = alive
	visible = alive
	if not alive:
		velocity = Vector2.ZERO

@rpc("authority", "call_local", "reliable")
func respawn(pos: Vector2) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	global_position = pos
	velocity = Vector2.ZERO
	is_alive = true
	visible = true
	health.reset()
	attack.reset()

func _play_damage_effects(hit_direction: Vector2) -> void:
	var explosion = EXPLOSION_SCENE.instantiate()
	var offset = -hit_direction.normalized() * 8.0
	explosion.global_position = global_position + offset
	var game = get_tree().root.get_node_or_null("Game")
	if game:
		game.add_child(explosion)

	var tween = create_tween()
	for _i in range(3):
		tween.tween_property(sprite, "modulate", Color.RED, 0.07)
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.07)

func _on_died() -> void:
	if multiplayer.is_server():
		set_alive.rpc(false)

func _on_attack_executed(data: Dictionary) -> void:
	if not is_multiplayer_authority():
		return
	var game = get_tree().root.get_node_or_null("Game")
	if game == null:
		return
	if multiplayer.is_server():
		game._spawn_projectile_from_owner(self, data)
	else:
		game.request_spawn_projectile.rpc_id(1, data)
