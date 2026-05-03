extends Control

## Lobby UI — handles host/join, player list, and game start.
## All networking logic lives in the Lobby autoload (lobby.gd).
## Button signals are connected in _ready() so no editor wiring is needed.

@onready var name_input:   LineEdit      = $Center/Panel/VBox/NameRow/NameInput
@onready var ip_input:     LineEdit      = $Center/Panel/VBox/JoinRow/IPInput
@onready var host_button:  Button        = $Center/Panel/VBox/HostRow/HostButton
@onready var join_button:  Button        = $Center/Panel/VBox/JoinRow/JoinButton
@onready var start_button: Button        = $Center/Panel/VBox/StartButton
@onready var status_label: Label         = $Center/Panel/VBox/StatusLabel
@onready var player_list:  VBoxContainer = $Center/Panel/VBox/PlayerList


func _ready() -> void:
	# Button signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	start_button.pressed.connect(_on_start_pressed)

	# Lobby autoload signals
	Lobby.player_connected.connect(_on_player_connected)
	Lobby.player_disconnected.connect(_on_player_disconnected)
	Lobby.server_disconnected.connect(_on_server_disconnected)

	start_button.visible = false
	_refresh_player_list()


# ── Button handlers ───────────────────────────────────────────────────────────

func _on_host_pressed() -> void:
	_apply_name()
	var err = Lobby.create_game()
	if err != OK:
		status_label.text = "Failed to host (error %s). Port may be in use." % err
		return

	status_label.text = "Hosting on port %d — waiting for players..." % Lobby.PORT
	host_button.disabled = true
	join_button.disabled = true
	start_button.visible = true
	_refresh_player_list()


func _on_join_pressed() -> void:
	_apply_name()
	var ip := ip_input.text.strip_edges()
	if ip.is_empty():
		ip = Lobby.DEFAULT_SERVER_IP

	var err = Lobby.join_game(ip)
	if err != OK:
		status_label.text = "Failed to connect (error %s)." % err
		return

	status_label.text = "Connecting to %s..." % ip
	host_button.disabled = true
	join_button.disabled = true


func _on_start_pressed() -> void:
	if not multiplayer.is_server():
		return
	if Lobby.players.size() < 2:
		status_label.text = "Need at least 2 players to start."
		return
	Lobby.load_game.rpc("res://scenes/game/game.tscn")


# ── Lobby signal handlers ─────────────────────────────────────────────────────

func _on_player_connected(_peer_id: int, _player_info: Dictionary) -> void:
	status_label.text = "%d player(s) in lobby." % Lobby.players.size()
	_refresh_player_list()


func _on_player_disconnected(_peer_id: int) -> void:
	_refresh_player_list()


func _on_server_disconnected() -> void:
	status_label.text = "Disconnected from server."
	host_button.disabled = false
	join_button.disabled = false
	start_button.visible = false
	_refresh_player_list()


# ── Helpers ───────────────────────────────────────────────────────────────────

func _apply_name() -> void:
	var n := name_input.text.strip_edges()
	Lobby.player_info["name"] = n if not n.is_empty() else "Player"


func _refresh_player_list() -> void:
	for child in player_list.get_children():
		child.queue_free()

	for pid in Lobby.players:
		var info: Dictionary = Lobby.players[pid]
		var lbl := Label.new()
		lbl.text = "%s%s" % [
			info.get("name", "Player"),
			"  [HOST]" if pid == 1 else ""
		]
		lbl.add_theme_font_size_override("font_size", 11)
		player_list.add_child(lbl)
