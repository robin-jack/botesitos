extends CharacterBody2D

const GRAVITY := 980.0

# Replicated state 
var facing_right: bool = true
var is_alive:     bool = true

# Set by game.gd before add_child
var team: String = "boss"
var peer_id: int = 1
var player_name: String = "Boss"

# Stats
var max_health = 10
var move_speed: float = 180.0
var jump_force: float = -310.0
var gravity_scale: float = 1.0

# private input state
var _jump_req:  bool  = false
var _dash_req:  bool  = false
var _atk_req:   bool  = false
var _input_dir: float = 0.0

# node refs
@onready var health: Health = $Health
@onready var attack: Attack = $Attack
@onready var dash:   Dash = $Dash

func _ready() -> void:
	health.died.connect(_on_died)
	attack.attack_executed.connect(_on_attack_executed)
	set_physics_process(is_multiplayer_authority())
	
func _physics_process(delta: float) -> void:
	if not is_alive: return
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
	_jump_req  = Input.is_action_just_pressed("ui_up")
	_dash_req  = Input.is_action_just_pressed("ui_accept")
	_atk_req   = Input.is_action_just_pressed("attack")

func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * gravity_scale * delta

func _handle_jump() -> void:
	if _jump_req and is_on_floor():
		velocity.y = jump_force
	_jump_req = false

func _handle_dash() -> void:
	if _dash_req:
		var dir := Vector2(_input_dir if _input_dir != 0.0 else (1.0 if facing_right else -1.0), 0.0)
		dash.try_dash(dir)
	_dash_req = false
	if dash.is_dashing:
		velocity = dash.apply_dash_velocity(velocity)

func _handle_movement(delta: float) -> void:
	if dash.is_dashing: return
	var speed := move_speed
	var control := 1.0
	velocity.x = move_toward(velocity.x, _input_dir * speed, speed * control * delta * 12.0)

func _handle_attack() -> void:
	if _atk_req:
		attack.try_attack(Vector2(1.0 if facing_right else -1.0, 0.0))
	_atk_req = false

func _update_facing() -> void:
	if   velocity.x >  5.0: facing_right = true
	elif velocity.x < -5.0: facing_right = false
	
# --- Network ---

# "authority" means the client would have to call it — wrong
# "any_peer" lets the server call it on all peers
@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: int, knockback: Vector2) -> void:
	if multiplayer.get_remote_sender_id() != 1: return  # only server can deal damage
	if not is_alive: return
	health.take_damage(amount)
	if is_multiplayer_authority():
		velocity += knockback
		
@rpc("any_peer", "call_local", "reliable")
func set_alive(alive: bool) -> void:
	if multiplayer.get_remote_sender_id() != 1: return  # only server controls alive state
	is_alive = alive
	visible = alive
	if not alive: velocity = Vector2.ZERO

@rpc("any_peer", "call_local", "reliable")
func respawn(pos: Vector2) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1: return
	global_position = pos
	velocity = Vector2.ZERO
	is_alive = true
	visible = true
	health.reset()
	attack.reset()
	
# --- Internal call-backs ---

func _on_died() -> void:
	set_alive.rpc(false)

func _on_attack_executed(data: Dictionary) -> void:
	var game = get_tree().root.get_node("Game")
	game.request_spawn_projectile.rpc_id(1, data)
