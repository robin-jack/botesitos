class_name PlayerNetcode
extends Node

const SEND_INTERVAL := 0.04  # 25 Hz

var _player_manager: PlayerManager
var _seq := 0
var _timer := 0.0

# pid -> {pos, vel, facing_dir, generation, seq}
var _remote_state: Dictionary = {}


func setup(player_manager: PlayerManager) -> void:
	_player_manager = player_manager


func _physics_process(delta: float) -> void:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return

	var local_id := multiplayer.get_unique_id()
	var local_player: Player = _player_manager.players.get(local_id)
	if is_instance_valid(local_player) and local_player.is_alive:
		_timer += delta
		if _timer >= SEND_INTERVAL:
			_timer -= SEND_INTERVAL
			_seq += 1
			if multiplayer.is_server():
				_relay_snapshot(
					local_id,
					local_player.spawn_generation,
					_seq,
					local_player.global_position,
					local_player.velocity,
					local_player.facing_dir
				)
			else:
				submit_movement_snapshot.rpc_id(
					1,
					local_id,
					local_player.spawn_generation,
					_seq,
					local_player.global_position,
					local_player.velocity,
					local_player.facing_dir
				)

	# Interpolate remote players
	for pid in _remote_state.keys():
		var state: Dictionary = _remote_state[pid]
		var player: Player = _player_manager.players.get(pid)
		if not is_instance_valid(player):
			_remote_state.erase(pid)
			continue
		if player.spawn_generation != state.generation:
			_remote_state.erase(pid)
			continue
		player.global_position = player.global_position.lerp(state.pos, 10.0 * delta)
		player.velocity = state.vel
		player.facing_dir = state.facing_dir


func _relay_snapshot(pid: int, generation: int, seq: int, pos: Vector2, vel: Vector2, facing: bool) -> void:
	var player: Player = _player_manager.players.get(pid)
	if not is_instance_valid(player) or not player.is_alive:
		return
	if player.spawn_generation != generation:
		return
	receive_movement_snapshot.rpc(pid, generation, seq, pos, vel, facing)


@rpc("any_peer", "call_local", "unreliable_ordered")
func submit_movement_snapshot(pid: int, generation: int, seq: int, pos: Vector2, vel: Vector2, facing: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != pid:
		return
	var player: Player = _player_manager.players.get(pid)
	if not is_instance_valid(player) or not player.is_alive:
		return
	if player.spawn_generation != generation:
		return
	receive_movement_snapshot.rpc(pid, generation, seq, pos, vel, facing)


@rpc("authority", "call_local", "unreliable_ordered")
func receive_movement_snapshot(pid: int, generation: int, seq: int, pos: Vector2, vel: Vector2, facing: bool) -> void:
	var local_id := multiplayer.get_unique_id()
	if pid == local_id:
		return
	var player: Player = _player_manager.players.get(pid)
	if not is_instance_valid(player):
		return
	if player.spawn_generation != generation:
		return
	_remote_state[pid] = {
		"pos": pos,
		"vel": vel,
		"facing_dir": facing,
		"generation": generation,
		"seq": seq,
	}
