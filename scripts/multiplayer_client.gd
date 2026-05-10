extends Node

func _enter_tree() -> void:
	var peer_id: int = str(name).to_int()
	set_multiplayer_authority(peer_id)
