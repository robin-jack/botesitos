class_name MatchController
extends Node

const LOBBY_SCENE_PATH = "res://scenes/lobby/lobby.tscn"

enum Phase { WAITING, COUNTDOWN, FIGHTING, ROUND_OVER, GAME_OVER }

@export var total_rounds: int = 5
@export var round_start_countdown: float = 3.0
@export var round_end_delay: float = 2.5

var _phase: Phase = Phase.WAITING
var _current_round: int = 0
var _boss_wins: int = 0
var _botinis_wins: int = 0
var _countdown_timer: float = 0.0
var _round_end_timer: float = 0.0
var _last_countdown_sent: int = -1
var _round_spawn_serial: int = 0

var _registry: Node
var _spawn_service: Node
var _countdown_label: Label

func configure(registry: Node, spawn_service: Node, countdown_label: Label) -> void:
	_registry = registry
	_spawn_service = spawn_service
	_countdown_label = countdown_label
	if _spawn_service:
		_spawn_service.player_died.connect(_on_player_died)
	if _countdown_label:
		_countdown_label.visible = false


func start_game() -> void:
	if not multiplayer.is_server():
		return
	if _phase != Phase.WAITING:
		return
	_registry.reset_for_series(Lobby.players.keys())
	_boss_wins = 0
	_botinis_wins = 0
	_current_round = 0
	_start_round()


func on_peer_loaded_during_match(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_registry.register_loaded_peer_during_match(peer_id)
	if _phase == Phase.WAITING and _registry.total_known_players() >= 2:
		_start_round()


func on_player_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_registry.remove_peer(peer_id)
	_spawn_service.remove_peer(peer_id)
	_check_round_end()


func can_use_abilities() -> bool:
	return _phase == Phase.FIGHTING


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	match _phase:
		Phase.COUNTDOWN:
			_countdown_timer -= delta
			var seconds := ceili(_countdown_timer)
			if seconds != _last_countdown_sent:
				_last_countdown_sent = seconds
				_rpc_countdown.rpc(seconds)
			if _countdown_timer <= 0.0:
				_phase = Phase.FIGHTING
				_rpc_hide_countdown.rpc()

		Phase.FIGHTING:
			_check_round_end()

		Phase.ROUND_OVER:
			_round_end_timer -= delta
			if _round_end_timer <= 0.0:
				_phase = Phase.WAITING
				call_deferred("_finish_round_transition")


func _finish_round_transition() -> void:
	await _spawn_service.cleanup_round()
	if _series_decided():
		_phase = Phase.GAME_OVER
		_rpc_show_winner.rpc(_get_series_winner())
		await get_tree().create_timer(2.5).timeout
		Lobby.load_game.rpc(LOBBY_SCENE_PATH)
		return
	_start_round()


func _start_round() -> void:
	_registry.promote_spectators_for_next_round(Lobby.players.keys())
	_registry.enforce_capacity(_spawn_service.get_spawn_capacity())
	if _registry.active_peer_ids.size() < 2:
		_phase = Phase.WAITING
		if _countdown_label:
			_countdown_label.text = "Waiting for players"
			_countdown_label.visible = true
		return

	if _countdown_label:
		_countdown_label.visible = false
	_round_spawn_serial += 1
	_current_round += 1
	_registry.assign_teams()
	_spawn_service.spawn_players(_round_spawn_serial)
	_countdown_timer = round_start_countdown
	_last_countdown_sent = -1
	_phase = Phase.COUNTDOWN


func _check_round_end() -> void:
	if _phase != Phase.FIGHTING:
		return
	var boss_alive: bool = _spawn_service.is_player_alive(_registry.boss_peer_id)
	var botinis_alive: bool = _spawn_service.any_player_alive(_registry.botinis_peer_ids)
	if not boss_alive and not botinis_alive:
		_award_round("botinis")
	elif not boss_alive:
		_award_round("botinis")
	elif not botinis_alive:
		_award_round("boss")


func _award_round(winner: String) -> void:
	if winner == "boss":
		_boss_wins += 1
	else:
		_botinis_wins += 1
	_phase = Phase.ROUND_OVER
	_round_end_timer = round_end_delay


func _series_decided() -> bool:
	var needed := ceili(total_rounds / 2.0)
	return _boss_wins >= needed or _botinis_wins >= needed


func _get_series_winner() -> String:
	return "boss" if _boss_wins > _botinis_wins else "botinis"


func _on_player_died(_pid: int) -> void:
	_check_round_end()


@rpc("authority", "call_local", "reliable")
func _rpc_countdown(seconds: int) -> void:
	if _countdown_label == null:
		return
	_countdown_label.text = "FIGHT!" if seconds <= 0 else str(seconds)
	_countdown_label.visible = true


@rpc("authority", "call_local", "reliable")
func _rpc_hide_countdown() -> void:
	if _countdown_label:
		_countdown_label.visible = false


@rpc("authority", "call_local", "reliable")
func _rpc_show_winner(winner: String) -> void:
	if _countdown_label == null:
		return
	_countdown_label.text = "%s win!" % winner.capitalize()
	_countdown_label.visible = true
