class_name MultiplayerClient
extends Node

@export var player: Player
@onready var synchronizer: MultiplayerSynchronizer = $MultiplayerSynchronizer
var peer_id: int

func _enter_tree() -> void:
	peer_id = int(name)
	set_multiplayer_authority(peer_id)


func set_player(new_player: Player) -> void:
	if is_instance_valid(player):
		player.queue_free()
		player = null

	if is_instance_valid(new_player):
		player = new_player
		add_child(player)
		if synchronizer:
			synchronizer.root_path = NodePath("../" + player.name)


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

	if synchronizer:
		synchronizer.public_visibility = false
