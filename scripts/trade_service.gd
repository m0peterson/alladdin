class_name TradeService
extends RefCounted

signal changed

const MAX_AMOUNT: int = 2147483647
var last_error: String = ""
var _merchants: Dictionary = {}
var _busy: bool = false


func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/merchants.json"))
	for entry: Dictionary in data.get("merchants", []):
		var stock := ItemInventory.new()
		var merchant_id: String = entry["id"]
		for row: Dictionary in entry["stock"]:
			stock.add_item(row["item_id"], int(row["quantity"]), {
				"owner_id": merchant_id, "source_id": merchant_id,
			})
		_merchants[merchant_id] = {"name": entry["name"], "budget": int(entry["budget"]), "inventory": stock}


func get_merchant_ids() -> Array[String]:
	var result: Array[String] = []
	for merchant_id: String in _merchants:
		result.append(merchant_id)
	return result


func get_merchant(merchant_id: String) -> Dictionary:
	if not _merchants.has(merchant_id):
		return {}
	var merchant: Dictionary = _merchants[merchant_id]
	return {"id": merchant_id, "name": merchant["name"], "budget": merchant["budget"],
		"stacks": (merchant["inventory"] as ItemInventory).get_stacks()}


func get_buy_price(item_id: String) -> int:
	return int(ItemCatalog.get_item(item_id).get("price", 0))


func get_sell_price(item_id: String) -> int:
	return maxi(1, get_buy_price(item_id) / 2) if get_buy_price(item_id) > 0 else 0


func buy(merchant_id: String, stack_id: String, quantity: int, player_state: PlayerState, inventory: ItemInventory) -> bool:
	return _trade(merchant_id, stack_id, quantity, player_state, inventory, true)


func sell(merchant_id: String, stack_id: String, quantity: int, player_state: PlayerState, inventory: ItemInventory) -> bool:
	return _trade(merchant_id, stack_id, quantity, player_state, inventory, false)


func _reject(message: String) -> bool:
	last_error = message
	return false


func _trade(merchant_id: String, stack_id: String, quantity: int, state: PlayerState, player_inventory: ItemInventory, buying: bool) -> bool:
	if _busy:
		return false
	last_error = ""
	if state == null or player_inventory == null or not _merchants.has(merchant_id):
		return _reject("Торговец недоступен.")
	if quantity <= 0 or quantity > MAX_AMOUNT:
		return _reject("Недопустимое количество.")
	var merchant: Dictionary = _merchants[merchant_id]
	var stock: ItemInventory = merchant["inventory"]
	var source: ItemInventory = stock if buying else player_inventory
	var destination: ItemInventory = player_inventory if buying else stock
	var stack: Dictionary = source.get_stack(stack_id)
	if stack.is_empty() or int(stack["quantity"]) < quantity:
		return _reject("Недостаточно товара.")
	var item_id: String = stack["item_id"]
	var item: Dictionary = ItemCatalog.get_item(item_id)
	if not item.get("sellable", false) or item.get("type", "") == "quest" or item_id == "lamp":
		return _reject("Этот предмет нельзя продать.")
	if stack["stolen"]:
		return _reject("Законный торговец не принимает краденое.")
	var price: int = get_buy_price(item_id) if buying else get_sell_price(item_id)
	# Cap before multiplication so invalid quantities cannot overflow money.
	if price <= 0 or quantity > MAX_AMOUNT / price:
		return _reject("Слишком большая сделка.")
	var total: int = price * quantity
	if buying and state.money < total:
		return _reject("Не хватает динаров.")
	if not buying and int(merchant["budget"]) < total:
		return _reject("У торговца не хватает динаров.")
	if (buying and int(merchant["budget"]) > MAX_AMOUNT - total) or (not buying and state.money > MAX_AMOUNT - total):
		return _reject("Слишком большая сумма.")
	var provenance := {"stolen": stack["stolen"], "owner_id": stack["owner_id"],
		"source_id": stack["source_id"], "instance_id": stack["instance_id"]}
	if not destination.can_add_item(item_id, quantity, provenance):
		return _reject("Нет места для товара.")
	# No callbacks can alter preflighted inventories while committing. Observers
	# receive signals only after both items and both money balances are settled.
	_busy = true
	var source_blocked: bool = source.is_blocking_signals()
	var destination_blocked: bool = destination.is_blocking_signals()
	var state_blocked: bool = state.is_blocking_signals()
	source.set_block_signals(true)
	destination.set_block_signals(true)
	state.set_block_signals(true)
	var removed: bool = source.remove_item(stack_id, quantity)
	var added: bool = false
	if removed:
		added = destination.add_item(item_id, quantity, provenance)
	# Both operations are guaranteed by inventory preflight and synchronous API.
	assert(removed and added, "Trade inventory contract violated after preflight")
	if removed and added:
		state.money += -total if buying else total
		merchant["budget"] += total if buying else -total
	source.set_block_signals(source_blocked)
	destination.set_block_signals(destination_blocked)
	state.set_block_signals(state_blocked)
	if removed and added:
		if not source_blocked:
			source.changed.emit()
		if not destination_blocked:
			destination.changed.emit()
		if not state_blocked:
			state.changed.emit()
		changed.emit()
	_busy = false
	return removed and added
