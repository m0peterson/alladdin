extends SceneTree

var failures: int = 0
var changes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var inv: ItemInventory = ItemInventory.new()
	inv.changed.connect(func() -> void: changes += 1)
	var legal: Dictionary = {"owner_id": "player", "source_id": "starter"}
	var stolen: Dictionary = {"stolen": true, "owner_id": "merchant_a", "source_id": "crate_a"}
	var other: Dictionary = {"stolen": true, "owner_id": "merchant_b", "source_id": "crate_b"}
	_expect(ItemCatalog.get_item_ids().size() == 7, "five goods, food and lamp catalog")
	for item_id: String in ItemCatalog.get_item_ids():
		var item: Dictionary = ItemCatalog.get_item(item_id)
		_expect(item["price"] is int and item["price"] >= 0, "integer nonnegative price")
		_expect(not item["description"].is_empty() and ResourceLoader.exists(item["icon"]), "description and real icon")
	var item_copy: Dictionary = ItemCatalog.get_item("bread")
	item_copy["heal"] = 999
	_expect(ItemCatalog.get_item("bread")["heal"] == 25, "catalog returns independent copy")
	_expect(inv.can_add_item("silk", 2, legal) and inv.get_stacks().is_empty() and changes == 0, "preflight is read only")
	_expect(inv.add_item("silk", 2, legal) and inv.add_item("silk", 3, legal), "matching origins merge")
	_expect(inv.get_stacks().size() == 1 and inv.count_item("silk") == 5, "merged exact count")
	_expect(inv.add_item("silk", 2, stolen) and inv.add_item("silk", 1, other), "same goods preserve separate owners and sources")
	_expect(inv.get_stacks().size() == 3 and inv.count_item("silk") == 8, "three distinct provenance stacks")
	var source_only: Dictionary = stolen.duplicate()
	source_only["source_id"] = "crate_other"
	_expect(inv.add_item("silk", 1, source_only) and inv.get_stacks().size() == 4, "same owner distinct source stays separate")
	var origins: ItemInventory = ItemInventory.new()
	var same_owner: Dictionary = stolen.duplicate()
	same_owner["stolen"] = false
	_expect(origins.add_item("spices", 1, stolen) and origins.add_item("spices", 1, same_owner), "legal and stolen with identical owner/source accepted")
	_expect(origins.get_stacks().size() == 2, "stolen flag alone prevents merging")
	var instance: Dictionary = {"instance_id": "family_bowl", "owner_id": "player", "source_id": "gift"}
	_expect(origins.add_item("pottery", 1, instance), "explicit unique ordinary instance accepted")
	instance["owner_id"] = "tampered"
	_expect(origins.get_stacks().back()["owner_id"] == "player", "input provenance cannot mutate stored origin")
	_expect(not origins.add_item("pottery", 1, instance) and not origins.add_item("copper", 1, instance), "duplicate instance refused across item IDs")
	var snapshot: Array[Dictionary] = inv.get_stacks()
	var stack_id: String = snapshot[0]["stack_id"]
	snapshot[0]["quantity"] = -1
	var single: Dictionary = inv.get_stack(stack_id)
	single["stolen"] = true
	_expect(inv.get_stack(stack_id)["quantity"] == 5 and not inv.get_stack(stack_id)["stolen"], "all reads are defensive copies")
	var before: Array[Dictionary] = inv.get_stacks()
	var signals_before: int = changes
	for quantity: int in [0, -1, ItemInventory.MAX_QUANTITY, 9223372036854775807]:
		_expect(not inv.add_item("silk", quantity, legal), "invalid/overflow quantity refused")
		_expect(not inv.remove_item(stack_id, quantity), "invalid removal refused")
	_expect(not inv.add_item("unknown", 1), "unknown item rejected")
	_expect(not inv.add_item("silk", 1, {"stolen": 1}), "invalid stolen type rejected")
	_expect(not inv.add_item("silk", 1, {"stolen": true}), "stolen item requires owner and source")
	_expect(not inv.add_item("silk", 1, {"owner_id": 7}), "invalid origin type rejected")
	_expect(not inv.remove_item("missing", 1), "missing stack refused")
	_expect(inv.get_stacks() == before and changes == signals_before, "all refusals preserve state and signal count")
	_expect(inv.remove_item(stack_id, 4) and inv.get_stack(stack_id)["quantity"] == 1, "partial removal exact")
	_expect(inv.remove_item(stack_id, 1) and inv.get_stack(stack_id).is_empty(), "zero stack removed")
	_expect(inv.add_item("silk", 1, legal), "re-add after removal")
	_expect(inv.get_stacks().back()["stack_id"] != stack_id, "stack identifiers never reused")
	var lamp_origin: Dictionary = {"owner_id": "warehouse", "source_id": "lamp_plinth"}
	_expect(not inv.add_item("lamp", 2, lamp_origin), "lamp quantity must be one")
	_expect(not inv.add_item("lamp", 1, {"instance_id": "fake_lamp"}), "lamp identity fixed")
	_expect(inv.add_item("lamp", 1, lamp_origin), "one lamp accepted")
	var lamp: Dictionary = inv.get_stacks().back()
	_expect(lamp["instance_id"] == ItemCatalog.LAMP_INSTANCE_ID, "lamp stable instance identity")
	_expect(not inv.add_item("lamp", 1, stolen), "duplicate lamp across origins refused")
	_expect(not inv.add_item("bread", 1, {"instance_id": ItemCatalog.LAMP_INSTANCE_ID}), "reserved identity cannot be used by another item")
	var state: PlayerState = PlayerState.new()
	state.health = 20
	_expect(not inv.remove_item(lamp["stack_id"], 1) and not inv.use_food(lamp["stack_id"], state), "ordinary remove and use cannot consume lamp")
	_expect(not ItemCatalog.get_item("lamp")["sellable"] and not ItemCatalog.get_item("lamp")["usable"], "quest sale/use flags protected")
	_expect(inv.count_item("lamp") == 1 and state.health == 20, "failed lamp operations preserve item and health")
	_expect(inv.add_item("bread", 3, stolen), "food fixture retains stolen provenance")
	var food_id: String = inv.get_stacks().back()["stack_id"]
	_expect(inv.use_food(food_id, state) and state.health == 45 and inv.get_stack(food_id)["quantity"] == 2, "food heals once and consumes exactly one")
	_expect(inv.get_stack(food_id)["stolen"] and inv.get_stack(food_id)["owner_id"] == "merchant_a", "remaining food keeps origin")
	state.health = 90
	_expect(inv.use_food(food_id, state) and state.health == 100, "healing clamps to maximum")
	_expect(not inv.use_food(food_id, state) and inv.get_stack(food_id)["quantity"] == 1, "full health never wastes food")
	state.health = 0
	_expect(not inv.use_food(food_id, state), "food cannot revive defeated player")
	_expect(not inv.use_food(food_id, null), "missing player rejected")
	_expect(inv.remove_item(lamp["stack_id"], 1, true), "only explicit quest operation can remove lamp")
	var cap: ItemInventory = ItemInventory.new()
	_expect(cap.add_item("copper", ItemInventory.MAX_QUANTITY), "max valid quantity accepted")
	_expect(not cap.can_add_item("copper", 1, stolen) and not cap.add_item("copper", 1), "overflow across different origins refused")
	_expect(cap.count_item("copper") == ItemInventory.MAX_QUANTITY, "overflow preserves exact count")
	await _check_ui(inv, state, food_id)
	if failures > 0:
		push_error("FAIL: T06 inventory (%d assertions)" % failures)
		quit(1)
	else:
		print("PASS: T06 catalog, quantities, copied reads, provenance, unique protected lamp, food and UI")
		print("NOT RUN: game I/pause integration and rendered readability; owned by integration review")
		quit(0)


func _check_ui(inv: ItemInventory, state: PlayerState, food_id: String) -> void:
	var ui: InventoryUI = InventoryUI.new()
	ui.setup(state, inv)
	root.add_child(ui)
	await process_frame
	_expect(ui.item_list.item_count == inv.get_stacks().size(), "UI projects inventory stacks")
	var food_index: int = -1
	var stacks: Array[Dictionary] = inv.get_stacks()
	for index: int in range(stacks.size()):
		if stacks[index]["stack_id"] == food_id:
			food_index = index
	state.health = 50
	ui.item_list.select(food_index)
	ui.item_list.item_selected.emit(food_index)
	_expect(not ui.use_button.disabled, "food action enabled for hurt player")
	ui.use_button.pressed.emit()
	_expect(state.health == 75 and inv.get_stack(food_id).is_empty(), "UI action consumes selected food through model")
	ui.setup(PlayerState.new(), ItemInventory.new())
	_expect(ui.item_list.item_count == 0 and ui.use_button.disabled, "UI can rebind fresh game")
	var rebound_count: int = ui.item_list.item_count
	inv.add_item("bread", 1)
	_expect(ui.item_list.item_count == rebound_count, "old inventory disconnected after rebind")
	ui.queue_free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
