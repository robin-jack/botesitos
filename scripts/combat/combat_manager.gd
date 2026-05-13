class_name CombatManager
extends Node

const ATTACK_SCENES = {
	"gun_attack": preload("uid://b8mmf48321hp")
}

var players: Dictionary = {}
var projectiles_container: Node2D


func spawn_attack(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	_do_spawn(data)


@rpc("any_peer", "reliable")
func request_attack(data: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var sender := multiplayer.get_remote_sender_id()
	var owner_id: int = data.get("owner_id", -1)
	if owner_id != sender:
		return

	var player: Player = players.get(owner_id)
	if not is_instance_valid(player) or not player.is_alive:
		return

	var attack_id: String = data.get("attack_id", "")
	if not ATTACK_SCENES.has(attack_id):
		return

	_do_spawn(data)


func _do_spawn(data: Dictionary) -> void:
	var attack_id: String = data.get("attack_id", "")
	var scene: PackedScene = ATTACK_SCENES.get(attack_id)
	if not scene:
		return

	var projectile = scene.instantiate()
	projectile.name = "%s_%d" % [attack_id.capitalize(), Time.get_ticks_msec()]
	projectile.setup(data)
	projectiles_container.add_child(projectile, true)
