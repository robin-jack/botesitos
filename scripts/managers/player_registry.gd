class_name PlayerRegistry
extends Node

var boss_peer_id: int = -1
var botinis_peer_ids: Array = []
var active_peer_ids: Array = []
var spectator_peer_ids: Array = []

var _used_boss_peers: Array = []

func reset_for_series(peer_ids: Array) -> void:
	active_peer_ids = peer_ids.duplicate()
	spectator_peer_ids.clear()
	botinis_peer_ids.clear()
	boss_peer_id = -1
	_used_boss_peers.clear()
	_rpc_set_spectators.rpc(spectator_peer_ids)


func register_loaded_peer_during_match(peer_id: int) -> void:
	if active_peer_ids.has(peer_id) or spectator_peer_ids.has(peer_id):
		return
	spectator_peer_ids.append(peer_id)
	_rpc_set_spectators.rpc(spectator_peer_ids)


func promote_spectators_for_next_round(lobby_peer_ids: Array) -> void:
	for pid in lobby_peer_ids:
		if not active_peer_ids.has(pid) and not spectator_peer_ids.has(pid):
			spectator_peer_ids.append(pid)
	for pid in spectator_peer_ids:
		if not active_peer_ids.has(pid):
			active_peer_ids.append(pid)
	spectator_peer_ids.clear()
	_rpc_set_spectators.rpc(spectator_peer_ids)


func enforce_capacity(capacity: int) -> void:
	if capacity <= 0:
		return
	while active_peer_ids.size() > capacity:
		var overflow_id := int(active_peer_ids.pop_back())
		if not spectator_peer_ids.has(overflow_id):
			spectator_peer_ids.append(overflow_id)
	if not spectator_peer_ids.is_empty():
		_rpc_set_spectators.rpc(spectator_peer_ids)


func assign_teams() -> void:
	var all_ids: Array = active_peer_ids.duplicate()
	if all_ids.is_empty():
		return
	var pool := all_ids.filter(func(id): return int(id) not in _used_boss_peers)
	if pool.is_empty():
		_used_boss_peers.clear()
		pool = all_ids.duplicate()
	pool.shuffle()
	boss_peer_id = int(pool[0])
	botinis_peer_ids = all_ids.filter(func(id): return int(id) != boss_peer_id)
	_used_boss_peers.append(boss_peer_id)
	_rpc_set_teams.rpc(boss_peer_id, botinis_peer_ids)


func remove_peer(peer_id: int) -> void:
	active_peer_ids.erase(peer_id)
	spectator_peer_ids.erase(peer_id)
	botinis_peer_ids.erase(peer_id)
	if boss_peer_id == peer_id:
		boss_peer_id = -1
	_rpc_set_spectators.rpc(spectator_peer_ids)
	_rpc_set_teams.rpc(boss_peer_id, botinis_peer_ids)


func total_known_players() -> int:
	return active_peer_ids.size() + spectator_peer_ids.size()


@rpc("authority", "call_local", "reliable")
func _rpc_set_teams(b_peer: int, botinis_peers: Array) -> void:
	boss_peer_id = b_peer
	botinis_peer_ids = botinis_peers


@rpc("authority", "call_local", "reliable")
func _rpc_set_spectators(peer_ids: Array) -> void:
	spectator_peer_ids = peer_ids
