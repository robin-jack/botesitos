extends Node2D

const BOTINI_SCENE = preload("uid://cfxvxpnwen2eq")
const BOSS_SCENE   = preload("uid://df6cjrmb84qw7")
const BULLET_SCENE = preload("uid://b8mmf48321hp")
const LASER_SCENE  = preload("uid://by5n3jobbje87")

enum TEAM { BOTINI, BOTATO }
enum Phase { WARMUP, COUNTDOWN, FIGHTING, ROUND_OVER, MATCH_OVER }

@export var total_rounds:          int   = 5
@export var round_start_countdown: float = 3.0
@export var round_end_delay:       float = 2.5

# Server-side state
var _phase:               Phase = Phase.WARMUP
var _current_round:       int   = 0
var _countdown_timer:     float = 0.0
var _round_end_timer:     float = 0.0
var _last_countdown_sent: int   = -1

var _match_in_progress:     bool = false
var _boss_rotation:         Array = []
var _player_scores:         Dictionary = {}
var _warmup_respawn_timers: Dictionary = {}

## peer_id -> character node
var players: Dictionary = {}
var boss_peer_id:     int   = -1
var botinis_peer_ids: Array = []

@onready var players_container:     Node2D = $Players
@onready var projectiles_container: Node2D = $Projectiles
@onready var spawn_points:          Array  = $SpawnPoints.get_children()
@onready var _countdown_label:      Label  = $CountdownLabel
@onready var start_button:          Button = $UI/StartButton
@onready var stop_button:           Button = $UI/StopButton


func _ready() -> void:
	# Only the server manages game state and spawns players.
	if multiplayer.is_server():
		for pid: int in Lobby.players:
			_spawn_single_player(pid)

		Lobby.player_connected.connect(_on_lobby_player_connected)
		Lobby.player_disconnected.connect(_on_lobby_player_disconnected)
		_phase = Phase.WARMUP

	# The start button is only visible and functional for the host.
	start_button.visible = multiplayer.is_server()
	stop_button.visible = false
	if multiplayer.is_server():
		start_button.pressed.connect(_on_start_button_pressed)
		stop_button.pressed.connect(_on_stop_match_pressed)


func _on_lobby_player_connected(pid: int, _info: Dictionary) -> void:
	if _phase == Phase.WARMUP:
		_spawn_single_player(pid)
	else:
		# Late joiner during match — inform them
		_rpc_match_in_progress.rpc_id(pid)


func _on_lobby_player_disconnected(pid: int) -> void:
	if players.has(pid):
		var player_node: Node = players[pid]
		if is_instance_valid(player_node):
			if player_node.get_parent():
				player_node.get_parent().remove_child(player_node)
			player_node.queue_free()
		players.erase(pid)

	if not multiplayer.is_server():
		return

	# Remove from rotation if they haven't been Botato yet
	if _match_in_progress:
		var idx := _boss_rotation.find(pid)
		if idx != -1 and idx >= _current_round:
			_boss_rotation.remove_at(idx)

		if _phase == Phase.FIGHTING:
			_check_round_end()


func _spawn_single_player(pid: int) -> void:
	if players.has(pid):
		return

	var player := BOTINI_SCENE.instantiate() as CharacterBody2D
	player.peer_id     = pid
	player.team        = pid
	player.player_name = Lobby.players[pid].get("name", "Player %d" % pid)
	player.name        = str(pid)

	players[pid] = player
	var sp: Node2D = spawn_points[randi() % spawn_points.size()]
	player.position = sp.global_position - players_container.global_position
	players_container.add_child(player)

	var hc := player.get_node_or_null("Health") as Health
	if hc:
		hc.died.connect(func(): _on_player_died(pid))


# --- Server tick ---

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return

	match _phase:
		Phase.WARMUP:
			_process_warmup_respawns(delta)

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
				_cleanup_round()
				if _match_is_over():
					_end_match()
				else:
					_start_round()

		Phase.MATCH_OVER:
			_round_end_timer -= delta
			if _round_end_timer <= 0.0:
				_return_to_warmup()


func _process_warmup_respawns(delta: float) -> void:
	var done: Array[int] = []
	for pid: int in _warmup_respawn_timers:
		_warmup_respawn_timers[pid] -= delta
		if _warmup_respawn_timers[pid] <= 0.0:
			done.append(pid)
			var player_node = players.get(pid) as Node
			if is_instance_valid(player_node):
				var sp = spawn_points[randi() % spawn_points.size()]
				player_node.respawn.rpc(sp.global_position)
	for pid: int in done:
		_warmup_respawn_timers.erase(pid)


# --- Round lifecycle (server only) ---

func _on_start_button_pressed() -> void:
	if _phase != Phase.WARMUP:
		return
	if Lobby.players.size() < 2:
		print("[Server] Need at least 2 players to start.")
		return

	_boss_rotation = Lobby.players.keys().duplicate()
	_boss_rotation.shuffle()

	_player_scores.clear()
	for pid: int in Lobby.players:
		_player_scores[pid] = 0

	_match_in_progress = true
	_current_round = 0
	start_button.hide()
	stop_button.show()

	_start_round()


func _on_stop_match_pressed() -> void:
	if not multiplayer.is_server():
		return
	if not _match_in_progress:
		return
	_cleanup_round()
	_end_match()


func _start_round() -> void:
	_current_round += 1
	boss_peer_id     = _boss_rotation[_current_round - 1]
	botinis_peer_ids = _boss_rotation.filter(func(id): return id != boss_peer_id)

	_spawn_players()
	_countdown_timer     = round_start_countdown
	_last_countdown_sent = -1
	_phase               = Phase.COUNTDOWN

	_rpc_set_teams.rpc(boss_peer_id, botinis_peer_ids)
	_rpc_hide_match_over.rpc()


func _spawn_players() -> void:
	for c in players_container.get_children():
		players_container.remove_child(c)
		c.queue_free()
	players.clear()

	var botini_idx := 0
	for pid: int in Lobby.players:
		var is_boss := (pid == boss_peer_id)
		var player: CharacterBody2D

		if is_boss:
			player              = BOSS_SCENE.instantiate() as CharacterBody2D
			player.peer_id      = pid
			player.player_name  = Lobby.players[pid].get("name", "Botato %d" % pid)
		else:
			player              = BOTINI_SCENE.instantiate() as CharacterBody2D
			player.peer_id      = pid
			player.player_name  = Lobby.players[pid].get("name", "Botini %d" % pid)

		player.name = str(pid)
		var sp: Node2D
		if is_boss:
			sp = spawn_points[randi() % spawn_points.size()]
		else:
			sp = spawn_points[botini_idx % spawn_points.size()]
			botini_idx += 1
		player.position = sp.global_position - players_container.global_position
		players_container.add_child(player, true)
		players[pid] = player

		var hc := player.get_node("Health") as Health
		if hc:
			hc.died.connect(func(): _on_player_died(pid))


func _check_round_end() -> void:
	if _phase != Phase.FIGHTING:
		return
	var boss_alive    := _is_boss_alive()
	var botinis_alive := _any_botini_alive()

	if not boss_alive and not botinis_alive:
		_award_round(TEAM.BOTINI, "Simultaneous KO — Botinis take the round!")
	elif not boss_alive:
		_award_round(TEAM.BOTINI, "Boss eliminated — Botinis win!")
	elif not botinis_alive:
		_award_round(TEAM.BOTATO, "Botinis eliminated — Botato wins!")


func _award_round(winner_team: TEAM, _msg: String) -> void:
	_phase           = Phase.ROUND_OVER
	_round_end_timer = round_end_delay

	if winner_team == TEAM.BOTATO:
		# Botato wins: +2 per dead Botini, +2 survive
		var botato = players.get(boss_peer_id)
		if botato and botato.get("is_alive") == true:
			_player_scores[boss_peer_id] += 2

		for pid: int in botinis_peer_ids:
			var p = players.get(pid)
			if p and p.get("is_alive") == false:
				_player_scores[boss_peer_id] += 2
	else:
		# Botinis win: +5 each surviving Botini, +2 survival
		for pid: int in botinis_peer_ids:
			var p = players.get(pid)
			if p and p.get("is_alive") == true:
				_player_scores[pid] += 7


func _cleanup_round() -> void:
	for c in players_container.get_children():
		players_container.remove_child(c)
		c.queue_free()
	for p in projectiles_container.get_children():
		p.queue_free()
	players.clear()


func _is_boss_alive() -> bool:
	var p := players.get(boss_peer_id) as Node
	return p != null and p.get("is_alive") == true


func _any_botini_alive() -> bool:
	for pid: int in botinis_peer_ids:
		var p := players.get(pid) as Node
		if p != null and p.get("is_alive") == true:
			return true
	return false


func _match_is_over() -> bool:
	return _current_round >= _boss_rotation.size()


func _end_match() -> void:
	_phase = Phase.MATCH_OVER
	_round_end_timer = 5.0
	# Spawn warmup players immediately so clients have nodes to sync to.
	# This prevents stale MultiplayerSynchronizer cache errors while the
	# match-over screen is shown.
	for pid: int in Lobby.players:
		_spawn_single_player(pid)
	_rpc_show_match_over.rpc(_player_scores)
	stop_button.hide()


func _return_to_warmup() -> void:
	_boss_rotation.clear()
	_current_round = 0
	_player_scores.clear()
	_warmup_respawn_timers.clear()
	_phase = Phase.WARMUP
	_match_in_progress = false

	start_button.visible = multiplayer.is_server()
	stop_button.visible = false
	_rpc_hide_match_over.rpc()

	for pid: int in Lobby.players:
		_spawn_single_player(pid)


func _on_player_died(pid: int) -> void:
	if _phase == Phase.WARMUP:
		_warmup_respawn_timers[pid] = 2.0
	elif _phase == Phase.FIGHTING:
		_check_round_end()


# --- Projectile spawning ---

func spawn_projectile(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var ptype: String = data.get("type", "projectile")
	var projectile: Node2D

	if ptype == "laser":
		if not LASER_SCENE:
			return
		projectile = LASER_SCENE.instantiate()
	else:
		if not BULLET_SCENE:
			return
		projectile = BULLET_SCENE.instantiate()

	projectile.name = "%s_%d" % [ptype.capitalize(), Time.get_ticks_msec()]
	projectile.setup(data)
	projectiles_container.add_child(projectile, true)


@rpc("any_peer", "reliable")
func request_spawn_projectile(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	spawn_projectile(data)


# --- Server → all clients RPCs ---

@rpc("authority", "call_local", "reliable")
func _rpc_set_teams(b_peer: int, botinis_peers: Array) -> void:
	boss_peer_id     = b_peer
	botinis_peer_ids = botinis_peers


@rpc("authority", "call_local", "reliable")
func _rpc_countdown(seconds: int) -> void:
	_countdown_label.text    = "FIGHT!" if seconds <= 0 else str(seconds)
	_countdown_label.visible = true


@rpc("authority", "call_local", "reliable")
func _rpc_hide_countdown() -> void:
	_countdown_label.visible = false


@rpc("authority", "call_local", "reliable")
func _rpc_show_match_over(scores: Dictionary) -> void:
	var winner_pid := -1
	var winner_score := -1
	var text := "MATCH OVER!\n"
	for pid in scores:
		var player_name := ""
		if Lobby.players.has(pid):
			player_name = Lobby.players[pid].get("name", "Player %d" % pid)
		else:
			player_name = "Player %d" % pid
		var score: int = scores[pid]
		text += "%s: %d pts\n" % [player_name, score]
		if score > winner_score:
			winner_score = score
			winner_pid = pid
	if winner_pid != -1:
		var winner_name := ""
		if Lobby.players.has(winner_pid):
			winner_name = Lobby.players[winner_pid].get("name", "Player %d" % winner_pid)
		else:
			winner_name = "Player %d" % winner_pid
		text += "\nWinner: %s!" % winner_name
	_countdown_label.text = text
	_countdown_label.visible = true


@rpc("authority", "call_local", "reliable")
func _rpc_hide_match_over() -> void:
	_countdown_label.visible = false


@rpc("authority", "call_local", "reliable")
func _rpc_match_in_progress() -> void:
	_countdown_label.text = "Match in progress.\nPlease wait for the next match."
	_countdown_label.visible = true
