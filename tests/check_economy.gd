extends SceneTree

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var trades := TradeService.new()
	var clock := GameClock.new()
	clock.setup(trades)
	root.add_child(clock)
	clock.set_process(false)
	var state := PlayerState.new()
	state.money = 10000
	var inventory := ItemInventory.new()
	_expect(trades.buy("merchantwest", _stack(trades, "merchantwest", "silk"), 4, state, inventory), "deplete configured stock")
	_expect(trades.sell("fence", inventory.get_stacks()[0]["stack_id"], 1, state, inventory), "spend independent fence budget")
	var before: Dictionary = trades.save_snapshot()
	_expect(clock.advance(359.9) and clock.day_index == 0, "day remains zero before 360 active seconds")
	_expect(trades.save_snapshot() == before, "no premature refill")
	var observed: Array[bool] = []
	var listener: Callable = func() -> void:
		var consistent: bool = clock.is_busy()
		for id: String in trades.get_merchant_ids():
			consistent = consistent and trades.get_merchant(id)["last_refill_day"] == clock.day_index
		var saved: Dictionary = clock.save_snapshot()
		consistent = consistent and not clock.advance(360.0) and not clock.restore_snapshot({"day_index": 0, "seconds_in_day": 0}) and clock.save_snapshot() == saved
		observed.append(consistent)
	trades.changed.connect(listener)
	_expect(clock.advance(0.1) and clock.day_index == 1 and clock.seconds_in_day == 0.0, "exact 360 second boundary")
	_expect(observed == [true], "callbacks see all markers and clock committed, reject reentrant clock operations")
	trades.changed.disconnect(listener)
	_expect(_count(trades, "merchantwest", "silk") == 4 and trades.get_merchant("fence")["budget"] == 55, "daily stock and independent budget reach target")
	before = trades.save_snapshot()
	_expect(trades.refill_for_day(1) and clock.advance(0.0) and trades.save_snapshot() == before, "repeat update is idempotent")
	_expect(trades.buy("merchantwest", _stack(trades, "merchantwest", "silk"), 1, state, inventory), "buy after refill")
	before = trades.save_snapshot()
	_expect(trades.refill_for_day(1) and trades.save_snapshot() == before, "same day depletion cannot trigger another grant")
	_expect(not trades.refill_for_day(0) and trades.save_snapshot() == before, "past day request changes nothing")
	_expect(clock.advance(1080.0) and clock.day_index == 4 and clock.seconds_in_day == 0.0 and _count(trades, "merchantwest", "silk") == 4, "skipped days normalize without accumulating grants")
	_expect(clock.advance(359.9), "prepare snapshot before boundary")
	var clock_saved: Dictionary = clock.save_snapshot()
	var trade_saved: Dictionary = trades.save_snapshot()
	_expect(clock.advance(0.1), "cross saved boundary")
	_expect(clock.restore_snapshot(clock_saved) and trades.restore_snapshot(trade_saved), "restore matching time and merchants")
	_expect(clock.save_snapshot() == clock_saved and trades.save_snapshot() == trade_saved, "restoring snapshot does not account for offline time")
	_expect(clock.restore_snapshot(clock_saved) and trades.restore_snapshot(trade_saved) and trades.save_snapshot() == trade_saved, "repeat load cannot accumulate goods")
	_expect(clock.advance(0.1) and _count(trades, "merchantwest", "silk") == 4, "loaded boundary refills once")
	var paused_time: Dictionary = clock.save_snapshot()
	var paused_stock: Dictionary = trades.save_snapshot()
	clock.set_process(true)
	paused = true
	_expect(clock.advance(720.0), "manual advance respects SceneTree pause")
	for frame: int in range(3):
		await process_frame
	_expect(clock.save_snapshot() == paused_time and trades.save_snapshot() == paused_stock, "paused simulation frames freeze time and stock")
	clock.set_process(false)
	paused = false
	_check_invalid_snapshots(trades, clock)
	_check_prices_and_cycles()
	_check_late_failure()
	var extra := ItemInventory.new()
	extra.add_item("silk", 8, {"owner_id": "player", "source_id": "gift"})
	_expect(trades.sell("merchantwest", extra.get_stacks()[0]["stack_id"], 8, state, extra), "sell excess with distinct provenance")
	var stacks_before: Array = trades.get_merchant("merchantwest")["stacks"]
	_expect(clock.advance(360.0) and trades.get_merchant("merchantwest")["stacks"] == stacks_before, "refill preserves surplus and provenance")
	clock.free()
	if failures == 0:
		print("PASS: T17 clock, pause, daily refill, snapshots and bounded no-arbitrage prices")
	quit(1 if failures else 0)


func _check_invalid_snapshots(trades: TradeService, clock: GameClock) -> void:
	var clock_before: Dictionary = clock.save_snapshot()
	for bad: Variant in [null, {}, {"day_index": true, "seconds_in_day": 0}, {"day_index": -1, "seconds_in_day": 0}, {"day_index": 0.5, "seconds_in_day": 0}, {"day_index": 2147483648, "seconds_in_day": 0}, {"day_index": 0, "seconds_in_day": 360}, {"day_index": 0, "seconds_in_day": NAN}, {"day_index": 0, "seconds_in_day": INF}]:
		_expect(not clock.restore_snapshot(bad) and clock.save_snapshot() == clock_before, "invalid clock snapshot rejected without mutation")
	for delta: float in [-1.0, INF, NAN, 1e300]:
		_expect(not clock.advance(delta) and clock.save_snapshot() == clock_before, "invalid or overflowing delta rejected")
	var before: Dictionary = trades.save_snapshot()
	var invalids: Array = [null, {}]
	var bad: Dictionary = before.duplicate(true)
	bad.erase("fence")
	invalids.append(bad)
	bad = before.duplicate(true)
	bad["unknown"] = bad["fence"]
	invalids.append(bad)
	for value: Variant in [true, -1, 1.25, 2147483648, NAN]:
		bad = before.duplicate(true)
		bad["merchantwest"]["budget"] = value
		invalids.append(bad)
	bad = before.duplicate(true)
	bad["merchantwest"]["last_refill_day"] = -1
	invalids.append(bad)
	bad = before.duplicate(true)
	bad["merchantwest"]["inventory"]["stacks"][0]["quantity"] = 2147483648
	invalids.append(bad)
	bad = before.duplicate(true)
	bad["merchantwest"]["inventory"]["stacks"][0]["stolen"] = true
	invalids.append(bad)
	for invalid: Variant in invalids:
		_expect(not trades.restore_snapshot(invalid) and trades.save_snapshot() == before, "invalid merchant snapshot rejected atomically")
	var state := PlayerState.new()
	state.money = TradeService.MAX_AMOUNT
	var inventory := ItemInventory.new()
	inventory.add_item("silk", 1)
	_expect(not trades.sell("merchantwest", inventory.get_stacks()[0]["stack_id"], 1, state, inventory) and inventory.count_item("silk") == 1 and trades.save_snapshot() == before, "dynamic sale refuses money overflow")
	var max_budget: Dictionary = before.duplicate(true)
	max_budget["merchantwest"]["budget"] = TradeService.MAX_AMOUNT
	_expect(trades.restore_snapshot(max_budget), "maximum budget snapshot valid")
	_expect(not trades.buy("merchantwest", _stack(trades, "merchantwest", "silk"), 1, state, inventory) and trades.save_snapshot() == max_budget, "dynamic purchase refuses budget overflow")
	_expect(trades.restore_snapshot(before), "restore after limit cases")


func _check_prices_and_cycles() -> void:
	var trades := TradeService.new()
	var baseline: Dictionary = trades.save_snapshot()
	for item_id: String in ["silk", "spices", "pottery", "copper", "perfume", "bread"]:
		var min_ask: int = TradeService.MAX_AMOUNT
		var max_bid: int = 0
		for amount: int in [0, 1, 3, 4, 5, 6, 8, 100]:
			var snapshot: Dictionary = baseline.duplicate(true)
			for id: String in trades.get_merchant_ids():
				var stock := ItemInventory.new()
				if amount > 0:
					stock.add_item(item_id, amount, {"owner_id": id, "source_id": id})
				snapshot[id]["inventory"] = stock.save_snapshot()
			_expect(trades.restore_snapshot(snapshot), "load valid stock price band")
			for id: String in trades.get_merchant_ids():
				min_ask = mini(min_ask, trades.get_offer_price(id, item_id, true))
				max_bid = maxi(max_bid, trades.get_offer_price(id, item_id, false))
		_expect(max_bid <= min_ask and min_ask > 0, "global max bid <= min ask: " + item_id)
	_expect(trades.restore_snapshot(baseline), "restore before real trade cycles")
	var state := PlayerState.new()
	state.money = 10000
	var inventory := ItemInventory.new()
	for cycle: int in range(12):
		var money_before: int = state.money
		_expect(trades.buy("merchantwest", _stack(trades, "merchantwest", "bread"), 1, state, inventory), "cycle buys actual goods")
		var id: String = "merchantwest" if cycle % 2 == 0 else "merchanteast"
		_expect(trades.sell(id, inventory.get_stacks()[0]["stack_id"], 1, state, inventory), "cycle resells across market")
		_expect(state.money <= money_before and inventory.count_item("bread") == 0, "closed inventory cycle has no profit")
		_expect(trades.refill_for_day(cycle + 1), "cycle includes next-day refill")


func _check_late_failure() -> void:
	var trades := TradeService.new()
	var clock := GameClock.new()
	clock.setup(trades)
	var state := PlayerState.new()
	state.money = 1000
	var inventory := ItemInventory.new()
	_expect(trades.buy("merchantwest", _stack(trades, "merchantwest", "silk"), 4, state, inventory), "prepare first merchant refill")
	_expect(trades.buy("merchanteast", _stack(trades, "merchanteast", "pottery"), 5, state, inventory), "prepare late merchant refill")
	var exhausted: Dictionary = trades.save_snapshot()
	exhausted["merchanteast"]["inventory"]["next_stack_id"] = ItemInventory.MAX_QUANTITY
	_expect(trades.restore_snapshot(exhausted), "exhausted counter snapshot valid")
	var time_before: Dictionary = clock.save_snapshot()
	_expect(not clock.advance(360.0) and clock.save_snapshot() == time_before and trades.save_snapshot() == exhausted, "late refill failure leaves clock and all merchants unchanged")
	clock.free()


func _stack(trades: TradeService, merchant_id: String, item_id: String) -> String:
	for stack: Dictionary in trades.get_merchant(merchant_id)["stacks"]:
		if stack["item_id"] == item_id:
			return stack["stack_id"]
	return ""


func _count(trades: TradeService, merchant_id: String, item_id: String) -> int:
	var count: int = 0
	for stack: Dictionary in trades.get_merchant(merchant_id)["stacks"]:
		if stack["item_id"] == item_id:
			count += int(stack["quantity"])
	return count


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
