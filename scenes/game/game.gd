extends Node2D

const BOTINI_SCENE = preload("uid://cfxvxpnwen2eq")
const BOSS_SCENE = preload("uid://df6cjrmb84qw7")
const BULLET_SCENE = preload("uid://b8mmf48321hp")
const LASER_SCENE = preload("uid://by5n3jobbje87")
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
var _used_boss_peers: Array = []
var _last_server_shot_msec: Dictionary = {}

var players: Dictionary = {} # peer_id -> character node
var boss_peer_id: int = -1
var botinis_peer_ids: Array = []
var active_peer_ids: Array = []
var spectator_peer_ids: Array = []

@onready var players_container: Node2D = $Players
@onready var projectiles_container: Node2D = $Projectiles
@onready var spawn_points: Array = $SpawnPoints.get_children()
@onready var _countdown_label: Label = $CountdownLabel
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _projectile_spawner: MultiplayerSpawner = $ProjectileSpawner

func _ready() -> void:
	_countdown_label.visible = false
	_player_spawner.spawn_function = Callable(self, "_spawn_player_from_data")
	_projectile_spawner.spawn_function = Callable(self, "_spawn_projectile_from_data")
	Lobby.player_disconnected.connect(_on_lobby_player_disconnected)
	if multiplayer.is_server():
		Lobby.player_loaded_local()
	else:
		Lobby.player_loaded.rpc_id(1)

func start_game() -> void:
	if not multiplayer.is_server():
		return
	if _phase != Phase.WAITING:
		return
	active_peer_ids = Lobby.players.keys().duplicate()
	spectator_peer_ids.clear()
	_used_boss_peers.clear()
	_last_server_shot_msec.clear()
	_boss_wins = 0
	_botinis_wins = 0
	_current_round = 0
	_start_round()

func on_peer_loaded_during_match(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if active_peer_ids.has(peer_id) or spectator_peer_ids.has(peer_id):
		return
	spectator_peer_ids.append(peer_id)
	_rpc_set_spectators.rpc(spectator_peer_ids)
	if _phase == Phase.WAITING and (active_peer_ids.size() + spectator_peer_ids.size()) >= 2:
		_start_round()

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
	await _cleanup_round()
	if _series_decided():
		_phase = Phase.GAME_OVER
		_rpc_show_winner.rpc(_get_series_winner())
		await get_tree().create_timer(2.5).timeout
		Lobby.load_game.rpc(LOBBY_SCENE_PATH)
		return
	_start_round()

func _start_round() -> void:
	_promote_spectators_for_next_round()
	if active_peer_ids.size() < 2:
		_phase = Phase.WAITING
		_countdown_label.text = "Waiting for players"
		_countdown_label.visible = true
		return
	_countdown_label.visible = false
	_current_round += 1
	_assign_teams()
	_spawn_players()
	_countdown_timer = round_start_countdown
	_last_countdown_sent = -1
	_phase = Phase.COUNTDOWN

func _promote_spectators_for_next_round() -> void:
	for pid in Lobby.players.keys():
		if not active_peer_ids.has(pid) and not spectator_peer_ids.has(pid):
			spectator_peer_ids.append(pid)
	for pid in spectator_peer_ids:
		if not active_peer_ids.has(pid):
			active_peer_ids.append(pid)
	spectator_peer_ids.clear()
	_rpc_set_spectators.rpc(spectator_peer_ids)

func _spawn_players() -> void:
	players.clear()
	var botini_idx := 0
	for pid: int in active_peer_ids:
		var is_boss := (pid == boss_peer_id)
		var spawn_pos := _pick_spawn_position(botini_idx, is_boss)
		var lobby_info = Lobby.players.get(pid, {})
		var player_name := str(lobby_info.get("name", "Player %d" % pid))
		var spawn_data := {
			"scene": "boss" if is_boss else "botini",
			"team": "boss" if is_boss else "botinis",
			"peer_id": pid,
			"name": player_name,
			"spawn_position": spawn_pos,
		}
		var player := _player_spawner.spawn(spawn_data) as CharacterBody2D
		if player:
			players[pid] = player
			var hc := player.get_node_or_null("Health") as Health
			if hc:
				var dead_pid := pid
				hc.died.connect(func(): _on_player_died(dead_pid))
		if not is_boss:
			botini_idx += 1

func _spawn_player_from_data(data: Dictionary) -> Node:
	var scene_key := str(data.get("scene", "botini"))
	var scene := BOSS_SCENE if scene_key == "boss" else BOTINI_SCENE
	var player := scene.instantiate() as CharacterBody2D
	var pid := int(data.get("peer_id", 1))
	player.name = "Player_%d" % pid
	player.team = str(data.get("team", "botinis"))
	player.peer_id = pid
	player.player_name = str(data.get("name", "Player"))
	player.global_position = data.get("spawn_position", Vector2.ZERO)
	player.velocity = Vector2.ZERO
	return player

func _pick_spawn_position(botini_idx: int, is_boss: bool) -> Vector2:
	if spawn_points.is_empty():
		return Vector2.ZERO
	if is_boss:
		var boss_spawn = spawn_points[randi() % spawn_points.size()]
		return boss_spawn.global_position
	var bot_spawn = spawn_points[botini_idx % spawn_points.size()]
	return bot_spawn.global_position

func _assign_teams() -> void:
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

func _check_round_end() -> void:
	if _phase != Phase.FIGHTING:
		return
	var boss_alive := _is_boss_alive()
	var botinis_alive := _any_botini_alive()
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

func _cleanup_round() -> void:
	for c in players_container.get_children():
		c.queue_free()
	for p in projectiles_container.get_children():
		p.queue_free()
	players.clear()
	await get_tree().process_frame

func _is_boss_alive() -> bool:
	var p := players.get(boss_peer_id) as Node
	return p != null and p.get("is_alive") == true

func _any_botini_alive() -> bool:
	for pid in botinis_peer_ids:
		var p := players.get(pid) as Node
		if p != null and p.get("is_alive") == true:
			return true
	return false

func _series_decided() -> bool:
	var needed := ceili(total_rounds / 2.0)
	return _boss_wins >= needed or _botinis_wins >= needed

func _get_series_winner() -> String:
	return "boss" if _boss_wins > _botinis_wins else "botinis"

func _on_player_died(_pid: int) -> void:
	_check_round_end()

func _on_lobby_player_disconnected(peer_id: int) -> void:
	active_peer_ids.erase(peer_id)
	spectator_peer_ids.erase(peer_id)
	botinis_peer_ids.erase(peer_id)
	_last_server_shot_msec.erase(peer_id)
	var p := players.get(peer_id) as Node
	if p:
		p.queue_free()
		players.erase(peer_id)

@rpc("any_peer", "reliable")
func request_spawn_projectile(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if not players.has(sender_id):
		return
	var shooter := players[sender_id] as CharacterBody2D
	if shooter == null:
		return
	_spawn_projectile_from_owner(shooter, data)

func _spawn_projectile_from_owner(shooter: CharacterBody2D, request_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if shooter.is_alive != true:
		return

	var shooter_peer := int(shooter.peer_id)
	var now_msec := Time.get_ticks_msec()
	var attack_component := shooter.get_node_or_null("Attack") as GunAttack
	if attack_component:
		var cooldown_msec := int(attack_component.cooldown * 1000.0)
		var next_allowed_msec := int(_last_server_shot_msec.get(shooter_peer, 0))
		if now_msec < next_allowed_msec:
			return
		_last_server_shot_msec[shooter_peer] = now_msec + cooldown_msec

	var dir_data = request_data.get("direction", Vector2.RIGHT)
	var dir: Vector2 = dir_data if dir_data is Vector2 else Vector2.RIGHT
	if dir.length_squared() < 0.0001:
		dir = Vector2(1.0 if shooter.facing_right else -1.0, 0.0)
	dir = dir.normalized()

	var projectile_type := "projectile"
	var projectile_speed := 340.0
	var projectile_damage := 5
	var projectile_knockback := 220.0

	if attack_component:
		projectile_type = attack_component.projectile_type
		projectile_speed = attack_component.projectile_speed
		projectile_damage = attack_component.damage
		projectile_knockback = attack_component.knockback_force

	var spawn_pos := shooter.global_position + dir * 8.0
	var projectile_data := {
		"type": projectile_type,
		"position": spawn_pos,
		"direction": dir,
		"speed": projectile_speed,
		"damage": projectile_damage,
		"knockback": projectile_knockback,
		"owner_id": shooter_peer,
		"team": shooter.team,
	}
	spawn_projectile(projectile_data)

func spawn_projectile(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_projectile_spawner.spawn(data)

func _spawn_projectile_from_data(data: Dictionary) -> Node:
	var ptype := str(data.get("type", "projectile"))
	var projectile: Node2D
	if ptype == "laser":
		projectile = LASER_SCENE.instantiate()
	else:
		projectile = BULLET_SCENE.instantiate()
	projectile.name = "%s_%d" % [ptype.capitalize(), Time.get_ticks_msec()]
	if projectile.has_method("setup"):
		projectile.setup(data)
	return projectile

@rpc("authority", "call_local", "reliable")
func _rpc_set_teams(b_peer: int, botinis_peers: Array) -> void:
	boss_peer_id = b_peer
	botinis_peer_ids = botinis_peers

@rpc("authority", "call_local", "reliable")
func _rpc_set_spectators(peer_ids: Array) -> void:
	spectator_peer_ids = peer_ids

@rpc("authority", "call_local", "reliable")
func _rpc_countdown(seconds: int) -> void:
	_countdown_label.text = "FIGHT!" if seconds <= 0 else str(seconds)
	_countdown_label.visible = true

@rpc("authority", "call_local", "reliable")
func _rpc_hide_countdown() -> void:
	_countdown_label.visible = false

@rpc("authority", "call_local", "reliable")
func _rpc_show_winner(winner: String) -> void:
	_countdown_label.text = "%s win!" % winner.capitalize()
	_countdown_label.visible = true
