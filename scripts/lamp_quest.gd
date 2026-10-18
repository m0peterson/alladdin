class_name LampQuest
extends RefCounted

signal changed

enum Stage { OFFERED, ACCEPTED, READY, COMPLETED }
const REWARD: int = 100
const MAX_MONEY: int = 2147483647

var last_error: String = ""
var _inventory: ItemInventory
var _state: PlayerState
var _stage: Stage = Stage.OFFERED
var _delivered_lamp: Dictionary = {}
var _busy: bool = false


# One quest belongs to one game. A new game creates a new quest instance.
func setup(inventory: ItemInventory, player_state: PlayerState) -> bool:
	if _busy or inventory == null or player_state == null:
		return false
	if _inventory != null:
		return _inventory == inventory and _state == player_state
	_inventory = inventory
	_state = player_state
	_inventory.changed.connect(_on_inventory_changed)
	return true


func get_stage() -> Stage:
	return _stage


func get_delivered_lamp() -> Dictionary:
	return _delivered_lamp.duplicate(true)


func accept_order() -> bool:
	if _busy:
		return false
	last_error = ""
	if _inventory == null or _state == null:
		return _reject("Заказ недоступен.")
	if _stage != Stage.OFFERED:
		return _reject("Заказ уже принят.")
	_busy = true
	_stage = Stage.READY if not _find_lamp().is_empty() else Stage.ACCEPTED
	changed.emit()
	_busy = false
	return true


func hand_over() -> bool:
	if _busy:
		return false
	last_error = ""
	if _inventory == null or _state == null:
		return _reject("Заказ недоступен.")
	if _stage == Stage.OFFERED:
		return _reject("Сначала примите заказ.")
	if _stage == Stage.COMPLETED:
		return _reject("Лампа уже передана. Награда получена.")
	var lamp: Dictionary = _find_lamp()
	if lamp.is_empty() or not _delivered_lamp.is_empty():
		return _reject("Нужна единственная лампа со склада.")
	if _state.money > MAX_MONEY - REWARD:
		return _reject("Нет места для награды в кошельке.")
	# All checks precede mutation. Block callbacks until the unique instance,
	# money and terminal stage are committed together; keep reentry locked
	# through every notification, including inventory and state observers.
	_busy = true
	var inventory_blocked: bool = _inventory.is_blocking_signals()
	var state_blocked: bool = _state.is_blocking_signals()
	_inventory.set_block_signals(true)
	_state.set_block_signals(true)
	var removed: bool = _inventory.remove_item(lamp["stack_id"], 1, true)
	if removed:
		_delivered_lamp = lamp.duplicate(true)
		_state.money += REWARD
		_stage = Stage.COMPLETED
	_inventory.set_block_signals(inventory_blocked)
	_state.set_block_signals(state_blocked)
	if removed:
		if not inventory_blocked:
			_inventory.changed.emit()
		if not state_blocked:
			_state.changed.emit()
		changed.emit()
	_busy = false
	return removed


func get_dialogue() -> String:
	match _stage:
		Stage.OFFERED:
			return "Принеси лампу со склада. Награда — %d динаров.\nВозьмёшься за заказ?" % REWARD
		Stage.ACCEPTED:
			return "Заказ принят. Лампа на складе к востоку.\nУдерживай F рядом с ящиком, затем вернись ко мне."
		Stage.READY:
			return "Лампа у тебя. Передашь её за %d динаров?\nЭто завершит заказ." % REWARD
		Stage.COMPLETED:
			return "Стража заметит пропажу. Лампа уже у меня.\nВнутри мерцает странный свет…\nНаграда: %d динаров. Заказ выполнен." % REWARD
	return ""


func _find_lamp() -> Dictionary:
	if _inventory == null or _inventory.count_item("lamp") != 1:
		return {}
	for stack: Dictionary in _inventory.get_stacks():
		if stack["item_id"] == "lamp" and stack["instance_id"] == ItemCatalog.LAMP_INSTANCE_ID and stack["quantity"] == 1:
			return stack
	return {}


func _on_inventory_changed() -> void:
	if _busy or _stage not in [Stage.ACCEPTED, Stage.READY]:
		return
	var next_stage: Stage = Stage.READY if not _find_lamp().is_empty() else Stage.ACCEPTED
	if _stage == next_stage:
		return
	_busy = true
	_stage = next_stage
	changed.emit()
	_busy = false


func _reject(message: String) -> bool:
	last_error = message
	return false
