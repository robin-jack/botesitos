extends CharacterBody2D

const EXPLOSION_SCENE = preload("uid://2f8twwxlgbxf")
const GRAVITY := 1280.0
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
var loadout: Dictionary = {}

@export var move_speed: float = 180.0
@export var jump_force: float = -448.0
@export var gravity_scale: float = 1.0

var _jump_req: bool = false
var _dash_req: bool = false
var _prm_req: bool = false
var _sec_req: bool = false
var _input_dir: float = 0.0
var _ability_sequence: int = 0
var coyote_timer: float = 0.0

var _abilities_by_slot: Dictionary = {}

@onready var sprite: Sprite2D = $Sprite
@onready var health: Health = $Health
@onready var dash: Dash = $Dash
@onready var ability_slots: Node = $AbilitySlots

func _enter_tree() -> void:
	var pid := _extract_peer_id_from_name(name)
	if pid > 0:
		peer_id = pid
		set_multiplayer_authority(peer_id)


func _ready() -> void:
	health.died.connect(_on_died)
	_register_abilities()
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

func apply_server_loadout(server_loadout: Dictionary) -> void:
	loadout = server_loadout.duplicate(true)

func _register_abilities() -> void:
	_abilities_by_slot.clear()
	if ability_slots == null:
		return
	for slot_node in ability_slots.get_children():
		var ability := slot_node
		if not ability.has_method("client_try_execute") or not ability.has_method("server_try_execute"):
			continue
		var normalized_slot := str(slot_node.name).to_lower()
		ability.slot_id = normalized_slot
		_abilities_by_slot[normalized_slot] = ability


func _gather_input() -> void:
	_input_dir = Input.get_axis("ui_left", "ui_right")
	_jump_req = Input.is_action_just_pressed("ui_up")
	_dash_req = Input.is_action_just_pressed("ui_accept")
	_prm_req = Input.is_action_just_pressed("primary")
	_sec_req = Input.is_action_just_pressed("secondary")


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
		dash.try_dash(dir, is_on_floor(), velocity.y)
	_dash_req = false
	if dash.is_dashing:
		velocity = dash.apply_dash_velocity(velocity)


func _handle_movement(delta: float) -> void:
	if dash.is_dashing:
		return
	var speed := move_speed
	velocity.x = move_toward(velocity.x, _input_dir * speed, speed * delta * 12.0)


func _handle_attack() -> void:
	if _prm_req:
		_try_ability("primary", {
			"direction": Vector2(1.0 if facing_right else -1.0, 0.0),
		})
		_prm_req = false
		
	if _sec_req:
		_try_ability("secondary", {
			"direction": Vector2(1.0 if facing_right else -1.0, 0.0),
		})
		_sec_req = false


func _try_ability(slot_id: String, input_data: Dictionary) -> void:
	var ability = _abilities_by_slot.get(slot_id)
	if ability == null:
		return
	_ability_sequence += 1
	var sequence := _ability_sequence
	if not ability.client_try_execute(input_data, self, sequence):
		return

	var context = _get_combat_context()
	if multiplayer.is_server():
		var response: Dictionary = ability.server_try_execute(input_data, self, context, sequence)
		if bool(response.get("accepted", false)):
			ability_accepted(slot_id, sequence, response.get("state", {}))
		else:
			ability_rejected(slot_id, sequence, response.get("state", {}))
	else:
		request_ability.rpc_id(1, slot_id, input_data, sequence)


@rpc("any_peer", "reliable")
func request_ability(slot_id: String, input_data: Dictionary, client_sequence: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != peer_id:
		return
	if not is_alive:
		return

	var ability = _abilities_by_slot.get(slot_id)
	var context = _get_combat_context()
	var response: Dictionary = {"accepted": false, "state": {}}
	if ability != null:
		response = ability.server_try_execute(input_data, self, context, client_sequence)

	if bool(response.get("accepted", false)):
		ability_accepted.rpc_id(sender_id, slot_id, client_sequence, response.get("state", {}))
	else:
		ability_rejected.rpc_id(sender_id, slot_id, client_sequence, response.get("state", {}))


@rpc("any_peer", "call_local", "reliable")
func ability_accepted(slot_id: String, _client_sequence: int, state: Dictionary) -> void:
	if not _is_server_rpc_sender():
		return
	var ability = _abilities_by_slot.get(slot_id)
	if ability:
		ability.client_apply_state(state)


@rpc("any_peer", "call_local", "reliable")
func ability_rejected(slot_id: String, _client_sequence: int, state: Dictionary) -> void:
	if not _is_server_rpc_sender():
		return
	var ability = _abilities_by_slot.get(slot_id)
	if ability:
		ability.client_apply_state(state)


func _get_combat_context():
	var game = get_tree().root.get_node_or_null("Game")
	if game and game.has_method("get_combat_world"):
		return game.get_combat_world()
	return null


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


@rpc("any_peer", "call_local", "reliable")
func apply_damage_feedback(hit_direction: Vector2, knockback: float, alive_after_hit: bool) -> void:
	if not _is_server_rpc_sender():
		return
	if is_multiplayer_authority() and alive_after_hit:
		velocity += hit_direction.normalized() * knockback
	_play_damage_effects(hit_direction)


@rpc("any_peer", "call_local", "reliable")
func set_alive(alive: bool) -> void:
	if not _is_server_rpc_sender():
		return
	is_alive = alive
	visible = alive
	if not alive:
		velocity = Vector2.ZERO


@rpc("any_peer", "call_local", "reliable")
func respawn(pos: Vector2) -> void:
	if not _is_server_rpc_sender():
		return
	global_position = pos
	velocity = Vector2.ZERO
	is_alive = true
	visible = true
	health.reset()
	for ability in _abilities_by_slot.values():
		if ability and ability.has_method("reset"):
			ability.reset()


@rpc("any_peer", "call_local", "reliable")
func prepare_for_despawn() -> void:
	if not _is_server_rpc_sender():
		return
	is_alive = false
	visible = false
	velocity = Vector2.ZERO
	set_physics_process(false)

	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision:
		collision.disabled = true
	var sync := get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync:
		sync.public_visibility = false


func _play_damage_effects(hit_direction: Vector2) -> void:
	#var explosion = EXPLOSION_SCENE.instantiate()
	#var offset = -hit_direction.normalized() * 8.0
	#explosion.global_position = global_position + offset
	#var game = get_tree().root.get_node_or_null("Game")
	#if game:
		#game.add_child(explosion)

	var tween = create_tween()
	for _i in range(3):
		tween.tween_property(sprite, "modulate", Color.RED, 0.07)
		tween.tween_property(sprite, "modulate", Color.WHITE, 0.07)


func _on_died() -> void:
	if multiplayer.is_server():
		set_alive.rpc(false)


func _is_server_rpc_sender() -> bool:
	var sender := multiplayer.get_remote_sender_id()
	return sender == 0 or sender == 1


func _extract_peer_id_from_name(node_name: String) -> int:
	if node_name.begins_with("Player_"):
		var parts := node_name.split("_")
		if not parts.is_empty():
			var maybe_id := parts[parts.size() - 1]
			if maybe_id.is_valid_int():
				return maybe_id.to_int()
	return -1
