extends Node2D

const BOTINI_SCENE = preload("uid://cfxvxpnwen2eq")
const BOSS_SCENE = preload("uid://df6cjrmb84qw7")
const BULLET_SCENE = preload("uid://b8mmf48321hp")
const LASER_SCENE = preload("uid://by5n3jobbje87")

enum Phase { WAITING, COUNTDOWN, FIGHTING, ROUND_OVER, GAME_OVER }

@export var total_rounds: int   = 5
@export var round_start_countdown: float = 3.0
@export var round_end_delay: float = 2.5

# Server-side state
var _phase:              Phase = Phase.WAITING
var _current_round:      int   = 0
var _boss_wins:          int   = 0
var _botinis_wins:       int   = 0
var _countdown_timer:    float = 0.0
var _round_end_timer:    float = 0.0
var _used_boss_peers:    Array = [] # for fair boss rotation
var _last_countdown_sent: int = -1

## peer_id -> character node
var players: Dictionary = {}
var boss_peer_id:      int   = -1
var botinis_peer_ids:  Array = []

# node refs
@onready var players_container = $Players
@onready var projectiles_container = $Projectiles
@onready var spawn_points = $SpawnPoints.get_children()
@onready var _countdown_label = $CountdownLabel

func _ready() -> void:
	# Tell the server this peer has finished loading.
	# Server calls directly (rpc_id to self + call_local would double-count).
	# Clients send an RPC to peer 1 (the server).
	_countdown_label.visible = false
	if multiplayer.is_server():
		Lobby.player_loaded()
	else:
		Lobby.player_loaded.rpc_id(1)

## Called by Lobby on the server once every peer has called player_loaded().
func start_game() -> void:
	if not multiplayer.is_server(): return
	_start_round()
	
# --- Server tick ---

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server(): return
	
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
				_cleanup_round()
				if _series_decided():
					_phase = Phase.GAME_OVER
				else:
					_start_round()

# --- Round lifecycle (server only) ---

func _start_round() -> void:
	_current_round += 1
	_assign_teams()
	_spawn_players()
	_countdown_timer = round_start_countdown
	_phase = Phase.COUNTDOWN

func _spawn_players() -> void:
	# Clear leftovers from the previous round.
	for c in players_container.get_children(): c.queue_free()
	players.clear()

	var botini_idx := 0
	for pid: int in Lobby.players.keys():
		var is_boss := (pid == boss_peer_id)
		var player: CharacterBody2D

		if is_boss:
			player = BOSS_SCENE.instantiate() as CharacterBody2D
			player.team         = "boss"
			player.peer_id      = pid
			player.player_name  = Lobby.players[pid].get("name", "Boss")
			var sp = spawn_points[randi() % spawn_points.size()]
			if sp:
				player.global_position = sp.global_position   # server's own copy
				player.spawn_position  = sp.global_position   # replicated to all peers via spawn state
		else:
			player = BOTINI_SCENE.instantiate() as CharacterBody2D
			player.team         = "botinis"
			player.peer_id      = pid
			player.player_name  = Lobby.players[pid].get("name", "Botini %d" % pid)
			var sp = spawn_points[botini_idx % spawn_points.size()]
			if sp:
				player.global_position = sp.global_position   # server's own copy
				player.spawn_position  = sp.global_position   # replicated to all peers via spawn state
			botini_idx += 1

		player.name = "Player_%d" % pid
		players_container.add_child(player, true)
		players[pid] = player

		# Watch for deaths server-side.
		# Use get_node() by scene name — don't rely on the script's @onready property name.
		var hc := player.get_node("Health") as Health
		if hc:
			hc.died.connect(func(): _on_player_died(pid))

func _assign_teams() -> void:
	var all_ids: Array = Lobby.players.keys()
	if all_ids.is_empty():
		push_error("_assign_teams: Lobby.players is empty — no players to assign!")
		return

	var pool := all_ids.filter(func(id): return int(id) not in _used_boss_peers)
	if pool.is_empty():
		_used_boss_peers.clear()
		pool = all_ids.duplicate()
	pool.shuffle()

	boss_peer_id     = int(pool[0])  # force int — avoids Variant comparison mismatch
	botinis_peer_ids = all_ids.filter(func(id): return int(id) != boss_peer_id)
	_used_boss_peers.append(boss_peer_id)

	print("[Server] Round %d — Boss: %d | Botinis: %s" % [_current_round, boss_peer_id, botinis_peer_ids])
	_rpc_set_teams.rpc(boss_peer_id, botinis_peer_ids)

func _check_round_end() -> void:
	# Guard: _award_round changes _phase, but _physics_process may call us
	# one more tick before the match sees the new phase. Check explicitly.
	if _phase != Phase.FIGHTING:
		return
	var boss_alive := _is_boss_alive()
	var botinis_alive := _any_botini_alive()
	
	if not boss_alive and not botinis_alive:
		_award_round("players", "Simultaneous KO — Botinis take the round!")
	elif not boss_alive:
		_award_round("players", "Boss eliminated — Botinis win!")
	elif not botinis_alive:
		_award_round("boss",    "Botinis eliminated — Boss wins!")

func _award_round(winner: String, _msg: String) -> void:
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

func _on_player_died(pid: int) -> void:
	_check_round_end()

# --- Projectile spawning ---

func spawn_projectile(data: Dictionary):
	if not multiplayer.is_server(): return
	var ptype: String = data.get("type", "projectile")
	var projectile: Node2D

	if ptype == "laser":
		if not LASER_SCENE: return
		projectile = LASER_SCENE.instantiate()
	else:
		if not BULLET_SCENE: return
		projectile = BULLET_SCENE.instantiate()

	projectile.name = "%s_%d" % [ptype.capitalize(), Time.get_ticks_msec()]
	projectile.setup(data)                              # set state FIRST
	projectiles_container.add_child(projectile, true)   # spawner captures correct state

# --- RPCs from server to all clients ---

@rpc("any_peer", "reliable")
func request_spawn_projectile(data: Dictionary) -> void:
	if not multiplayer.is_server(): return
	spawn_projectile(data)

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
