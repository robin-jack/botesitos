extends Node2D

## peer_id -> character node (forwarded from PlayerManager)
var players: Dictionary:
	get:
		return player_manager.players if player_manager else {}

var boss_peer_id:     int   = -1
var botinis_peer_ids: Array = []

@onready var players_container:     Node2D = $Players
@onready var projectiles_container: Node2D = $Projectiles
@onready var combat_manager:        CombatManager = $CombatManager
@onready var match_manager:         MatchManager = $MatchManager
@onready var player_manager:        PlayerManager = $PlayerManager
@onready var spawn_points:          Array  = $SpawnPoints.get_children()
@onready var _countdown_label:      Label  = $UI/CountdownLabel
@onready var start_button:          Button = $UI/StartButton
@onready var stop_button:           Button = $UI/StopButton


func _ready() -> void:
	add_to_group("game")
	player_manager.setup(players_container, spawn_points)
	match_manager.setup(player_manager.players)
	combat_manager.players = player_manager.clients
	combat_manager.projectiles_container = $Projectiles
	_connect_signals()

	# Only the server manages game state and spawns players.
	if multiplayer.is_server():
		for pid: int in Lobby.clients:
			player_manager.spawn_warmup_player(pid, Lobby.clients[pid])

		Lobby.player_connected.connect(_on_lobby_player_connected)
		Lobby.player_disconnected.connect(_on_lobby_player_disconnected)

	# The start button is only visible and functional for the host.
	_update_host_buttons()
	if multiplayer.is_server():
		start_button.pressed.connect(_on_start_button_pressed)
		stop_button.pressed.connect(_on_stop_match_pressed)


func _connect_signals() -> void:
	# MatchManager -> game.gd (UI / RPC presentation)
	match_manager.phase_changed.connect(_on_phase_changed)
	match_manager.countdown_changed.connect(_on_countdown_changed)
	match_manager.countdown_finished.connect(_on_countdown_finished)
	match_manager.teams_changed.connect(_on_teams_changed)
	match_manager.match_over.connect(_on_match_over)
	match_manager.warmup_returned.connect(_on_warmup_returned)

	# MatchManager -> PlayerManager (lifecycle)
	match_manager.warmup_spawn_needed.connect(
		func(pid): player_manager.spawn_warmup_player(pid, Lobby.clients.get(pid, {}))
	)
	match_manager.round_setup_needed.connect(
		func(boss_id, botini_ids): player_manager.spawn_round_players(Lobby.clients, boss_id, botini_ids)
	)
	match_manager.warmup_respawn_needed.connect(player_manager.respawn_warmup_player)
	match_manager.round_cleanup_needed.connect(player_manager.clear_players)

	# MatchManager -> CombatManager (projectiles)
	match_manager.projectiles_cleanup_needed.connect(combat_manager.clear_projectiles)

	# PlayerManager -> game.gd -> MatchManager (death)
	player_manager.player_died.connect(_on_player_died)


func _on_lobby_player_connected(pid: int, _info: Dictionary) -> void:
	player_manager.mark_player_connected(pid)
	if match_manager.can_spawn_joiner():
		player_manager.spawn_warmup_player(pid, Lobby.clients[pid])
	else:
		# Late joiner during match — inform them
		_rpc_match_in_progress.rpc_id(pid)


func _on_lobby_player_disconnected(pid: int) -> void:
	player_manager.mark_player_disconnected(pid)

	if not multiplayer.is_server():
		return

	match_manager.handle_player_disconnected(pid)


func _on_player_died(pid: int) -> void:
	if not multiplayer.is_server():
		return
	match_manager.handle_player_died(pid)
	player_manager.despawn_eliminated_player(pid)


# --- Server tick ---

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	match_manager.server_tick(delta)


func _on_start_button_pressed() -> void:
	_countdown_label.show()
	if match_manager.request_start_match(Lobby.clients.keys()):
		_update_host_buttons()

func _on_stop_match_pressed() -> void:
	if not multiplayer.is_server():
		return
	match_manager.request_stop_match()


# --- MatchManager signal handlers (UI / RPC presentation) ---

func _on_phase_changed(_phase: int) -> void:
	_update_host_buttons()

func _on_countdown_changed(seconds: int) -> void:
	_rpc_countdown.rpc(seconds)

func _on_countdown_finished() -> void:
	_rpc_hide_countdown.rpc()

func _on_teams_changed(b_peer: int, botinis_peers: Array) -> void:
	boss_peer_id = b_peer
	botinis_peer_ids = botinis_peers
	_rpc_set_teams.rpc(b_peer, botinis_peers)
	_rpc_hide_match_over.rpc()

func _on_match_over(scores: Dictionary) -> void:
	player_manager.clear_players()
	for pid: int in Lobby.clients:
		player_manager.spawn_warmup_player(pid, Lobby.clients[pid])
	_rpc_show_match_over.rpc(scores)
	stop_button.hide()

func _on_warmup_returned() -> void:
	player_manager.clear_players()
	_update_host_buttons()
	_rpc_hide_match_over.rpc()
	for pid: int in Lobby.clients:
		player_manager.spawn_warmup_player(pid, Lobby.clients[pid])

func _update_host_buttons() -> void:
	var is_server := multiplayer.is_server()
	var phase := match_manager.get_phase()
	start_button.visible = is_server and phase == MatchManager.Phase.WARMUP and not match_manager.is_match_in_progress()
	stop_button.visible = is_server and match_manager.is_match_in_progress()


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
		if Lobby.clients.has(pid):
			player_name = Lobby.clients[pid].get("name", "Player %d" % pid)
		else:
			player_name = "Player %d" % pid
		var score: int = scores[pid]
		text += "%s: %d pts\n" % [player_name, score]
		if score > winner_score:
			winner_score = score
			winner_pid = pid
	if winner_pid != -1:
		var winner_name := ""
		if Lobby.clients.has(winner_pid):
			winner_name = Lobby.clients[winner_pid].get("name", "Player %d" % winner_pid)
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
