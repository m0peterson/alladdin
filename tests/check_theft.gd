extends SceneTree

var failures: int = 0
var world: Node2D
var actor: Node2D
var interactions: InteractionController
var controller: TheftController
var inventory: ItemInventory
var completed: Array[Dictionary] = []
var ui: TheftUI


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not InputMap.has_action("steal"):
		InputMap.add_action("steal")
	world = Node2D.new()
	root.add_child(world)
	actor = Node2D.new()
	world.add_child(actor)
	interactions = InteractionController.new()
	root.add_child(interactions)
	interactions.set_process(false)
	interactions.set_player(actor)
	inventory = ItemInventory.new()
	controller = TheftController.new()
	root.add_child(controller)
	controller.set_process(false)
	controller.setup(actor, inventory, interactions)
	controller.theft_completed.connect(func(event: Dictionary) -> void: completed.append(event.duplicate(true)))
	ui = TheftUI.new()
	root.add_child(ui)
	ui.setup(controller)
	await physics_frame
	await process_frame
	var target: TheftTarget = _make_target("silk", 2)
	_release()
	Input.action_press("steal")
	controller._process(0.6)
	_expect(inventory.count_item("silk") == 0 and target.stock.count_item("silk") == 2 and ui.visible, "partial hold displays progress without transferring")
	var observed: Array[bool] = []
	inventory.changed.connect(func() -> void:
		observed.append(target.stock.get_stacks().is_empty() and inventory.count_item("silk") == 2)
		_expect(target.transfer_to(inventory, actor).is_empty(), "stock callback cannot reenter theft")
		controller._process(5.0)
	, CONNECT_ONE_SHOT)
	actor.position = Vector2(3, 4)
	controller._process(0.5)
	_expect(observed == [true], "inventory observers see atomically settled source and destination")
	_expect(completed.size() == 1 and target.stock.get_stacks().is_empty(), "one success empties finite source")
	var loot: Dictionary = inventory.get_stacks()[0]
	_expect(loot["stolen"] and loot["owner_id"] == "owner" and loot["source_id"] == target.target_id, "stolen owner and source survive transfer")
	_expect(completed[0]["position"] == Vector2(3, 4) and completed[0]["quantity"] == 2 and completed[0]["item_id"] == "silk" and completed[0]["owner_id"] == "owner", "crime event contains success-time position and item snapshot")
	actor.position = Vector2.ZERO
	_expect(completed[0]["position"] == Vector2(3, 4), "crime event never follows player")
	controller._process(10.0)
	_release()
	Input.action_press("steal")
	controller._process(10.0)
	_expect(completed.size() == 1 and inventory.count_item("silk") == 2, "held and repeated input on empty source cannot duplicate")
	_expect(not target.seed("silk", 2), "finite source cannot be seeded again")

	# Release and distance both discard accumulated progress.
	target = _make_target("spices", 1)
	_release()
	Input.action_press("steal")
	controller._process(0.8)
	_release()
	Input.action_press("steal")
	controller._process(0.3)
	_expect(inventory.count_item("spices") == 0, "release cancels progress")
	actor.position = Vector2(100, 0)
	controller._process(2.0)
	actor.position = Vector2.ZERO
	controller._process(2.0)
	_expect(inventory.count_item("spices") == 0 and target.stock.count_item("spices") == 1, "walking away cancels and requires release")
	_release()
	Input.action_press("steal")
	controller._process(0.5)
	interactions.current_target = null
	controller._process(1.0)
	interactions.current_target = target
	controller._process(2.0)
	_expect(inventory.count_item("spices") == 0, "losing displayed target cancels without silent reacquisition")
	_release()
	Input.action_press("steal")
	controller._process(0.5)
	var other: TheftTarget = _make_target("bread", 1)
	controller._process(2.0)
	_expect(other.stock.count_item("bread") == 1 and target.stock.count_item("spices") == 1, "target change cannot silently switch theft")

	# Every modal stop suppresses the key until an actual release.
	interactions.current_target = target
	_release()
	Input.action_press("steal")
	controller._process(0.7)
	paused = true
	controller._process(3.0)
	paused = false
	controller._process(3.0)
	_expect(inventory.count_item("spices") == 0, "pause cancels hold and blocks retained F")
	_release()
	Input.action_press("steal")
	controller._process(0.7)
	var button := Button.new()
	root.add_child(button)
	button.grab_focus()
	controller._process(3.0)
	button.release_focus()
	controller._process(3.0)
	_expect(inventory.count_item("spices") == 0, "GUI focus cancels and blocks retained F")
	button.free()
	_release()
	Input.action_press("steal")
	controller._process(0.7)
	controller.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	controller._process(3.0)
	_expect(inventory.count_item("spices") == 0, "application focus loss cancels hold")
	_release()
	Input.action_press("steal")
	controller._process(1.1)
	_expect(inventory.count_item("spices") == 1, "fresh F after modal release succeeds")

	# A full destination and duplicate quest item leave both inventories unchanged.
	inventory.add_item("copper", ItemInventory.MAX_QUANTITY)
	target = _make_target("copper", 1)
	var before: Array[Dictionary] = inventory.get_stacks()
	_release()
	Input.action_press("steal")
	controller._process(2.0)
	_expect(inventory.get_stacks() == before and target.stock.count_item("copper") == 1, "capacity failure has no partial effect")
	target = _make_target("lamp", 1)
	_release()
	Input.action_press("steal")
	controller._process(1.1)
	var lamp: Dictionary = _find_item("lamp")
	_expect(inventory.count_item("lamp") == 1 and lamp.get("instance_id") == ItemCatalog.LAMP_INSTANCE_ID and lamp.get("stolen") == true, "lamp uses same theft path and stable unique provenance")
	target = _make_target("lamp", 1)
	before = inventory.get_stacks()
	_release()
	Input.action_press("steal")
	controller._process(2.0)
	_expect(inventory.get_stacks() == before and target.stock.count_item("lamp") == 1, "duplicate lamp refused atomically")

	target = _make_target("perfume", 1)
	_release()
	Input.action_press("steal")
	controller._process(0.5)
	target.free()
	controller._process(2.0)
	_expect(inventory.count_item("perfume") == 0, "freed target cancels safely")

	# Invalidating geometry while holding uses the same ray query as E.
	target = _make_target("perfume", 1)
	target.position = Vector2(24, 0)
	_release()
	Input.action_press("steal")
	controller._process(0.5)
	var wall := StaticBody2D.new()
	wall.position = Vector2(12, -3)
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(2, 16)
	collider.shape = rectangle
	wall.add_child(collider)
	world.add_child(wall)
	await physics_frame
	await process_frame
	controller._process(2.0)
	_expect(inventory.count_item("perfume") == 0 and target.stock.count_item("perfume") == 1, "wall appearing during hold cancels through shared availability query")
	wall.free()
	target.position = Vector2.ZERO
	_release()
	Input.action_press("steal")
	controller._process(0.5)
	target.free()
	target = _make_target("perfume", 1)
	controller._process(2.0)
	_expect(inventory.count_item("perfume") == 0, "deleted hold target cannot be replaced silently")

	# Opening GUI from a progress listener cannot complete the theft in that frame.
	target = _make_target("perfume", 1)
	_release()
	controller.progress_changed.connect(func(_ratio: float, active: bool) -> void:
		if active:
			paused = true
	, CONNECT_ONE_SHOT)
	Input.action_press("steal")
	controller._process(2.0)
	_expect(inventory.count_item("perfume") == 0 and target.stock.count_item("perfume") == 1, "completion revalidates modal state after progress callbacks")
	paused = false
	Input.action_release("steal")
	print("PASS: T12 hold, cancellation, finite stock, provenance, atomicity, GUI, lamp" if failures == 0 else "FAIL: T12 %d checks" % failures)
	world.free()
	ui.free()
	controller.free()
	interactions.free()
	quit(0 if failures == 0 else 1)


func _make_target(item_id: String, quantity: int) -> TheftTarget:
	var target := TheftTarget.new()
	target.target_id = "container_%d" % world.get_child_count()
	target.owner_id = "owner"
	target.display_name = "Ящик"
	world.add_child(target)
	_expect(target.seed(item_id, quantity), "seed finite target: " + item_id)
	interactions.current_target = target
	return target


func _release() -> void:
	Input.action_release("steal")
	controller._process(0.0)


func _find_item(item_id: String) -> Dictionary:
	for stack: Dictionary in inventory.get_stacks():
		if stack["item_id"] == item_id:
			return stack
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
