class_name Player
extends CharacterBody2D

const EXPLOSION_SCENE = preload("uid://2f8twwxlgbxf")
const GRAVITY := 980.0
const COYOTE_TIME_MAX = 0.12 # seconds

enum TEAM { BOTINI, BOTATO }

# Replicated state (read/written by MultiplayerClient)
var facing_dir: bool = true:
	set(value):
		facing_dir = value
		if is_inside_tree() and animation:
			animation.flip_h = not value
var is_alive: bool = true

# Set by game.gd before add_child
@export var team: TEAM
var player_name: String = "Player"
var is_local: bool

# Stats
var max_health: int = 10
@export var move_speed: float = 200.0
@export var jump_force: float = -450.0
var gravity_scale: float = 1.0

# private input state
var _jump_req:  bool  = false
var _crouch_req:  bool  = false
var _dash_req:  bool  = false
var _atk_req:   bool  = false
var input_dir: float = 0.0

var coyote_timer: float = 0.0
var _damage_tween: Tween
var _game: Node2D

# node refs
@onready var health: Health = $Health
@onready var attack: Attack = $Attack
@onready var dash:   Dash = $Dash
@onready var animation: AnimatedSprite2D = $AnimatedSprite2D
@onready var shoot_sound = $ShootSound
@onready var camera = $Camera2D

func _ready() -> void:
	health.died.connect(_on_died)
	attack.attack_executed.connect(_on_attack_executed)
	_game = get_tree().get_first_node_in_group("game")

	is_local = is_multiplayer_authority()
	set_physics_process(is_local)
	camera.enabled = is_local
	
func _physics_process(_delta: float) -> void:
	if not is_alive:
		return
	dash.update(_delta)
	_apply_gravity(_delta)
	_gather_input()
	_handle_jump()
	_handle_dash()
	_handle_movement(_delta)
	_handle_attack()
	move_and_slide()
	_update_facing()
	
func _gather_input() -> void:
	input_dir = Input.get_axis("ui_left", "ui_right")
	_jump_req  = Input.is_action_just_pressed("ui_up")
	_crouch_req  = Input.is_action_pressed("ui_down")
	_dash_req  = Input.is_action_just_pressed(dash.input_key)
	_atk_req   = Input.is_action_just_pressed("attack")

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
		var dir := Vector2(input_dir if input_dir != 0.0 else (1.0 if facing_dir else -1.0), 0.0)
		dash.try_dash(dir)
	_dash_req = false
	if dash.is_dashing:
		velocity = dash.apply_dash_velocity(velocity)
	

func _handle_movement(delta: float) -> void:
	if dash.is_dashing:
		return
	velocity.x = move_toward(velocity.x, input_dir * move_speed, move_speed * delta * 12.0)

func _handle_attack() -> void:
	if _atk_req:
		var dir := Vector2(input_dir if input_dir != 0.0 else (1.0 if facing_dir else -1.0), 0.0)
		velocity -= dir * 200
		attack.try_attack(Vector2(1.0 if facing_dir else -1.0, 0.0))
	_atk_req = false

func _update_facing() -> void:
	if animation.animation == "shoot" and animation.is_playing():
		return
	if input_dir != 0:
		facing_dir = sign(input_dir) > 0
		animation.play("walk")
	else:
		if _crouch_req:
			animation.play("crouch")
		else:
			animation.play("idle")
	
func apply_damage(amount: int, direction: Vector2, knockback: float, is_authority: bool) -> void:
	if not is_alive:
		return
	_play_damage_effects(direction)
	if is_authority:
		velocity += (direction * knockback)
		velocity.y -= knockback / 4.0
	health.take_damage(amount)

func _play_damage_effects(hit_direction: Vector2) -> void:
	var explosion = EXPLOSION_SCENE.instantiate()
	var offset = -hit_direction.normalized() * 8.0
	explosion.global_position = global_position + offset
	_game.add_child(explosion)

	if is_instance_valid(_damage_tween):
		_damage_tween.kill()
	_damage_tween = create_tween()
	# Flash 3 times
	for i in range(3):
		_damage_tween.tween_property(animation, "modulate", Color.RED, 0.07)
		_damage_tween.tween_property(animation, "modulate", Color.WHITE, 0.07)

func _on_died() -> void:
	is_alive = false

func _on_attack_executed(data: Dictionary) -> void:
	animation.play("shoot")
	shoot_sound.play()
	if is_multiplayer_authority():
		_game.combat_manager.spawn_attack(data)
	else:
		_game.combat_manager.request_attack.rpc_id(1, data)
