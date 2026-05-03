extends Node

# Autoload named Lobby

signal player_connected(peer_id, player_info)
signal player_disconnected(peer_id)
signal server_disconnected

const PORT = 58008
const DEFAULT_SERVER_IP = "127.0.0.1"
const MAX_CONNECTIONS = 10
const GAME_SCENE_PATH = "res://scenes/game/game.tscn"
const LOBBY_SCENE_PATH = "res://scenes/lobby/lobby.tscn"
const MAX_NAME_LENGTH = 16

var players = {}
var player_info = {"name": "Name"}
var _loaded_peers := {}
var _pending_loaded_peers := {}
var game_in_progress: bool = false
var current_scene_path: String = LOBBY_SCENE_PATH

func _ready():
	multiplayer.peer_connected.connect(_on_player_connected)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func join_game(address = ""):
	if address.is_empty():
		address = DEFAULT_SERVER_IP
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, PORT)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	return OK

func create_game():
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_CONNECTIONS)
	if error != OK:
		return error
	multiplayer.multiplayer_peer = peer
	var host_info := _sanitize_player_info(player_info)
	player_info = host_info.duplicate(true)
	players[1] = host_info
	player_connected.emit(1, host_info)
	return OK

func remove_multiplayer_peer():
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players.clear()
	_loaded_peers.clear()
	_pending_loaded_peers.clear()
	game_in_progress = false
	current_scene_path = LOBBY_SCENE_PATH

@rpc("call_local", "reliable")
func load_game(game_scene_path):
	current_scene_path = game_scene_path
	game_in_progress = false
	_loaded_peers.clear()
	_pending_loaded_peers.clear()
	get_tree().change_scene_to_file(game_scene_path)

@rpc("any_peer", "reliable")
func player_loaded():
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_mark_peer_loaded(sender_id)

func player_loaded_local() -> void:
	if not multiplayer.is_server():
		return
	_mark_peer_loaded(1)

func _mark_peer_loaded(peer_id: int) -> void:
	if peer_id <= 0:
		return
	if not players.has(peer_id):
		_pending_loaded_peers[peer_id] = true
		return
	if _loaded_peers.has(peer_id):
		return
	_loaded_peers[peer_id] = true

	var game := get_tree().root.get_node_or_null("Game")
	if game_in_progress and game and game.has_method("on_peer_loaded_during_match"):
		game.on_peer_loaded_during_match(peer_id)
		return
	if game and _loaded_peers.size() >= players.size():
		game.start_game()
		game_in_progress = true
		_loaded_peers.clear()

func _on_player_connected(id: int):
	if multiplayer.is_server() and game_in_progress and current_scene_path == GAME_SCENE_PATH:
		load_game.rpc_id(id, current_scene_path)
	_register_player.rpc_id(id, player_info)

@rpc("any_peer", "reliable")
func _register_player(new_player_info: Dictionary):
	var new_player_id = multiplayer.get_remote_sender_id()
	if new_player_id <= 0:
		return
	var safe_info := _sanitize_player_info(new_player_info)
	if multiplayer.is_server():
		players[new_player_id] = safe_info
		player_connected.emit(new_player_id, safe_info)
		if _pending_loaded_peers.has(new_player_id):
			_pending_loaded_peers.erase(new_player_id)
			_mark_peer_loaded(new_player_id)
	else:
		players[new_player_id] = safe_info
		player_connected.emit(new_player_id, safe_info)

func _on_player_disconnected(id: int):
	players.erase(id)
	_loaded_peers.erase(id)
	_pending_loaded_peers.erase(id)
	player_disconnected.emit(id)

func _on_connected_ok():
	var peer_id = multiplayer.get_unique_id()
	var safe_info := _sanitize_player_info(player_info)
	player_info = safe_info.duplicate(true)
	players[peer_id] = safe_info
	player_connected.emit(peer_id, safe_info)

func _on_connected_fail():
	remove_multiplayer_peer()

func _on_server_disconnected():
	remove_multiplayer_peer()
	players.clear()
	server_disconnected.emit()

func _sanitize_player_info(info: Dictionary) -> Dictionary:
	var raw_name := str(info.get("name", "Player")).strip_edges()
	if raw_name.is_empty():
		raw_name = "Player"
	if raw_name.length() > MAX_NAME_LENGTH:
		raw_name = raw_name.substr(0, MAX_NAME_LENGTH)
	return {"name": raw_name}
