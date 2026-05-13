extends Node2D

const BOTINI_SCENE = preload("uid://cfxvxpnwen2eq")
const BOSS_SCENE   = preload("uid://df6cjrmb84qw7")

## peer_id -> character node
var players: Dictionary = {}
var boss_peer_id:     int   = -1
var botinis_peer_ids: Array = []

@onready var players_container:     Node2D = $Players
@onready var projectiles_container: Node2D = $Projectiles
@onready var combat_manager:        CombatManager = $CombatManager
@onready var match_manager:         MatchManager = $MatchManager
@onready var spawn_points:          Array  = $SpawnPoints.get_children()
@onready var _countdown_label:      Label  = $UI/CountdownLabel
@onready var start_button:          Button = $UI/StartButton
@onready var stop_button:           Button = $UI/StopButton


func _ready() -> void:
	add_to_group("game")
	combat_manager.players = players
	combat_manager.projectiles_container = $Projectiles
	match_manager.setup(players)
	_connect_match_signals()

	# Only the server manages game state and spawns players.
	if multiplayer.is_server():
		for pid: int in Lobby.players:
			_spawn_single_player(pid)

		Lobby.player_connected.connect(_on_lobby_player_connected)
		Lobby.player_disconnected.connect(_on_lobby_player_disconnected)

	# The start button is only visible and functional for the host.
	_update_host_buttons()
	if multiplayer.is_server():
		start_button.pressed.connect(_on_start_button_pressed)
		stop_button.pressed.connect(_on_stop_match_pressed)


func _connect_match_signals() -> void:
	match_manager.phase_changed.connect(_on_phase_changed)
	match_manager.countdown_changed.connect(_on_countdown_changed)
	match_manager.countdown_finished.connect(_on_countdown_finished)
	match_manager.teams_changed.connect(_on_teams_changed)
	match_manager.warmup_spawn_needed.connect(_on_warmup_spawn_needed)
	match_manager.round_setup_needed.connect(_on_round_setup_needed)
	match_manager.warmup_respawn_needed.connect(_on_warmup_respawn_needed)
	match_manager.round_cleanup_needed.connect(_on_round_cleanup_needed)
	match_manager.projectiles_cleanup_needed.connect(_on_projectiles_cleanup_needed)
	match_manager.match_over.connect(_on_match_over)
	match_manager.warmup_returned.connect(_on_warmup_returned)


func _on_lobby_player_connected(pid: int, _info: Dictionary) -> void:
	if match_manager.can_spawn_joiner():
		_spawn_single_player(pid)
	else:
		# Late joiner during match — inform them
		_rpc_match_in_progress.rpc_id(pid)

func _on_lobby_player_disconnected(pid: int) -> void:
	if players.has(pid):
		var player_node: Player = players[pid]
		if is_instance_valid(player_node):
			if player_node.get_parent():
				player_node.get_parent().remove_child(player_node)
			player_node.queue_free()
		players.erase(pid)

	if not multiplayer.is_server():
		return

	match_manager.handle_player_disconnected(pid)


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
	match_manager.server_tick(delta)


func _on_start_button_pressed() -> void:
	_countdown_label.show()
	if match_manager.request_start_match(Lobby.players.keys()):
		_update_host_buttons()

func _on_stop_match_pressed() -> void:
	if not multiplayer.is_server():
		return
	match_manager.request_stop_match()


# --- MatchManager signal handlers ---

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

func _on_warmup_spawn_needed(pid: int) -> void:
	_spawn_single_player(pid)

func _on_round_setup_needed(b_peer: int, botinis_peers: Array) -> void:
	boss_peer_id = b_peer
	botinis_peer_ids = botinis_peers
	_spawn_players()

func _on_warmup_respawn_needed(pid: int) -> void:
	var player_node: Player = players.get(pid)
	if is_instance_valid(player_node):
		var sp = spawn_points[randi() % spawn_points.size()]
		player_node.respawn.rpc(sp.global_position)

func _on_round_cleanup_needed() -> void:
	for c in players_container.get_children():
		players_container.remove_child(c)
		c.queue_free()
	players.clear()

func _on_projectiles_cleanup_needed() -> void:
	for p in projectiles_container.get_children():
		p.queue_free()

func _on_match_over(scores: Dictionary) -> void:
	for pid: int in Lobby.players:
		_spawn_single_player(pid)
	_rpc_show_match_over.rpc(scores)
	stop_button.hide()

func _on_warmup_returned() -> void:
	_update_host_buttons()
	_rpc_hide_match_over.rpc()
	for pid: int in Lobby.players:
		_spawn_single_player(pid)

func _update_host_buttons() -> void:
	var is_server := multiplayer.is_server()
	var phase := match_manager.get_phase()
	start_button.visible = is_server and phase == MatchManager.Phase.WARMUP and not match_manager.is_match_in_progress()
	stop_button.visible = is_server and match_manager.is_match_in_progress()


func _spawn_players() -> void:
	for c in players_container.get_children():
		players_container.remove_child(c)
		c.queue_free()
	players.clear()

	var botini_idx := 0
	for pid: int in Lobby.players:
		var is_boss := (pid == boss_peer_id)
		var player: Player

		if is_boss:
			player              = BOSS_SCENE.instantiate()
			player.peer_id      = pid
			player.player_name  = Lobby.players[pid].get("name", "Botato %d" % pid)
		else:
			player              = BOTINI_SCENE.instantiate()
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

		player.health.died.connect(func(): _on_player_died(pid))


func _on_player_died(pid: int) -> void:
	match_manager.handle_player_died(pid)


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
