class_name PlayerManager
extends Node

signal player_died(pid: int)

const BOTINI_SCENE = preload("uid://cfxvxpnwen2eq")
const BOSS_SCENE   = preload("uid://df6cjrmb84qw7")

## peer_id -> character node
var players: Dictionary = {}

## peer_id -> bool (connected status)
var _connected_peers: Dictionary = {}

var _players_container: Node2D
var _spawn_points: Array


func setup(players_container: Node2D, spawn_points: Array) -> void:
	_players_container = players_container
	_spawn_points = spawn_points


func spawn_warmup_player(pid: int, player_info: Dictionary) -> void:
	if players.has(pid):
		return

	var player := BOTINI_SCENE.instantiate() as CharacterBody2D
	player.peer_id     = pid
	player.team        = pid
	player.player_name = player_info.get("name", "Player %d" % pid)
	player.name        = str(pid)

	players[pid] = player
	_connected_peers[pid] = true
	var sp: Node2D = _spawn_points[randi() % _spawn_points.size()]
	player.position = sp.global_position - _players_container.global_position
	_players_container.add_child(player)

	var hc := player.get_node_or_null("Health") as Health
	if hc:
		hc.died.connect(func(): _on_player_died(pid))


func spawn_round_players(player_infos: Dictionary, boss_peer_id: int, botinis_peer_ids: Array) -> void:
	clear_players()

	var botini_idx := 0
	for pid: int in player_infos:
		var is_boss := (pid == boss_peer_id)
		var player: Player

		if is_boss:
			player              = BOSS_SCENE.instantiate()
			player.peer_id      = pid
			player.player_name  = player_infos[pid].get("name", "Botato %d" % pid)
		else:
			player              = BOTINI_SCENE.instantiate()
			player.peer_id      = pid
			player.player_name  = player_infos[pid].get("name", "Botini %d" % pid)

		player.name = str(pid)
		var sp: Node2D
		if is_boss:
			sp = _spawn_points[randi() % _spawn_points.size()]
		else:
			sp = _spawn_points[botini_idx % _spawn_points.size()]
			botini_idx += 1
		player.position = sp.global_position - _players_container.global_position
		_players_container.add_child(player, true)
		players[pid] = player
		_connected_peers[pid] = true

		player.health.died.connect(func(): _on_player_died(pid))


func respawn_warmup_player(pid: int) -> void:
	var player_info = Lobby.players.get(pid)
	if not player_info:
		despawn_eliminated_player(pid)
		return
	despawn_eliminated_player(pid)
	spawn_warmup_player(pid, player_info)


func despawn_eliminated_player(pid: int) -> void:
	if not multiplayer.is_server():
		return
	if players.has(pid):
		var player_node: CharacterBody2D = players[pid]
		players.erase(pid)
		if is_instance_valid(player_node):
			player_node.queue_free.call_deferred()


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
	if players.has(pid):
		var player_node: CharacterBody2D = players[pid]
		players.erase(pid)
		if is_instance_valid(player_node):
			player_node.queue_free()
	_connected_peers.erase(pid)


func clear_players() -> void:
	if not multiplayer.is_server():
		return
	for c in _players_container.get_children():
		c.queue_free()
	players.clear()
	# NOTE: _connected_peers is intentionally NOT cleared here;
	# connection state survives round transitions.


func get_player(pid: int) -> CharacterBody2D:
	return players.get(pid)


func _on_player_died(pid: int) -> void:
	player_died.emit(pid)
