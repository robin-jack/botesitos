class_name MatchManager
extends Node

signal phase_changed(phase: int)
signal countdown_changed(seconds: int)
signal countdown_finished()
signal teams_changed(boss_peer_id: int, botinis_peer_ids: Array)
signal warmup_spawn_needed(pid: int)
signal round_setup_needed(boss_peer_id: int, botinis_peer_ids: Array)
signal warmup_respawn_needed(pid: int)
signal round_cleanup_needed()
signal projectiles_cleanup_needed()
signal match_over(scores: Dictionary)
signal warmup_returned()

enum Phase { WARMUP, COUNTDOWN, FIGHTING, ROUND_OVER, MATCH_OVER }
enum TEAM { BOTINI, BOTATO }

@export var round_start_countdown: float = 3.0
@export var round_end_delay: float = 2.5

var _phase: Phase = Phase.WARMUP
var _current_round: int = 0
var _countdown_timer: float = 0.0
var _round_end_timer: float = 0.0
var _match_over_timer: float = 0.0
var _last_countdown_sent: int = -1

var _match_in_progress: bool = false
var _boss_rotation: Array = []
var _player_scores: Dictionary = {}
var _warmup_respawn_timers: Dictionary = {}

var _players: Dictionary = {}
var _eliminated_peer_ids: Array[int] = []

var boss_peer_id: int = -1
var botinis_peer_ids: Array = []

var total_rounds: int:
	get:
		if _boss_rotation.size() > 0:
			return _boss_rotation.size()
		return _players.size()


func setup(players: Dictionary) -> void:
	_players = players


func get_phase() -> int:
	return _phase


func get_scores() -> Dictionary:
	return _player_scores.duplicate()


func is_match_in_progress() -> bool:
	return _match_in_progress


func can_spawn_joiner() -> bool:
	return _phase == Phase.WARMUP


func request_start_match(player_ids: Array) -> bool:
	if _phase != Phase.WARMUP:
		return false
	if player_ids.size() < 2:
		print("[Server] Need at least 2 players to start.")
		return false

	_boss_rotation = player_ids.duplicate()
	_boss_rotation.shuffle()

	_player_scores.clear()
	for pid: int in player_ids:
		_player_scores[pid] = 0

	_match_in_progress = true
	_current_round = 0
	_start_round()
	return true


func request_stop_match() -> void:
	if not _match_in_progress:
		return
	round_cleanup_needed.emit()
	projectiles_cleanup_needed.emit()
	_end_match()


func handle_player_disconnected(pid: int) -> void:
	if _match_in_progress:
		var idx := _boss_rotation.find(pid)
		if idx != -1 and idx >= _current_round:
			_boss_rotation.remove_at(idx)

		if _phase == Phase.FIGHTING:
			_check_round_end()


func handle_player_died(pid: int) -> void:
	if _phase == Phase.WARMUP:
		_warmup_respawn_timers[pid] = 2.0
	elif _phase == Phase.FIGHTING:
		if not pid in _eliminated_peer_ids:
			_eliminated_peer_ids.append(pid)
		_check_round_end()


func server_tick(delta: float) -> void:
	match _phase:
		Phase.WARMUP:
			_process_warmup_respawns(delta)

		Phase.COUNTDOWN:
			_countdown_timer -= delta
			var seconds := ceili(_countdown_timer)
			if seconds != _last_countdown_sent:
				_last_countdown_sent = seconds
				countdown_changed.emit(seconds)
			if _countdown_timer <= 0.0:
				_phase = Phase.FIGHTING
				phase_changed.emit(_phase)
				countdown_finished.emit()

		Phase.FIGHTING:
			_check_round_end()

		Phase.ROUND_OVER:
			_round_end_timer -= delta
			if _round_end_timer <= 0.0:
				round_cleanup_needed.emit()
				projectiles_cleanup_needed.emit()
				if _match_is_over():
					_end_match()
				else:
					_start_round()

		Phase.MATCH_OVER:
			_match_over_timer -= delta
			if _match_over_timer <= 0.0:
				_return_to_warmup()


func _process_warmup_respawns(delta: float) -> void:
	var done: Array[int] = []
	for pid: int in _warmup_respawn_timers:
		_warmup_respawn_timers[pid] -= delta
		if _warmup_respawn_timers[pid] <= 0.0:
			done.append(pid)
			warmup_respawn_needed.emit(pid)
	for pid: int in done:
		_warmup_respawn_timers.erase(pid)


func _start_round() -> void:
	_current_round += 1
	boss_peer_id = _boss_rotation[_current_round - 1]
	botinis_peer_ids = _boss_rotation.filter(func(id): return id != boss_peer_id)
	_eliminated_peer_ids.clear()

	_countdown_timer = round_start_countdown
	_last_countdown_sent = -1
	_phase = Phase.COUNTDOWN
	phase_changed.emit(_phase)
	round_setup_needed.emit(boss_peer_id, botinis_peer_ids.duplicate())
	teams_changed.emit(boss_peer_id, botinis_peer_ids.duplicate())


func _check_round_end() -> void:
	if _phase != Phase.FIGHTING:
		return
	var boss_alive := _is_boss_alive()
	var botinis_alive := _any_botini_alive()

	if not boss_alive and not botinis_alive:
		_award_round(TEAM.BOTINI)
	elif not boss_alive:
		_award_round(TEAM.BOTINI)
	elif not botinis_alive:
		_award_round(TEAM.BOTATO)


func _award_round(winner_team: int) -> void:
	_phase = Phase.ROUND_OVER
	_round_end_timer = round_end_delay
	phase_changed.emit(_phase)

	if winner_team == TEAM.BOTATO:
		if not boss_peer_id in _eliminated_peer_ids:
			_player_scores[boss_peer_id] += 2

		for pid: int in botinis_peer_ids:
			if pid in _eliminated_peer_ids:
				_player_scores[boss_peer_id] += 2
	else:
		for pid: int in botinis_peer_ids:
			if not pid in _eliminated_peer_ids:
				_player_scores[pid] += 7


func _is_boss_alive() -> bool:
	return not boss_peer_id in _eliminated_peer_ids


func _any_botini_alive() -> bool:
	for pid: int in botinis_peer_ids:
		if not pid in _eliminated_peer_ids:
			return true
	return false


func _match_is_over() -> bool:
	return _current_round >= _boss_rotation.size()


func _end_match() -> void:
	_phase = Phase.MATCH_OVER
	_match_over_timer = 5.0
	phase_changed.emit(_phase)
	match_over.emit(_player_scores.duplicate())


func _return_to_warmup() -> void:
	_boss_rotation.clear()
	_current_round = 0
	_player_scores.clear()
	_warmup_respawn_timers.clear()
	_eliminated_peer_ids.clear()
	_phase = Phase.WARMUP
	_match_in_progress = false
	phase_changed.emit(_phase)
	warmup_returned.emit()
