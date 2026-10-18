extends SceneTree

var failures: int = 0
var service: TradeService
var state: PlayerState
var inventory: ItemInventory


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	service = TradeService.new()
	state = PlayerState.new()
	state.money = 100
	inventory = ItemInventory.new()
	_expect(service.get_merchant_ids().size() == 3, "two legal merchants and fence")
	_expect(service.is_fence("fence"), "fence has separate trade")
	var west: Dictionary = service.get_merchant("merchantwest")
	var east: Dictionary = service.get_merchant("merchanteast")
	var west_stack: Dictionary = west["stacks"][0]
	var item_id: String = west_stack["item_id"]
	var price: int = service.get_buy_price(item_id)
	var initial_quantity: int = west_stack["quantity"]
	var initial_budget: int = west["budget"]
	var signal_states: Array[bool] = []
	inventory.changed.connect(func() -> void:
		signal_states.append(state.money == 100 - price * 2 and inventory.count_item(item_id) == 2 and service.get_merchant("merchantwest")["budget"] == initial_budget + price * 2)
	, CONNECT_ONE_SHOT)
	_expect(service.buy("merchantwest", west_stack["stack_id"], 2, state, inventory), "buy two goods")
	_expect(signal_states == [true], "observers see completely settled transaction")
	_expect(state.money == 100 - price * 2, "player pays full buy price")
	_expect(service.get_merchant("merchantwest")["stacks"][0]["quantity"] == initial_quantity - 2, "stock deducted")
	_expect(service.get_merchant("merchanteast") == east, "other merchant unchanged")
	var bought: Dictionary = inventory.get_stacks()[0]
	_expect(bought["owner_id"] == west_stack["owner_id"] and bought["source_id"] == west_stack["source_id"] and not bought["stolen"], "buy retains provenance")
	_expect(service.sell("merchantwest", bought["stack_id"], 2, state, inventory), "sell two goods")
	_expect(state.money <= 100 and inventory.count_item(item_id) == 0, "round trip has no profit")
	_expect(service.get_merchant("merchantwest")["stacks"][0]["quantity"] == initial_quantity, "round trip restores stock")
	# Accessors expose copies, never mutable stock or budget handles.
	west["budget"] = 0
	west["stacks"][0]["quantity"] = 0
	_expect(service.get_merchant("merchantwest")["budget"] > 0, "merchant snapshot cannot change budget")
	_expect(service.get_merchant("merchantwest")["stacks"][0]["quantity"] == initial_quantity, "merchant snapshot cannot change stock")
	state.money = 0
	_refusal(true, "merchantwest", west_stack["stack_id"], 1, "insufficient player money")
	state.money = 100
	_refusal(true, "merchantwest", west_stack["stack_id"], initial_quantity + 1, "insufficient stock")
	_refusal(true, "missing", west_stack["stack_id"], 1, "unknown merchant")
	_refusal(true, "merchantwest", "missing", 1, "unknown stack")
	_refusal(true, "merchantwest", west_stack["stack_id"], 0, "zero quantity")
	_refusal(true, "merchantwest", west_stack["stack_id"], -1, "negative quantity")
	_refusal(true, "merchantwest", west_stack["stack_id"], 9223372036854775807, "overflow quantity")
	inventory.add_item("perfume", 100, {"source_id": "gift", "owner_id": "player"})
	var perfume: Dictionary = _find_stack("perfume")
	_refusal(false, "merchanteast", perfume["stack_id"], 100, "insufficient merchant budget")
	inventory.add_item("silk", 1, {"stolen": true, "owner_id": "victim", "source_id": "warehouse"})
	var stolen: Dictionary = _find_stack("silk")
	_refusal(false, "merchantwest", stolen["stack_id"], 1, "stolen goods rejected west")
	_refusal(false, "merchanteast", stolen["stack_id"], 1, "stolen goods rejected east")
	inventory.add_item("lamp", 1, {"instance_id": "quest_lamp", "source_id": "quest"})
	var lamp: Dictionary = _find_stack("lamp")
	_refusal(false, "merchantwest", lamp["stack_id"], 1, "quest lamp rejected")
	_expect(inventory.count_item("lamp") == 1, "quest lamp retained")
	# Destination overflow rejects before money, source stock or provenance changes.
	inventory.add_item("bread", 2147483647, {"owner_id": "merchantwest", "source_id": "merchantwest"})
	var bread_id: String = ""
	for stack: Dictionary in service.get_merchant("merchantwest")["stacks"]:
		if stack["item_id"] == "bread":
			bread_id = stack["stack_id"]
	_refusal(true, "merchantwest", bread_id, 1, "destination overflow")
	# A good can also be sold to the other lawful merchant without laundering.
	_expect(service.sell("merchantwest", perfume["stack_id"], 1, state, inventory), "merchant buys legitimate goods")
	var acquired: Dictionary = {}
	for stack: Dictionary in service.get_merchant("merchantwest")["stacks"]:
		if stack["item_id"] == "perfume":
			acquired = stack
	_expect(acquired.get("source_id") == "gift" and acquired.get("owner_id") == "player", "sale retains distinct provenance")
	# Unique ordinary instances also retain their identity in both directions.
	inventory.add_item("copper", 1, {"instance_id": "keepsake_copper", "source_id": "gift", "owner_id": "player"})
	var unique: Dictionary = _find_stack("copper")
	var money_before_unique: int = state.money
	_expect(service.sell("merchanteast", unique["stack_id"], 1, state, inventory), "second merchant has independent working budget")
	for stack: Dictionary in service.get_merchant("merchanteast")["stacks"]:
		if stack["instance_id"] == "keepsake_copper":
			unique = stack
	_expect(service.buy("merchanteast", unique["stack_id"], 1, state, inventory), "buy unique legitimate instance back")
	_expect(_find_stack("copper")["instance_id"] == "keepsake_copper" and state.money <= money_before_unique, "instance ID retained without round trip profit")
	for id: String in ["silk", "spices", "pottery", "copper", "perfume", "bread"]:
		_expect(service.get_sell_price(id) <= service.get_buy_price(id), "no arbitrage across merchants: " + id)
	# GUI can be constructed while paused, displays both modes, delegates actions.
	var ui := TradeUI.new()
	root.add_child(ui)
	ui.setup(service, state, inventory, "merchantwest")
	ui.show()
	paused = true
	_expect(ui.process_mode == Node.PROCESS_MODE_ALWAYS and ui.visible, "trade GUI works during root pause")
	var before_gui: int = state.money
	ui._transact(str(service.get_merchant("merchantwest")["stacks"][0]["stack_id"]))
	_expect(state.money == before_gui - price and ui._message.text == "Сделка завершена.", "GUI buy delegates full transaction to service")
	ui._switch_mode(false)
	_expect(ui._rows.get_child_count() == inventory.get_stacks().size(), "sell view displays inventory")
	var closes: Array[bool] = []
	ui.closed.connect(func() -> void: closes.append(true))
	ui.close()
	_expect(closes == [true] and not ui.visible and paused, "close emits signal; root owns pause")
	paused = false
	ui.free()
	if failures == 0:
		print("PASS: T07 atomic trade, refusals, provenance, round trip and GUI contract")
	quit(1 if failures else 0)


func _find_stack(item_id: String) -> Dictionary:
	for stack: Dictionary in inventory.get_stacks():
		if stack["item_id"] == item_id:
			return stack
	return {}


func _snapshot() -> Dictionary:
	return {"money": state.money, "inventory": inventory.get_stacks(),
		"west": service.get_merchant("merchantwest"), "east": service.get_merchant("merchanteast")}


func _refusal(buying: bool, merchant_id: String, stack_id: String, quantity: int, label: String) -> void:
	var before: Dictionary = _snapshot()
	var result: bool = service.buy(merchant_id, stack_id, quantity, state, inventory) if buying else service.sell(merchant_id, stack_id, quantity, state, inventory)
	_expect(not result and not service.last_error.is_empty(), label + " returns reason")
	_expect(_snapshot() == before, label + " changes nothing")


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
