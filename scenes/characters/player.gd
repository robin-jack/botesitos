extends CharacterBody2D

signal died(is_boss)

const BOTATO = preload("uid://b1526uv1pxisa")
const BOTINI = preload("uid://bxg5056857nvd")
const EXPLOSION_SCENE = preload("uid://2f8twwxlgbxf")

const BOSS_SPEED = 130.0
const BOSS_JUMP = -300.0
const BOSS_HEALTH = 5
const BOSS_ATTACK_DELAY = 1.0

const COYOTE_TIME_MAX: float = 0.1 # How many seconds you can jump after falling

var speed = 180.0
var jump_velocity = -310.0
var max_health = 1
var current_health = 1
var dash_cooldown = 2
var attack_cooldown = 0.5
var is_dashing: bool = false

var is_boss_character: bool = false 
var is_initialized: bool = false # Freezes physics until we are synced
var is_dead: bool = false # Add this to prevent double-deaths!

@export var sync_facing_dir: float = 1.0 :
	set(value):
		sync_facing_dir = value
		if is_inside_tree() and visuals:
			visuals.scale.x = value * abs(visuals.scale.x)

var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
var can_dash = true
var can_attack = true
var coyote_timer: float = 0.0

@onready var visuals = $Visuals
@onready var collision = $CollisionShape2D
@onready var dash_timer = $DashTimer
@onready var attack_timer = $AttackTimer

func _enter_tree():
	set_multiplayer_authority(name.to_int())

# Called by server before adding to tree
func setup(is_boss: bool):
	is_boss_character = is_boss
	if is_boss:
		speed = BOSS_SPEED
		jump_velocity = BOSS_JUMP
		max_health = BOSS_HEALTH
	current_health = max_health

func _ready():
	dash_timer.timeout.connect(func(): can_dash = true)
	attack_timer.timeout.connect(func(): can_attack = true)

	if multiplayer.is_server():
		apply_visuals()
		is_initialized = true # Server starts immediately
	else:
		# Client spawns frozen, asks the server for the correct spawn pos and stats
		request_setup.rpc_id(1)

func apply_visuals():
	if is_boss_character:
		var boss_shape = CapsuleShape2D.new()
		boss_shape.height = 24
		boss_shape.radius = 10
		collision.shape = boss_shape
		visuals.texture = BOTATO
	else:
		visuals.texture = BOTINI

# Client asks Server (Peer 1) for data
@rpc("any_peer", "reliable")
func request_setup():
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	# Server replies exclusively to the client who asked
	receive_setup.rpc_id(sender_id, is_boss_character, global_position)

# Client receives data from Server
@rpc("any_peer", "reliable")
func receive_setup(is_boss: bool, pos: Vector2):
	if multiplayer.get_remote_sender_id() != 1: return # Only trust the server
	global_position = pos # Snap to correct position above the floor!
	setup(is_boss)
	apply_visuals()
	is_initialized = true # Data received, unfreeze physics!

func _physics_process(delta):
	if not is_initialized or not is_multiplayer_authority():
		return

	if is_dashing:
		move_and_slide()
		return

	# --- COYOTE TIME & GRAVITY ---
	if is_on_floor():
		coyote_timer = COYOTE_TIME_MAX # Reset the timer as long as we are on the ground
	else:
		coyote_timer -= delta # Count down when we are in the air
		velocity.y += gravity * delta # Add gravity

	# --- HANDLE JUMP ---
	# We now check the timer instead of is_on_floor()
	if Input.is_action_just_pressed("ui_up") and coyote_timer > 0.0:
		velocity.y = jump_velocity
		coyote_timer = 0.0 # CRITICAL: Reset to 0 immediately so we can't double jump in the air!

	var direction = Input.get_axis("ui_left", "ui_right")
	if direction:
		velocity.x = direction * speed
		sync_facing_dir = sign(direction)
	else:
		velocity.x = move_toward(velocity.x, 0, speed)

	if Input.is_action_just_pressed("ui_accept") and can_dash and not is_boss_character:
		dash(direction)

	if Input.is_action_just_pressed("attack") and can_attack:
		perform_attack()

	move_and_slide()

func dash(direction: float):
	can_dash = false
	is_dashing = true
	var dash_dir = direction if direction != 0 else sync_facing_dir
	
	velocity.x = dash_dir * speed * 3.0 # A strong, sustained burst
	velocity.y = 0 # Optional: prevents falling while dashing
	
	# Wait for the dash to finish, then restore control
	await get_tree().create_timer(0.2).timeout 
	is_dashing = false
	
	dash_timer.start(dash_cooldown)

func perform_attack():
	can_attack = false
	var facing_dir = sign(visuals.scale.x)
	
	if is_boss_character:
		attack_timer.start(BOSS_ATTACK_DELAY)
		_rpc_play_attack_animation.rpc(true)
		await get_tree().create_timer(BOSS_ATTACK_DELAY).timeout
		fire_projectile.rpc_id(1, facing_dir, true)
	else:
		attack_timer.start(attack_cooldown)
		_rpc_play_attack_animation.rpc(false)
		fire_projectile.rpc_id(1, facing_dir, false)

@rpc("call_local", "reliable")
func _rpc_play_attack_animation(is_boss: bool):
	pass

@rpc("any_peer", "call_local", "reliable")
func fire_projectile(direction: float, is_boss_attack: bool):
	if not multiplayer.is_server(): return
	
	# Ask the Game node to handle the secure server-side spawning
	var game = get_node("/root/Game")
	game.spawn_projectile(name.to_int(), is_boss_attack, global_position, direction)

@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, hit_dir: float = 0.0):
	# If we are already dead, ignore further damage so we don't emit the died signal twice
	if not multiplayer.is_server() or is_dead: return
	
	current_health -= amount
	
	# Send the explosion RPC
	_rpc_play_damage_effects.rpc(hit_dir)
	
	if current_health <= 0:
		is_dead = true
		died.emit(is_boss_character)
		
		# CRITICAL: Wait one frame before deleting!
		# This guarantees the RPC packet above is sent before the node is destroyed.
		await get_tree().physics_frame 
		queue_free()

# We added "any_peer" here so the Server is allowed to call this on the Client's node
@rpc("any_peer", "call_local", "reliable")
func _rpc_play_damage_effects(hit_dir: float):
	# Spawn the Explosion
	var explosion = EXPLOSION_SCENE.instantiate()
	
	var offset_x = -hit_dir * 5.0
	var offset_y = randf_range(-2.0, 2.0)
	
	explosion.global_position = global_position + Vector2(offset_x, offset_y)
	get_node("/root/Game").add_child(explosion) 
	
	# Flash Red Rapidly
	var tween = create_tween()
	for i in range(3):
		tween.tween_property(visuals, "modulate", Color.RED, 0.05)
		tween.tween_property(visuals, "modulate", Color.WHITE, 0.05)
