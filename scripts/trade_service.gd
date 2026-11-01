class_name TradeService
extends RefCounted

signal changed

const MAX_AMOUNT: int = 2147483647
var last_error: String = ""
var _merchants: Dictionary = {}
var _busy: bool = false
var _targets: Dictionary = {}


func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/merchants.json"))
	for entry: Dictionary in data.get("merchants", []):
		var stock := ItemInventory.new()
		var merchant_id: String = entry["id"]
		for row: Dictionary in entry["stock"]:
			stock.add_item(row["item_id"], int(row["quantity"]), {
				"owner_id": merchant_id, "source_id": merchant_id,
			})
		_targets[merchant_id] = {"budget": int(entry["budget"]), "stock": entry["stock"].duplicate(true)}
		_merchants[merchant_id] = {"last_refill_day": 0, "name": entry["name"], "budget": int(entry["budget"]), "inventory": stock, "fence": bool(entry.get("fence", false))}


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
		"stacks": (merchant["inventory"] as ItemInventory).get_stacks(), "fence": merchant["fence"],
		"last_refill_day": merchant["last_refill_day"]}


func get_buy_price(item_id: String) -> int:
	return int(ItemCatalog.get_item(item_id).get("price", 0))


func get_sell_price(item_id: String) -> int:
	return maxi(1, get_buy_price(item_id) / 2) if get_buy_price(item_id) > 0 else 0


func is_fence(merchant_id: String) -> bool:
	return bool(_merchants.get(merchant_id, {}).get("fence", false))


func get_offer_price(merchant_id: String, item_id: String, buying: bool = true) -> int:
	if not _merchants.has(merchant_id):
		return 0
	var base: int = get_buy_price(item_id)
	# Bound before multiplication. Save data cannot supply prices or targets.
	if base <= 0 or base > MAX_AMOUNT / 120:
		return 0
	var multiplier: int = 100
	var stock: ItemInventory = _merchants[merchant_id]["inventory"]
	for row: Dictionary in _targets[merchant_id]["stock"]:
		if row["item_id"] == item_id:
			var target: int = int(row["quantity"])
			var remaining: int = stock.count_item(item_id)
			multiplier = 120 if remaining < target else (80 if remaining > target else 100)
			break
	var ask: int = maxi(1, base * multiplier / 100)
	if buying:
		return ask
	var bid: int = maxi(1, ask / 2)
	return maxi(1, bid / 2) if is_fence(merchant_id) else bid


func get_trade_refusal(merchant_id: String, stack: Dictionary, _buying: bool = false) -> String:
	if not _merchants.has(merchant_id):
		return "Торговец недоступен."
	var item_id: String = str(stack.get("item_id", ""))
	var item: Dictionary = ItemCatalog.get_item(item_id)
	if not item.get("sellable", false) or item.get("type", "") == "quest" or item_id == "lamp":
		return "Этот предмет нельзя продать."
	if stack.get("stolen", false) and not is_fence(merchant_id):
		return "Законный торговец не принимает краденое."
	return ""


func is_busy() -> bool:
	return _busy


# Plain data; the clock and merchants belong to one atomic world snapshot.
func save_snapshot() -> Dictionary:
	var result: Dictionary = {}
	for merchant_id: String in _merchants:
		var merchant: Dictionary = _merchants[merchant_id]
		result[merchant_id] = {"budget": merchant["budget"],
			"inventory": (merchant["inventory"] as ItemInventory).save_snapshot(),
			"last_refill_day": merchant["last_refill_day"]}
	return result


func validate_snapshot(data: Variant) -> String:
	if data is not Dictionary or data.size() != _merchants.size():
		return "Неверный набор торговцев."
	var instances: Dictionary = {}
	for merchant_id: String in _merchants:
		if data.get(merchant_id) is not Dictionary:
			return "Торговец отсутствует в сохранении."
		var row: Dictionary = data[merchant_id]
		if row.size() != 3 or not _integer_in(row.get("budget"), 0, MAX_AMOUNT) or not _integer_in(row.get("last_refill_day"), 0, MAX_AMOUNT):
			return "Неверный бюджет или день пополнения."
		var error: String = ItemInventory.validate_snapshot(row.get("inventory"))
		if not error.is_empty():
			return error
		for stack: Dictionary in row["inventory"]["stacks"]:
			if not get_trade_refusal(merchant_id, stack).is_empty():
				return "Недопустимый товар у торговца."
			var instance_id: String = stack["instance_id"]
			if not instance_id.is_empty():
				if instances.has(instance_id):
					return "Повторный уникальный предмет у торговцев."
				instances[instance_id] = true
	return ""


# Silent: WorldSave validates and commits all world sections before notifications.
func restore_snapshot(data: Variant) -> bool:
	if _busy:
		return false
	last_error = validate_snapshot(data)
	if not last_error.is_empty():
		return false
	var prepared: Dictionary = _prepare_inventories(data)
	for merchant_id: String in _merchants:
		_merchants[merchant_id]["inventory"] = prepared[merchant_id]
		_merchants[merchant_id]["budget"] = int(data[merchant_id]["budget"])
		_merchants[merchant_id]["last_refill_day"] = int(data[merchant_id]["last_refill_day"])
	return true


# Top up rather than accumulate skipped-day grants. Prepare every merchant first.
func refill_for_day(day: int, emit_change: bool = true) -> bool:
	if _busy or day < 0 or day > MAX_AMOUNT:
		return false
	var snapshot: Dictionary = save_snapshot()
	var prepared: Dictionary = _prepare_inventories(snapshot)
	var modified: bool = false
	for merchant_id: String in _merchants:
		var row: Dictionary = snapshot[merchant_id]
		if int(row["last_refill_day"]) > day:
			return _reject("Нельзя вернуть экономику в прошлый день.")
		if int(row["last_refill_day"]) == day:
			continue
		modified = true
		var inventory: ItemInventory = prepared[merchant_id]
		for target: Dictionary in _targets[merchant_id]["stock"]:
			var item_id: String = target["item_id"]
			var missing: int = maxi(0, int(target["quantity"]) - inventory.count_item(item_id))
			if missing > 0 and not inventory.add_item(item_id, missing, {"owner_id": merchant_id, "source_id": merchant_id}):
				return _reject("Не удалось пополнить товар.")
		row["budget"] = maxi(int(row["budget"]), int(_targets[merchant_id]["budget"]))
		row["last_refill_day"] = day
	if not modified:
		return true
	_busy = true
	for merchant_id: String in _merchants:
		_merchants[merchant_id]["inventory"] = prepared[merchant_id]
		_merchants[merchant_id]["budget"] = snapshot[merchant_id]["budget"]
		_merchants[merchant_id]["last_refill_day"] = day
	if emit_change:
		changed.emit()
	_busy = false
	return true


func _prepare_inventories(data: Dictionary) -> Dictionary:
	var prepared: Dictionary = {}
	for merchant_id: String in _merchants:
		var inventory := ItemInventory.new()
		var restored: bool = inventory.restore_snapshot(data[merchant_id]["inventory"])
		assert(restored, "Validated merchant inventory must restore")
		prepared[merchant_id] = inventory
	return prepared


static func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	if value is not int and value is not float:
		return false
	return is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum


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
	var refusal: String = get_trade_refusal(merchant_id, stack, buying)
	if not refusal.is_empty():
		return _reject(refusal)
	var price: int = get_offer_price(merchant_id, item_id, buying)
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
