class_name ItemInventory
extends RefCounted

signal changed

const MAX_QUANTITY: int = 2147483647
const MAX_STACKS: int = 4096
const MAX_ID_LENGTH: int = 128
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
	# Existing stacks can still merge at either save-format limit, without
	# consuming another ID or stack slot.
	if _next_stack_id >= MAX_QUANTITY or _stacks.size() >= MAX_STACKS:
		for stack: Dictionary in _stacks:
			if stack["item_id"] == item_id and _same_origin(stack, origin):
				return true
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
		if provenance.get(key, "") is not String or provenance.get(key, "").length() > MAX_ID_LENGTH:
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


func save_snapshot() -> Dictionary:
	return {"stacks": get_stacks(), "next_stack_id": _next_stack_id}


static func validate_snapshot(data: Variant) -> String:
	if data is not Dictionary or data.get("stacks") is not Array or not PlayerSave.integer_in(data.get("next_stack_id"), 1, MAX_QUANTITY):
		return "Неверный формат инвентаря."
	if data["stacks"].size() > MAX_STACKS:
		return "В сохранении слишком много стеков."
	var candidate: ItemInventory = ItemInventory.new()
	var ids: Dictionary = {}
	var pattern: RegEx = RegEx.create_from_string("^stack_([1-9][0-9]{0,9})$")
	for entry: Variant in data["stacks"]:
		if entry is not Dictionary:
			return "Неверный стек инвентаря."
		for key: String in ["stack_id", "item_id", "owner_id", "source_id", "instance_id"]:
			if entry.get(key) is not String or entry[key].length() > MAX_ID_LENGTH:
				return "Неверный ID или происхождение предмета."
		var matched: RegExMatch = pattern.search(entry["stack_id"])
		if matched == null or ids.has(entry["stack_id"]) or int(matched.get_string(1)) >= int(data["next_stack_id"]):
			return "Неверный или повторный ID стека."
		if entry.get("stolen") is not bool or not PlayerSave.integer_in(entry.get("quantity"), 1, MAX_QUANTITY):
			return "Неверное количество или отметка кражи."
		if entry["item_id"] == "lamp" and entry["instance_id"] != ItemCatalog.LAMP_INSTANCE_ID:
			return "Неверный ID уникальной лампы."
		if not candidate.add_item(entry["item_id"], int(entry["quantity"]), entry):
			return "Неверный предмет, происхождение или дубликат уникального предмета."
		ids[entry["stack_id"]] = true
	return ""


# Validate before replacing anything, including when called outside file loading.
func restore_snapshot(data: Variant) -> bool:
	if not validate_snapshot(data).is_empty():
		return false
	var restored: Array[Dictionary] = []
	for entry: Dictionary in data["stacks"]:
		var stack: Dictionary = entry.duplicate(true)
		stack["quantity"] = int(stack["quantity"])
		restored.append(stack)
	_stacks = restored
	_next_stack_id = int(data["next_stack_id"])
	changed.emit()
	return true
