extends Control

## Lobby UI — lets the player enter a name and host/join a game.
## All networking logic lives in the Lobby autoload (lobby.gd).
## Scene transition happens only after the connection is confirmed,
## avoiding the race condition of changing scene before ENet is ready.

const GAME_SCENE = "res://scenes/game/game.tscn"

@onready var name_input:   LineEdit = $Center/Panel/VBox/NameRow/NameInput
@onready var ip_input:     LineEdit = $Center/Panel/VBox/JoinRow/IPInput
@onready var host_button:  Button   = $Center/Panel/VBox/HostRow/HostButton
@onready var join_button:  Button   = $Center/Panel/VBox/JoinRow/JoinButton
@onready var status_label: Label    = $Center/Panel/VBox/StatusLabel


func _ready() -> void:
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	# Scene transition is driven by Lobby signals so it only fires
	# once the connection is actually established.
	Lobby.player_connected.connect(_on_player_connected)
	Lobby.connection_failed.connect(_on_connection_failed)
	Lobby.server_disconnected.connect(_on_server_disconnected)
	
	if OS.has_feature("hoster"):
		_on_host_pressed()
	else:
		_on_join_pressed.call_deferred()


# --- Button handlers ---

func _on_host_pressed() -> void:
	_apply_name()
	var err := Lobby.create_game()
	if err != OK:
		status_label.text = "Failed to host (error %s). Port may be in use." % err
		return
	# create_game() emits player_connected(1, …) synchronously,
	# so _on_player_connected handles the scene change below.
	print_debug("Host session here")


func _on_join_pressed() -> void:
	_apply_name()
	var ip := ip_input.text.strip_edges()
	if ip.is_empty():
		ip = Lobby.DEFAULT_SERVER_IP

	var err := Lobby.join_game(ip)
	if err != OK:
		status_label.text = "Failed to connect (error %s)." % err
		return

	status_label.text  = "Connecting to %s…" % ip
	host_button.disabled = true
	join_button.disabled = true

# --- Lobby signal handlers ---

## Fires for every player that connects, including ourselves.
## We only care about our own confirmation to trigger the scene change.
func _on_player_connected(peer_id: int, _info: Dictionary) -> void:
	if peer_id == multiplayer.get_unique_id():
		get_tree().change_scene_to_file(GAME_SCENE)


func _on_connection_failed() -> void:
	status_label.text    = "Connection failed."
	host_button.disabled = false
	join_button.disabled = false


func _on_server_disconnected() -> void:
	status_label.text    = "Disconnected from server."
	host_button.disabled = false
	join_button.disabled = false


# --- Helpers ---

func _apply_name() -> void:
	var n := name_input.text.strip_edges()
	Lobby.player_info["name"] = n if not n.is_empty() else _generate_random_name()


func _generate_random_name() -> String:
	# @Emi's fantastic names
	var Emi1: Array[String] = ["Re", "Dar", "Me", "Su", "Ven"]
	var Emi2: Array[String] = ["ir", "ton", "me", "so"]
	var Emi3: Array[String] = ["tz", "s", "er", "ky"]
	return (Emi1[randi() % Emi1.size()]
		+ Emi2[randi() % Emi2.size()]
		+ Emi3[randi() % Emi3.size()])
