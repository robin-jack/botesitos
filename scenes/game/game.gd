extends Node2D

@onready var players_container: Node2D = $Players
@onready var projectiles_container: Node2D = $Projectiles
@onready var spawn_points: Array = $SpawnPoints.get_children()
@onready var _countdown_label: Label = $CountdownLabel
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _projectile_spawner: MultiplayerSpawner = $ProjectileSpawner

@onready var player_registry: Node = $PlayerRegistry
@onready var player_spawn_service: Node = $PlayerSpawnService
@onready var match_controller: Node = $MatchController
@onready var combat_world: Node = $CombatWorld

func _ready() -> void:
	combat_world.configure(_projectile_spawner, projectiles_container, match_controller)
	player_spawn_service.configure(_player_spawner, players_container, spawn_points, player_registry, combat_world)
	match_controller.configure(player_registry, player_spawn_service, _countdown_label)

	Lobby.player_disconnected.connect(_on_lobby_player_disconnected)
	if multiplayer.is_server():
		Lobby.player_loaded_local()
	else:
		Lobby.player_loaded.rpc_id(1)

func start_game() -> void:
	match_controller.start_game()

func on_peer_loaded_during_match(peer_id: int) -> void:
	match_controller.on_peer_loaded_during_match(peer_id)

func get_combat_world() -> Node:
	return combat_world

func _on_lobby_player_disconnected(peer_id: int) -> void:
	match_controller.on_player_disconnected(peer_id)
