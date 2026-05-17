class_name MultiplayerClient
extends Node

signal player_spawned(player: Player)
signal player_despawned(player: Player)

const BOTINI_SCENE = preload("uid://cfxvxpnwen2eq")
const BOSS_SCENE   = preload("uid://df6cjrmb84qw7")

enum PlayerType { NONE, BOTINI, BOSS }

@export var player: Player:
	set(value):
		if player == value:
			return
		if is_instance_valid(player):
			remove_child(player)
			player_despawned.emit(player)
			player.queue_free()
		player = value
		if is_instance_valid(player):
			add_child.call_deferred(player)
			player_spawned.emit(player)

@export var player_type: PlayerType = PlayerType.NONE:
	set(value):
		if player_type == value:
			return
		player_type = value
		_update_player_scene()

@export var spawn_position: Vector2 = Vector2.ZERO

var SyncPos: Vector2
var facing_dir: bool
var is_alive: bool = true

@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
var peer_id: int

func _enter_tree() -> void:
	peer_id = int(name)
	set_multiplayer_authority(peer_id)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if is_multiplayer_authority():
		SyncPos = player.global_position
		facing_dir = player.facing_dir
		is_alive = player.is_alive
	else:
		player.global_position = player.global_position.lerp(SyncPos, 10 * delta)
		player.facing_dir = facing_dir
		player.is_alive = is_alive

func _update_player_scene() -> void:
	match player_type:
		PlayerType.NONE:
			self.player = null
		PlayerType.BOTINI:
			var p = BOTINI_SCENE.instantiate() as Player
			p.name = "Player"
			p.position = spawn_position
			self.player = p
		PlayerType.BOSS:
			var p = BOSS_SCENE.instantiate() as Player
			p.name = "Player"
			p.position = spawn_position
			self.player = p

@rpc("authority", "call_local", "reliable")
func configure_player(type: PlayerType, pos: Vector2) -> void:
	spawn_position = pos
	player_type = type

@rpc("any_peer", "call_local", "reliable")
func receive_damage(amount: int, direction: Vector2, knockback: float) -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if not is_instance_valid(player) or not player.is_alive:
		return
	player.apply_damage(amount, direction, knockback, is_multiplayer_authority())

@rpc("any_peer", "call_local", "reliable")
func prepare_for_despawn() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	if is_instance_valid(player):
		player.is_alive = false
		player.velocity = Vector2.ZERO
		player.set_physics_process(false)
		if player.camera:
			player.camera.enabled = false
