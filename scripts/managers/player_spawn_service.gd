class_name PlayerSpawnService
extends Node

signal player_died(peer_id: int)

const BOTINI_SCENE = preload("uid://cfxvxpnwen2eq")
const BOSS_SCENE = preload("uid://df6cjrmb84qw7")

var players: Dictionary = {} # peer_id -> character node

var _player_spawner: MultiplayerSpawner
var _players_container: Node2D
var _spawn_points: Array = []
var _registry: Node
var _combat_world: Node

func configure(player_spawner: MultiplayerSpawner, players_container: Node2D, spawn_points: Array, registry: Node, combat_world: Node) -> void:
	_player_spawner = player_spawner
	_players_container = players_container
	_spawn_points = spawn_points
	_registry = registry
	_combat_world = combat_world
	if _player_spawner:
		_player_spawner.spawn_function = Callable(self, "spawn_player_from_data")


func get_spawn_capacity() -> int:
	return _spawn_points.size()


func spawn_players(round_spawn_serial: int) -> void:
	if _registry == null or _player_spawner == null:
		return
	players.clear()
	var spawn_assignments: Dictionary = _build_spawn_assignments(_registry.active_peer_ids)
	for pid: int in _registry.active_peer_ids:
		if not spawn_assignments.has(pid):
			continue
		var is_boss: bool = pid == _registry.boss_peer_id
		var team: String = "boss" if is_boss else "botinis"
		var lobby_info = Lobby.players.get(pid, {})
		var player_name := str(lobby_info.get("name", "Player %d" % pid))
		var spawn_data: Dictionary = {
			"scene": "boss" if is_boss else "botini",
			"team": team,
			"peer_id": pid,
			"name": player_name,
			"spawn_position": spawn_assignments[pid],
			"spawn_serial": round_spawn_serial,
			"loadout": _get_default_loadout(team),
		}
		var player := _player_spawner.spawn(spawn_data) as CharacterBody2D
		if player:
			players[pid] = player
			var hc := player.get_node_or_null("Health") as Health
			if hc:
				var dead_pid := pid
				hc.died.connect(func(): player_died.emit(dead_pid))


func spawn_player_from_data(data: Dictionary) -> Node:
	var scene_key := str(data.get("scene", "botini"))
	var scene := BOSS_SCENE if scene_key == "boss" else BOTINI_SCENE
	var player := scene.instantiate() as CharacterBody2D
	var pid := int(data.get("peer_id", 1))
	var spawn_serial := int(data.get("spawn_serial", 0))
	player.name = "Player_%d_%d" % [spawn_serial, pid]
	player.team = str(data.get("team", "botinis"))
	player.peer_id = pid
	player.player_name = str(data.get("name", "Player"))
	player.global_position = data.get("spawn_position", Vector2.ZERO)
	player.velocity = Vector2.ZERO
	if player.has_method("apply_server_loadout"):
		player.apply_server_loadout(data.get("loadout", {}))
	return player


func cleanup_round() -> void:
	for pid in players.keys():
		var character := players[pid] as Node
		if character and character.has_method("prepare_for_despawn"):
			character.prepare_for_despawn.rpc()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if _players_container:
		for c in _players_container.get_children():
			c.queue_free()
	if _combat_world:
		_combat_world.cleanup_combat()
	players.clear()
	await get_tree().process_frame


func remove_peer(peer_id: int) -> void:
	var p := players.get(peer_id) as Node
	if p:
		p.queue_free()
		players.erase(peer_id)


func is_player_alive(peer_id: int) -> bool:
	var p := players.get(peer_id) as Node
	return p != null and p.get("is_alive") == true


func any_player_alive(peer_ids: Array) -> bool:
	for pid in peer_ids:
		if is_player_alive(int(pid)):
			return true
	return false


func _build_spawn_assignments(peer_ids: Array) -> Dictionary:
	var assignments := {}
	if _spawn_points.is_empty():
		return assignments
	var shuffled_spawns := _spawn_points.duplicate()
	shuffled_spawns.shuffle()
	var count: int = min(peer_ids.size(), shuffled_spawns.size())
	for i in range(count):
		var pid := int(peer_ids[i])
		var marker := shuffled_spawns[i] as Node2D
		assignments[pid] = marker.global_position
	return assignments


func _get_default_loadout(team: String) -> Dictionary:
	if team == "boss":
		return {
			"primary": {"ability": "laser_gun"},
			"secondary": {},
			"utility": {},
		}
	return {
		"primary": {"ability": "burst_gun"},
		"secondary": {},
		"utility": {},
	}
