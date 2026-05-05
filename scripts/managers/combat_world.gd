class_name CombatWorld
extends Node

var _spawner: MultiplayerSpawner
var _combat_container: Node
var _match_controller: Node

func configure(spawner: MultiplayerSpawner, combat_container: Node, match_controller: Node) -> void:
	_spawner = spawner
	_combat_container = combat_container
	_match_controller = match_controller
	if _spawner:
		_spawner.spawn_function = Callable(self, "_spawn_combat_scene_from_data")


func spawn_combat_scene(scene: PackedScene, data: Dictionary) -> Node:
	if not multiplayer.is_server() or scene == null or _spawner == null:
		return null
	var spawn_data := data.duplicate(true)
	spawn_data["scene_path"] = scene.resource_path
	return _spawner.spawn(spawn_data)


func spawn_effect(scene: PackedScene, position: Vector2, data: Dictionary = {}) -> Node:
	if scene == null:
		return null
	var effect := scene.instantiate() as Node2D
	if effect == null:
		return null
	effect.global_position = position
	for key in data.keys():
		effect.set(key, data[key])
	var game := get_tree().root.get_node_or_null("Game")
	if game:
		game.add_child(effect)
	return effect


func can_player_use_abilities(player: CharacterBody2D) -> bool:
	if not multiplayer.is_server():
		return false
	if player == null or not is_instance_valid(player):
		return false
	if player.get("is_alive") != true:
		return false
	return _match_controller != null and _match_controller.can_use_abilities()


func cleanup_combat() -> void:
	if _combat_container == null:
		return
	for child in _combat_container.get_children():
		child.queue_free()


func _spawn_combat_scene_from_data(data: Dictionary) -> Node:
	var scene_path := str(data.get("scene_path", ""))
	if scene_path.is_empty():
		return null
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate()
	node.name = "%s_%d" % [node.name, Time.get_ticks_msec()]
	if node.has_method("setup"):
		node.setup(data)
	return node
