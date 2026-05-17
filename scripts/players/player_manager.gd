class_name PlayerManager
extends Node

signal player_died(pid: int)

const MULTIPLAYER_CLIENT = preload("uid://c3iades372qie")

## peer_id -> MultiplayerClient (persistent for the network session)
var clients: Dictionary = {}

## peer_id -> Player (current character node; removed when dead)
var players: Dictionary = {}

## peer_id -> bool (connected status)
var _connected_peers: Dictionary = {}

var _players_container: Node2D
var _spawn_points: Array


func setup(players_container: Node2D, spawn_points: Array) -> void:
	_players_container = players_container
	_spawn_points = spawn_points


func _get_or_create_client(pid: int) -> MultiplayerClient:
	var client: MultiplayerClient = clients.get(pid)
	if not is_instance_valid(client):
		client = MULTIPLAYER_CLIENT.instantiate() as MultiplayerClient
		client.name = str(pid)
		_players_container.add_child(client)
		clients[pid] = client
		_connected_peers[pid] = true
		
		client.player_spawned.connect(func(p): _on_player_spawned(pid, p))
		client.player_despawned.connect(func(p): _on_player_despawned(pid, p))
	return client


func _on_player_spawned(pid: int, player: Player) -> void:
	players[pid] = player
	player.player_name = Lobby.clients.get(pid, {}).get("name", "Player %d" % pid)
	var hc := player.get_node_or_null("Health") as Health
	if hc:
		hc.died.connect(func(): _on_player_died(pid))


func _on_player_despawned(pid: int, _player: Player) -> void:
	players.erase(pid)


func spawn_warmup_player(pid: int, player_info: Dictionary) -> void:
	var client := _get_or_create_client(pid)
	if client.player_type != MultiplayerClient.PlayerType.NONE:
		return

	var sp: Node2D = _spawn_points[randi() % _spawn_points.size()]
	client.spawn_position = sp.global_position - _players_container.global_position
	client.player_type = MultiplayerClient.PlayerType.BOTINI


func spawn_round_players(player_infos: Dictionary, boss_peer_id: int, botinis_peer_ids: Array) -> void:
	clear_players()

	var botini_idx := 0
	for pid: int in player_infos:
		var is_boss := (pid == boss_peer_id)
		var client := _get_or_create_client(pid)

		var sp: Node2D
		if is_boss:
			sp = _spawn_points[randi() % _spawn_points.size()]
		else:
			sp = _spawn_points[botini_idx % _spawn_points.size()]
			botini_idx += 1
		client.spawn_position = sp.global_position - _players_container.global_position
		client.player_type = MultiplayerClient.PlayerType.BOSS if is_boss else MultiplayerClient.PlayerType.BOTINI


func respawn_warmup_player(pid: int) -> void:
	var player_info = Lobby.clients.get(pid)
	if not player_info:
		await despawn_eliminated_player(pid)
		return
	await despawn_eliminated_player(pid)
	spawn_warmup_player(pid, player_info)


func despawn_eliminated_player(pid: int) -> void:
	if not multiplayer.is_server():
		return

	var client: MultiplayerClient = clients.get(pid)
	if is_instance_valid(client):
		client.prepare_for_despawn.rpc()

	await get_tree().physics_frame

	if clients.has(pid):
		var c: MultiplayerClient = clients[pid]
		if is_instance_valid(c):
			c.player_type = MultiplayerClient.PlayerType.NONE


func mark_player_disconnected(pid: int) -> void:
	_connected_peers[pid] = false
	var player: CharacterBody2D = players.get(pid)
	if is_instance_valid(player):
		player.velocity = Vector2.ZERO


func mark_player_connected(pid: int) -> void:
	_connected_peers[pid] = true


func is_player_connected(pid: int) -> bool:
	return _connected_peers.get(pid, false)


func remove_player(pid: int) -> void:
	if not multiplayer.is_server():
		return

	if clients.has(pid):
		var client_node: MultiplayerClient = clients[pid]
		clients.erase(pid)
		if is_instance_valid(client_node):
			client_node.queue_free.call_deferred()

	players.erase(pid)
	_connected_peers.erase(pid)


func clear_players() -> void:
	if not multiplayer.is_server():
		return

	for pid: int in clients:
		var client: MultiplayerClient = clients[pid]
		if is_instance_valid(client):
			client.player_type = MultiplayerClient.PlayerType.NONE

	players.clear()
	# NOTE: _connected_peers and clients are intentionally NOT cleared here;
	# connection state and client containers survive round transitions.


func get_player(pid: int) -> CharacterBody2D:
	return players.get(pid)


func _on_player_died(pid: int) -> void:
	player_died.emit(pid)
