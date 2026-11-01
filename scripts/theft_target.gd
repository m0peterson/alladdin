class_name TheftTarget
extends InteractionTarget

@export var owner_id: String = ""
# A container holds one finite lot. Each successful hold empties that lot.
var stock: ItemInventory = ItemInventory.new()
var _busy: bool = false
var _seeded: bool = false


func _init() -> void:
	kind = Kind.CONTAINER


func seed(item_id: String, quantity: int = 1, provenance: Dictionary = {}) -> bool:
	if _busy or _seeded or not stock.get_stacks().is_empty() or target_id.is_empty() or owner_id.is_empty():
		return false
	var origin: Dictionary = provenance.duplicate(true)
	origin["owner_id"] = owner_id
	origin["source_id"] = target_id
	_seeded = stock.add_item(item_id, quantity, origin)
	return _seeded


func prompt() -> String:
	return "Удерж. F — %s" % display_name if not stock.get_stacks().is_empty() else "Пусто: %s" % display_name


func interact(actor: Node2D) -> String:
	return prompt() if is_available(actor) else ""


func get_loot() -> Dictionary:
	var stacks: Array[Dictionary] = stock.get_stacks()
	return stacks[0] if stacks.size() == 1 else {}


func stolen_origin(loot: Dictionary) -> Dictionary:
	return {"stolen": true, "owner_id": owner_id, "source_id": target_id,
		"instance_id": loot.get("instance_id", "")}


func can_transfer(inventory: ItemInventory) -> bool:
	var loot: Dictionary = get_loot()
	return not _busy and inventory != null and inventory != stock and not owner_id.is_empty() and not target_id.is_empty() and not loot.is_empty() and inventory.can_add_item(loot["item_id"], loot["quantity"], stolen_origin(loot))


func transfer_to(inventory: ItemInventory, actor: Node2D) -> Dictionary:
	if not is_available(actor) or not can_transfer(inventory):
		return {}
	var loot: Dictionary = get_loot()
	var event: Dictionary = {"source_id": target_id, "owner_id": owner_id,
		"position": actor.global_position, "item_id": loot["item_id"], "quantity": loot["quantity"]}
	_busy = true
	var stock_blocked: bool = stock.is_blocking_signals()
	var inventory_blocked: bool = inventory.is_blocking_signals()
	stock.set_block_signals(true)
	inventory.set_block_signals(true)
	var removed: bool = stock.remove_item(loot["stack_id"], loot["quantity"], true)
	var added: bool = inventory.add_item(loot["item_id"], loot["quantity"], stolen_origin(loot)) if removed else false
	assert(removed and added, "Theft inventory contract violated after preflight")
	stock.set_block_signals(stock_blocked)
	inventory.set_block_signals(inventory_blocked)
	if removed and added:
		opened = true
		if not stock_blocked:
			stock.changed.emit()
		if not inventory_blocked:
			inventory.changed.emit()
	_busy = false
	return event if removed and added else {}


func save_snapshot() -> Dictionary:
	return {"owner_id": owner_id, "opened": opened, "inventory": stock.save_snapshot()}


func validate_snapshot(data: Variant) -> String:
	if data is not Dictionary or data.get("owner_id") != owner_id or data.get("opened") is not bool:
		return "Неверное состояние контейнера: " + target_id
	var problem: String = ItemInventory.validate_snapshot(data.get("inventory"))
	if not problem.is_empty():
		return problem
	var stacks: Array = data["inventory"]["stacks"]
	if stacks.size() > 1 or data["opened"] != stacks.is_empty():
		return "Содержимое контейнера не согласовано с открытием."
	for entry: Dictionary in stacks:
		if entry["owner_id"] != owner_id or entry["source_id"] != target_id or entry["stolen"]:
			return "Неверное происхождение содержимого контейнера."
	return ""


func restore_snapshot(data: Variant) -> bool:
	if _busy or not validate_snapshot(data).is_empty():
		return false
	var blocked: bool = stock.is_blocking_signals()
	stock.set_block_signals(true)
	stock.restore_snapshot(data["inventory"])
	stock.set_block_signals(blocked)
	opened = data["opened"]
	_seeded = true
	return true
