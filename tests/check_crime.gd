extends SceneTree

class ReportGuard extends Node2D:
	var guard_id: String = "test_guard"
	var facing: Vector2 = Vector2.RIGHT
	var visibility := VisibilityQuery.new()
	var reports: Array[Vector2] = []

	func can_see(point: Vector2) -> bool:
		return visibility.can_see(self, point, facing)

	func report_crime(point: Vector2) -> void:
		reports.append(point)

var failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var guard := ReportGuard.new()
	world.add_child(guard)
	var owner := CrimeWitness.new()
	owner.owner_id = "merchantwest"
	owner.facing = Vector2.RIGHT
	world.add_child(owner)
	var service := CrimeService.new()
	service.configure([guard], [owner])
	var event: Dictionary = {"owner_id": "merchantwest", "source_id": "chest_west", "position": Vector2(40, 0), "item_id": "silk", "quantity": 1}
	await physics_frame
	await physics_frame
	_expect(service.on_theft_completed(event), "visible guard and owner witness theft")
	_expect(guard.reports == [Vector2(40, 0)], "guard receives crime snapshot")
	event["position"] = Vector2(50, 0)
	_expect(guard.reports == [Vector2(40, 0)], "later event mutation cannot update knowledge")
	guard.facing = Vector2.LEFT
	service.configure([guard], [])
	_expect(not service.on_theft_completed(event), "guard sector prevents magical alarm")
	guard.facing = Vector2.RIGHT
	event["position"] = Vector2(200, 0)
	_expect(not service.on_theft_completed(event), "guard distance prevents magical alarm")
	service.configure([], [])
	event["position"] = Vector2(40, 0)
	_expect(not service.on_theft_completed(event), "no witnesses means no alarm")
	# Owner witness can alert a guard facing away; a different owner cannot.
	guard.facing = Vector2.LEFT
	service.configure([guard], [owner])
	_expect(service.on_theft_completed(event), "owner witnesses and reports to guard")
	event["owner_id"] = "merchanteast"
	_expect(not service.on_theft_completed(event), "unrelated owner does not witness")
	event["owner_id"] = "merchantwest"
	owner.facing = Vector2.LEFT
	_expect(not service.on_theft_completed(event), "owner sector checked")
	var farther_owner := CrimeWitness.new()
	farther_owner.owner_id = owner.owner_id
	farther_owner.facing = Vector2.RIGHT
	farther_owner.position = Vector2(-20, 0)
	world.add_child(farther_owner)
	service.configure([guard], [farther_owner, owner])
	_expect(not service.on_theft_completed(event), "nearest owner selected before visibility, not a farther duplicate")
	farther_owner.free()
	service.configure([guard], [owner])
	owner.facing = Vector2.RIGHT
	owner.position = Vector2(-200, 0)
	_expect(not service.on_theft_completed(event), "owner distance checked")
	owner.position = Vector2.ZERO
	var wall := StaticBody2D.new()
	wall.position = Vector2(20, 0)
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(5, 40)
	shape.shape = rectangle
	wall.add_child(shape)
	world.add_child(wall)
	await physics_frame
	await physics_frame
	guard.facing = Vector2.RIGHT
	_expect(not service.on_theft_completed(event), "wall blocks guard and owner witnesses")
	wall.free()
	await physics_frame
	await physics_frame
	var report_count: int = guard.reports.size()
	service.crime_witnessed.connect(func(_event: Dictionary, _ids: Array[String]) -> void:
		_expect(not service.on_theft_completed(event), "crime signal cannot reenter reports")
	, CONNECT_ONE_SHOT)
	_expect(service.on_theft_completed(event) and guard.reports.size() == report_count + 1, "one snapshot per report")
	_trade_checks()
	world.free()
	if failures == 0:
		print("PASS: T13 witnesses, snapshot reports, fence, provenance and atomic refusal")
	quit(1 if failures else 0)


func _trade_checks() -> void:
	var trades := TradeService.new()
	var state := PlayerState.new()
	var inventory := ItemInventory.new()
	state.money = 20
	var origin: Dictionary = {"stolen": true, "owner_id": "merchantwest", "source_id": "chest_west", "instance_id": "stolen_silk"}
	inventory.add_item("silk", 1, origin)
	var stolen: Dictionary = inventory.get_stacks()[0]
	var before: Dictionary = _snapshot(trades, state, inventory)
	_expect(not trades.sell("merchantwest", stolen["stack_id"], 1, state, inventory), "lawful merchant rejects stolen goods")
	_expect(trades.last_error.contains("краденое") and _snapshot(trades, state, inventory) == before, "lawful refusal explains and changes nothing")
	var fence_before: Dictionary = trades.get_merchant("fence")
	var price: int = trades.get_offer_price("fence", "silk", false)
	_expect(price > 0 and price < trades.get_sell_price("silk"), "fence offer cheaper than lawful resale")
	var observed: Array[bool] = []
	var reentry: Array[bool] = []
	inventory.changed.connect(func() -> void:
		observed.append(state.money == 20 + price and inventory.count_item("silk") == 0 and trades.get_merchant("fence")["budget"] == fence_before["budget"] - price)
		reentry.append(trades.sell("fence", stolen["stack_id"], 1, state, inventory))
	, CONNECT_ONE_SHOT)
	_expect(trades.sell("fence", stolen["stack_id"], 1, state, inventory), "fence purchases stolen good")
	_expect(observed == [true] and reentry == [false], "callbacks see settled trade and cannot reenter")
	var acquired: Dictionary = trades.get_merchant("fence")["stacks"][0]
	for key: String in origin:
		_expect(acquired[key] == origin[key], "fence retains " + key)
	_expect(trades.buy("fence", acquired["stack_id"], 1, state, inventory), "finite fence stock can be bought back")
	_expect(inventory.get_stacks()[0]["stolen"] and inventory.get_stacks()[0]["instance_id"] == "stolen_silk", "buyback cannot launder or replace identity")
	_expect(not trades.sell("merchanteast", inventory.get_stacks()[0]["stack_id"], 1, state, inventory), "bought-back stolen goods still refused")
	inventory.add_item("lamp", 1)
	var lamp: Dictionary = inventory.get_stacks()[1]
	before = _snapshot(trades, state, inventory)
	_expect(not trades.sell("fence", lamp["stack_id"], 1, state, inventory) and _snapshot(trades, state, inventory) == before, "fence ordinary trade excludes lamp atomically")
	inventory.add_item("perfume", 100, {"stolen": true, "owner_id": "victim", "source_id": "large_chest"})
	var perfume: Dictionary = inventory.get_stacks()[2]
	before = _snapshot(trades, state, inventory)
	_expect(not trades.sell("fence", perfume["stack_id"], 100, state, inventory) and _snapshot(trades, state, inventory) == before, "finite fence budget rejects bulk sale atomically")
	inventory.add_item("bread", 1, {"owner_id": "player", "source_id": "gift"})
	var bread: Dictionary = inventory.get_stacks()[3]
	_expect(trades.sell("merchantwest", bread["stack_id"], 1, state, inventory), "legal trade remains working")
	var ui := TradeUI.new()
	root.add_child(ui)
	ui.setup(trades, state, inventory, "merchantwest")
	ui._switch_mode(false)
	var refusal_button: Button = ui._rows.get_child(0).get_child(1) as Button
	_expect(not refusal_button.disabled and refusal_button.text == "Отказ", "lawful GUI exposes actionable refusal")
	refusal_button.pressed.emit()
	_expect(ui._message.text.contains("краденое"), "lawful GUI displays refusal reason")
	ui.setup(trades, state, inventory, "fence")
	ui._switch_mode(false)
	var fence_button: Button = ui._rows.get_child(0).get_child(1) as Button
	_expect(fence_button.text == "Продать %d д." % price and not fence_button.disabled, "fence GUI displays actual discounted offer")
	ui.free()


func _snapshot(trades: TradeService, state: PlayerState, inventory: ItemInventory) -> Dictionary:
	return {"money": state.money, "inventory": inventory.get_stacks(), "fence": trades.get_merchant("fence"), "west": trades.get_merchant("merchantwest"), "east": trades.get_merchant("merchanteast")}


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
