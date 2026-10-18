class_name TheftController
extends Node

signal theft_completed(event: Dictionary)
signal progress_changed(ratio: float, active: bool)
signal status_changed(message: String)

var hold_duration: float = 1.0
var player: Node2D
var inventory: ItemInventory
var interactions: InteractionController
var _target: TheftTarget
var _elapsed: float = 0.0
var _waiting_for_release: bool = true
var _busy: bool = false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func setup(actor: Node2D, items: ItemInventory, interaction_controller: InteractionController) -> void:
	player = actor
	inventory = items
	interactions = interaction_controller
	suppress_until_release()


func suppress_until_release() -> void:
	_waiting_for_release = true
	_cancel()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		suppress_until_release()


func _process(delta: float) -> void:
	if _busy or not InputMap.has_action("steal"):
		return
	var pressed: bool = Input.is_action_pressed("steal")
	if get_tree().paused or get_viewport().gui_get_focus_owner() != null or not is_instance_valid(player) or not player.can_process():
		suppress_until_release()
		return
	if _waiting_for_release:
		_waiting_for_release = pressed
		return
	if not pressed:
		_cancel()
		return
	var selected: TheftTarget
	if is_instance_valid(interactions) and is_instance_valid(interactions.current_target):
		selected = interactions.current_target as TheftTarget
	if not is_instance_valid(selected) or not selected.is_available(player):
		suppress_until_release()
		return
	if _elapsed > 0.0 and (not is_instance_valid(_target) or selected != _target):
		suppress_until_release()
		return
	if not selected.can_transfer(inventory):
		_busy = true
		suppress_until_release()
		status_changed.emit("Контейнер пуст или нет места для добычи.")
		_busy = false
		return
	_target = selected
	_elapsed += maxf(delta, 0.0)
	_busy = true
	progress_changed.emit(clampf(_elapsed / maxf(hold_duration, 0.01), 0.0, 1.0), true)
	# Signal listeners can open GUI, release input or change the selected target.
	if not is_instance_valid(selected) or not is_instance_valid(interactions) or interactions.current_target != selected or get_tree().paused or get_viewport().gui_get_focus_owner() != null or not Input.is_action_pressed("steal") or not selected.is_available(player):
		suppress_until_release()
		_busy = false
		return
	if _elapsed < maxf(hold_duration, 0.01):
		_busy = false
		return
	# Suppression precedes signals, so callbacks cannot start another hold.
	_waiting_for_release = true
	var event: Dictionary = selected.transfer_to(inventory, player)
	_cancel()
	if not event.is_empty():
		status_changed.emit("Добыча получена.")
		theft_completed.emit(event)
	_busy = false


func _cancel() -> void:
	_elapsed = 0.0
	_target = null
	progress_changed.emit(0.0, false)
