class_name Player
extends CharacterBody2D

const EXPLOSION_SCENE = preload("uid://2f8twwxlgbxf")
const GRAVITY := 980.0
const COYOTE_TIME_MAX = 0.12 # seconds

enum TEAM { BOTINI, BOTATO }

# Replicated state 
var facing_right: bool = true:
	set(value):
		facing_right = value
		if is_inside_tree() and animation:
			animation.flip_h = not value
var is_alive: bool = true

# Set by game.gd before add_child
@export var team: TEAM
var peer_id: int = 1
var player_name: String = "Player"

# Stats
var max_health = 10
var move_speed: float = 200.0
var jump_force: float = -450.0
var gravity_scale: float = 1.0

# private input state
var _jump_req:  bool  = false
var _crouch_req:  bool  = false
var _dash_req:  bool  = false
var _atk_req:   bool  = false
var input_dir: float = 0.0

var coyote_timer: float = 0.0

# node refs
@onready var health: Health = $Health
@onready var attack: Attack = $Attack
@onready var dash:   Dash = $Dash
@onready var animation = $AnimatedSprite2D


func _enter_tree() -> void:
	peer_id = int(name)
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
	input_dir = Input.get_axis("ui_left", "ui_right")
	_jump_req  = Input.is_action_just_pressed("ui_up")
	_crouch_req  = Input.is_action_pressed("ui_down")
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
		var dir := Vector2(input_dir if input_dir != 0.0 else (1.0 if facing_right else -1.0), 0.0)
		dash.try_dash(dir)
	_dash_req = false
	if dash.is_dashing:
		velocity = dash.apply_dash_velocity(velocity)
	

func _handle_movement(delta: float) -> void:
	if dash.is_dashing:
		return
	var speed := move_speed
	var control := 1.0
	velocity.x = move_toward(velocity.x, input_dir * speed, speed * control * delta * 12.0)

func _handle_attack() -> void:
	if _atk_req:
		animation.play("shoot")
		attack.try_attack(Vector2(1.0 if facing_right else -1.0, 0.0))
	_atk_req = false

func _update_facing() -> void:
	if velocity.x >  5.0:
		facing_right = true
		animation.play("walk")
	elif velocity.x < -5.0:
		facing_right = false
		animation.play("walk")
	else:
		if _crouch_req:
			animation.play("crouch")
		else:
			animation.play("idle")
	
# --- Network ---

# "authority" means the client would have to call it — wrong
# "any_peer" lets the server call it on all peers
@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: int, direction: Vector2, knockback: float) -> void:
	if not is_alive:
		return
	_rpc_play_damage_effects.rpc(direction)
	if is_multiplayer_authority():
		velocity += (direction * knockback)
		velocity.y -= knockback / 4.0
	health.take_damage(amount)
		
@rpc("any_peer", "call_local", "reliable")
func set_alive(alive: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	is_alive = alive
	visible = alive
	if not alive: velocity = Vector2.ZERO

@rpc("any_peer", "call_local", "reliable")
func respawn(pos: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		push_error("Something went wrong!")
		return
	global_position = pos
	velocity = Vector2.ZERO
	is_alive = true
	visible = true
	health.reset()
	attack.reset()

@rpc("any_peer", "reliable")
func _rpc_play_damage_effects(hit_direction: Vector2):
	var explosion = EXPLOSION_SCENE.instantiate()
	var offset = -hit_direction.normalized() * 8.0
	explosion.global_position = global_position + offset
	get_tree().root.get_node("Game").add_child(explosion)
	
	var tween = create_tween()
	# Flash 3 times
	for i in range(3):
		tween.tween_property(animation, "modulate", Color.RED, 0.07)
		tween.tween_property(animation, "modulate", Color.WHITE, 0.07)
	
# --- Internal call-backs ---

func _on_died() -> void:
	set_alive.rpc(false)

func _on_attack_executed(data: Dictionary) -> void:
	var game = get_tree().root.get_node("Game")
	if multiplayer.is_server():
		game.spawn_projectile(data)
	else:
		game.request_spawn_projectile.rpc_id(1, data)
