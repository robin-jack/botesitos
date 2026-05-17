extends Node

# Autoload named "Lobby"

signal player_connected(peer_id: int, player_info: Dictionary)
signal player_disconnected(peer_id: int)
signal server_disconnected
signal connection_failed

const PORT = 58008
const DEFAULT_SERVER_IP = "127.0.0.1"
const MAX_CONNECTIONS = 10

var player_info: Dictionary = {"name": "Botini"}

var clients: Dictionary = {}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func create_game() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(PORT, MAX_CONNECTIONS)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	clients[1] = player_info
	player_connected.emit(1, player_info)
	return OK


func join_game(address: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, PORT)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	return OK


func remove_multiplayer_peer() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	clients.clear()


# --- Multiplayer callbacks ---

## When a remote peer connects, tell them about ourselves.
func _on_peer_connected(id: int) -> void:
	_register_player.rpc_id(id, player_info)


## Each peer calls this on the newly connected peer; get_remote_sender_id()
## tells us who is registering.
@rpc("any_peer", "reliable")
func _register_player(new_player_info: Dictionary) -> void:
	var new_player_id := multiplayer.get_remote_sender_id()
	clients[new_player_id] = new_player_info
	player_connected.emit(new_player_id, new_player_info)


func _on_peer_disconnected(id: int) -> void:
	clients.erase(id)
	player_disconnected.emit(id)


## Called on the client when the connection to the server is confirmed.
func _on_connected_ok() -> void:
	var peer_id := multiplayer.get_unique_id()
	clients[peer_id] = player_info
	player_connected.emit(peer_id, player_info)


func _on_connected_fail() -> void:
	remove_multiplayer_peer()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	remove_multiplayer_peer()
	server_disconnected.emit()
