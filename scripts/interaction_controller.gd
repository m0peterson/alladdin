class_name InteractionController
extends Node

signal prompt_changed(text: String)
signal interaction_completed(message: String)

var player: Node2D
var current_target: InteractionTarget
var _waiting_for_release: bool = true


func set_player(actor: Node2D) -> void:
	player = actor
	_set_target(null)
	suppress_until_release()


func suppress_until_release() -> void:
	_waiting_for_release = true


func _process(_delta: float) -> void:
	if _waiting_for_release:
		_waiting_for_release = Input.is_action_pressed("interact")
	refresh_target()


func refresh_target() -> void:
	var nearest: InteractionTarget
	var nearest_distance: float = INF
	if is_instance_valid(player) and player.can_process() and not get_tree().paused:
		for node: Node in get_tree().get_nodes_in_group("interaction_targets"):
			var target: InteractionTarget = node as InteractionTarget
			if target == null or not player.get_parent().is_ancestor_of(target) or not target.is_available(player):
				continue
			var distance: float = player.global_position.distance_squared_to(target.global_position)
			if distance < nearest_distance or (distance == nearest_distance and target.target_id < nearest.target_id):
				nearest = target
				nearest_distance = distance
	_set_target(nearest)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if not _waiting_for_release:
			try_interact()


func try_interact() -> void:
	# Act on the displayed target, never silently switch to another on keypress.
	if not is_instance_valid(current_target) or not current_target.is_available(player):
		_set_target(null)
		return
	var result: String = current_target.interact(player)
	if not result.is_empty():
		interaction_completed.emit(result)


func _set_target(target: InteractionTarget) -> void:
	current_target = target
	prompt_changed.emit(target.prompt() if is_instance_valid(target) else "")
