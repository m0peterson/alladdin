class_name ItemInventory
extends RefCounted

signal changed

const MAX_QUANTITY: int = 2147483647
var _stacks: Array[Dictionary] = []
var _next_stack_id: int = 1


func get_stacks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for stack: Dictionary in _stacks:
		result.append(stack.duplicate(true))
	return result


func get_stack(stack_id: String) -> Dictionary:
	for stack: Dictionary in _stacks:
		if stack["stack_id"] == stack_id:
			return stack.duplicate(true)
	return {}


func count_item(item_id: String) -> int:
	var count: int = 0
	for stack: Dictionary in _stacks:
		if stack["item_id"] == item_id:
			count += stack["quantity"] as int
	return count


func can_add_item(item_id: String, quantity: int, provenance: Dictionary = {}) -> bool:
	var item: Dictionary = ItemCatalog.get_item(item_id)
	if item.is_empty() or quantity <= 0 or quantity > MAX_QUANTITY:
		return false
	# Check subtraction first, so even int64-max input cannot overflow a sum.
	if count_item(item_id) > MAX_QUANTITY - quantity:
		return false
	var origin: Dictionary = _normalize_origin(item_id, provenance)
	if origin.is_empty():
		return false
	if item["type"] == "quest" and (quantity != 1 or count_item(item_id) != 0):
		return false
	var instance_id: String = origin["instance_id"]
	if not instance_id.is_empty():
		if quantity != 1:
			return false
		for stack: Dictionary in _stacks:
			if stack["instance_id"] == instance_id:
				return false
	return true


func add_item(item_id: String, quantity: int, provenance: Dictionary = {}) -> bool:
	if not can_add_item(item_id, quantity, provenance):
		return false
	var origin: Dictionary = _normalize_origin(item_id, provenance)
	for stack: Dictionary in _stacks:
		if stack["item_id"] == item_id and _same_origin(stack, origin):
			stack["quantity"] += quantity
			changed.emit()
			return true
	var stack: Dictionary = origin.duplicate(true)
	stack["stack_id"] = "stack_%d" % _next_stack_id
	_next_stack_id += 1
	stack["item_id"] = item_id
	stack["quantity"] = quantity
	_stacks.append(stack)
	changed.emit()
	return true


func remove_item(stack_id: String, quantity: int, allow_quest: bool = false) -> bool:
	if quantity <= 0 or quantity > MAX_QUANTITY:
		return false
	for index: int in range(_stacks.size()):
		var stack: Dictionary = _stacks[index]
		if stack["stack_id"] != stack_id:
			continue
		if quantity > stack["quantity"]:
			return false
		if ItemCatalog.get_item(stack["item_id"])["type"] == "quest" and not allow_quest:
			return false
		stack["quantity"] -= quantity
		if stack["quantity"] == 0:
			_stacks.remove_at(index)
		changed.emit()
		return true
	return false


func use_food(stack_id: String, player_state: PlayerState) -> bool:
	if player_state == null or player_state.health <= 0 or player_state.health >= PlayerState.MAX_HEALTH:
		return false
	var stack: Dictionary = self.get_stack(stack_id)
	if stack.is_empty():
		return false
	var item: Dictionary = ItemCatalog.get_item(stack["item_id"])
	if item["type"] != "food" or not item["usable"] or item["heal"] <= 0:
		return false
	# All preconditions passed: consume exactly one and clamp healing in PlayerState.
	if not remove_item(stack_id, 1):
		return false
	player_state.health += item["heal"] as int
	return true


func _normalize_origin(item_id: String, provenance: Dictionary) -> Dictionary:
	if provenance.get("stolen", false) is not bool:
		return {}
	for key: String in ["owner_id", "source_id", "instance_id"]:
		if provenance.get(key, "") is not String:
			return {}
	var origin: Dictionary = {
		"stolen": provenance.get("stolen", false),
		"owner_id": provenance.get("owner_id", ""),
		"source_id": provenance.get("source_id", ""),
		"instance_id": provenance.get("instance_id", ""),
	}
	if origin["stolen"] and (origin["owner_id"].is_empty() or origin["source_id"].is_empty()):
		return {}
	if item_id == "lamp":
		if origin["instance_id"] not in ["", ItemCatalog.LAMP_INSTANCE_ID]:
			return {}
		origin["instance_id"] = ItemCatalog.LAMP_INSTANCE_ID
	elif origin["instance_id"] == ItemCatalog.LAMP_INSTANCE_ID:
		return {}
	return origin


func _same_origin(stack: Dictionary, origin: Dictionary) -> bool:
	for key: String in ["stolen", "owner_id", "source_id", "instance_id"]:
		if stack[key] != origin[key]:
			return false
	return true
