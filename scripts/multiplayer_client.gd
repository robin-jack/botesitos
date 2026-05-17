class_name MultiplayerClient
extends Node

@export var player: Player
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
var peer_id: int

func _enter_tree() -> void:
	peer_id = int(name)
	set_multiplayer_authority(peer_id)


@rpc("any_peer", "call_local", "reliable")
func prepare_for_despawn() -> void:
	if multiplayer.get_remote_sender_id() != 1:
		return
	player.is_alive = false
	player.velocity = Vector2.ZERO
	player.set_physics_process(false)
	if player.camera:
		player.camera.enabled = false
	
	synchronizer.public_visibility = false
