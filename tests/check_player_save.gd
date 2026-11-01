extends SceneTree

const Game = preload("res://scripts/game.gd")
var failures: int = 0
var directory: String
var saves: PlayerSave
var game: Game


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Unique OS temporary directory; never touch the real user save.
	directory = OS.get_temp_dir().path_join("alladdin-t15-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	_expect(DirAccess.make_dir_recursive_absolute(directory) == OK, "create isolated directory")
	saves = PlayerSave.new(directory.path_join("player.json"))
	_expect(not saves.read_file()["ok"], "missing file reported")
	var state: PlayerState = PlayerState.new()
	state.health = 37
	state.money = 1234567890
	var inventory: ItemInventory = ItemInventory.new()
	inventory.add_item("bread", 3, {"owner_id": "player", "source_id": "starter"})
	inventory.add_item("bread", 2, {"stolen": true, "owner_id": "merchantwest", "source_id": "market_goods"})
	inventory.add_item("lamp", 1, {"stolen": true, "owner_id": "warehouse", "source_id": "warehouse_lamp"})
	var snapshot: Dictionary = saves.capture(Vector2(136.5, 368.25), state, inventory)
	var expected: Variant = JSON.parse_string(JSON.stringify(snapshot))
	_expect(saves.write(snapshot).is_empty(), "initial safe write")
	var result: Dictionary = saves.read_file()
	_expect(result["ok"] and result["data"] == expected, "round-trip every player field and provenance")
	var restored: ItemInventory = ItemInventory.new()
	_expect(restored.restore_snapshot(result["data"]["player"]["inventory"]), "restore validated stacks")
	_expect(restored.save_snapshot() == inventory.save_snapshot(), "stable stack IDs and next ID preserved")
	_expect(restored.restore_snapshot(result["data"]["player"]["inventory"]) and restored.count_item("lamp") == 1, "repeated load replaces inventory")
	restored.add_item("silk", 1)
	_expect(restored.get_stacks()[-1]["stack_id"] == "stack_4", "new ID does not collide after loading")
	_check_invalid(snapshot)
	_check_origin_id_limit()
	_check_stack_id_limit()
	_check_stack_count_limit()
	var previous: String = FileAccess.get_file_as_string(saves.path)
	# A directory at the temp path deterministically rejects opening WRITE.
	DirAccess.make_dir_absolute(saves.path + ".tmp")
	var changed: Dictionary = snapshot.duplicate(true)
	changed["player"]["money"] = 90
	_expect(not saves.write(changed).is_empty(), "write failure reported")
	_expect(FileAccess.get_file_as_string(saves.path) == previous, "failed write preserves previous valid bytes")
	DirAccess.remove_absolute(saves.path + ".tmp")
	_expect(saves.write(changed).is_empty(), "second safe write")
	_expect(saves.has_backup() and saves.read_file(saves.path + ".bak")["data"] == expected, "verified backup is previous snapshot")
	_write_text(saves.path, "{broken")
	_expect(not saves.read_file()["ok"], "corruption is not silently replaced with backup")
	_expect(not saves.write(changed).is_empty(), "save refuses overwrite of corrupt primary")
	_expect(saves.restore_backup()["ok"] and saves.read_file()["data"] == expected, "explicit backup restores valid primary")
	DirAccess.remove_absolute(saves.path + ".bak")
	DirAccess.make_dir_absolute(saves.path + ".bak")
	previous = FileAccess.get_file_as_string(saves.path)
	_expect(not saves.write(changed).is_empty(), "backup replacement failure reported")
	_expect(FileAccess.get_file_as_string(saves.path) == previous, "backup replacement failure preserves primary")
	DirAccess.remove_absolute(saves.path + ".bak")
	_expect(saves.write(snapshot).is_empty(), "recreate verified backup")
	var before_inventory: Dictionary = restored.save_snapshot()
	_expect(not restored.restore_snapshot({"stacks": [null], "next_stack_id": 1}), "inventory public boundary rejects invalid snapshot")
	_expect(restored.save_snapshot() == before_inventory, "inventory rejection does not partially mutate")
	await _check_game(snapshot)
	for filename: String in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	if failures:
		push_error("FAIL: T15 player save (%d assertions)" % failures)
		quit(1)
	else:
		print("PASS: T15 versioned player save, validation, safe writes, backup, F5/F9 and Continue")
		print("NOT RUN: rendered save message readability and power-loss durability")
		quit(0)


func _check_origin_id_limit() -> void:
	var inventory: ItemInventory = ItemInventory.new()
	var before: Dictionary = inventory.save_snapshot()
	for key: String in ["owner_id", "source_id", "instance_id"]:
		var origin: Dictionary = {key: "x".repeat(ItemInventory.MAX_ID_LENGTH + 1)}
		_expect(not inventory.can_add_item("bread", 1, origin) and not inventory.add_item("bread", 1, origin), "oversized origin ID refused: " + key)
		_expect(inventory.save_snapshot() == before, "origin ID refusal does not mutate inventory: " + key)
	var boundary: String = "x".repeat(ItemInventory.MAX_ID_LENGTH)
	_expect(inventory.can_add_item("bread", 1, {"owner_id": boundary, "source_id": boundary, "instance_id": boundary}) and inventory.add_item("bread", 1, {"owner_id": boundary, "source_id": boundary, "instance_id": boundary}), "origin IDs of exactly maximum length are accepted")
	_expect(ItemInventory.validate_snapshot(inventory.save_snapshot()).is_empty(), "accepted boundary origin remains serializable")


func _check_stack_id_limit() -> void:
	var inventory: ItemInventory = ItemInventory.new()
	_expect(inventory.restore_snapshot({"stacks": [], "next_stack_id": ItemInventory.MAX_QUANTITY}), "restore exhausted stack counter")
	var before: Dictionary = inventory.save_snapshot()
	_expect(not inventory.can_add_item("bread", 1) and not inventory.add_item("bread", 1), "exhausted counter refuses a new stack")
	_expect(inventory.save_snapshot() == before, "ID exhaustion refusal does not mutate inventory")
	_expect(inventory.restore_snapshot({"stacks": [], "next_stack_id": ItemInventory.MAX_QUANTITY - 1}), "restore last available stack ID")
	_expect(inventory.add_item("bread", 1), "last available stack ID is usable")
	_expect(ItemInventory.validate_snapshot(inventory.save_snapshot()).is_empty(), "last stack leaves serializable next counter")
	before = inventory.save_snapshot()
	_expect(not inventory.can_add_item("bread", 1, {"source_id": "different"}) and not inventory.add_item("bread", 1, {"source_id": "different"}), "different origin requires an unavailable new ID")
	_expect(inventory.save_snapshot() == before, "new origin refusal preserves stacks and counter")
	_expect(inventory.can_add_item("bread", 1) and inventory.add_item("bread", 1), "existing origin can merge with exhausted ID space")
	_expect(inventory.count_item("bread") == 2 and ItemInventory.validate_snapshot(inventory.save_snapshot()).is_empty(), "merge retains serializable inventory")


func _check_stack_count_limit() -> void:
	var inventory: ItemInventory = ItemInventory.new()
	for index: int in range(ItemInventory.MAX_STACKS):
		if not inventory.add_item("bread", 1, {"source_id": "source_%d" % index}):
			_expect(false, "fill every available stack slot")
			return
	var before: Dictionary = inventory.save_snapshot()
	_expect(before["stacks"].size() == ItemInventory.MAX_STACKS, "maximum stack capacity is reachable")
	_expect(not inventory.can_add_item("bread", 1, {"source_id": "overflow"}) and not inventory.add_item("bread", 1, {"source_id": "overflow"}), "full inventory refuses a new origin")
	_expect(inventory.save_snapshot() == before, "stack capacity refusal does not mutate inventory")
	_expect(inventory.can_add_item("bread", 1, {"source_id": "source_0"}) and inventory.add_item("bread", 1, {"source_id": "source_0"}), "full inventory allows an existing origin to merge")
	_expect(inventory.get_stacks().size() == ItemInventory.MAX_STACKS and inventory.get_stacks()[0]["quantity"] == 2, "merge consumes no extra stack slot")
	_expect(ItemInventory.validate_snapshot(inventory.save_snapshot()).is_empty(), "full inventory remains serializable after refusal and merge")


func _check_invalid(snapshot: Dictionary) -> void:
	var cases: Array[Dictionary] = []
	for version: Variant in [2, "1", true, null]:
		var wrong: Dictionary = snapshot.duplicate(true)
		wrong["version"] = version
		cases.append(wrong)
	for field: String in ["health", "money"]:
		for value: Variant in ["37", true, -1, 1.5, 2147483648]:
			var wrong: Dictionary = snapshot.duplicate(true)
			wrong["player"][field] = value
			cases.append(wrong)
	for field: String in ["quantity", "stack_id", "item_id", "stolen", "owner_id", "instance_id"]:
		var wrong: Dictionary = snapshot.duplicate(true)
		wrong["player"]["inventory"]["stacks"][0][field] = {"quantity": 0, "stack_id": "runtime-id", "item_id": "missing", "stolen": "true", "owner_id": 17, "instance_id": ItemCatalog.LAMP_INSTANCE_ID}[field]
		cases.append(wrong)
	var duplicate: Dictionary = snapshot.duplicate(true)
	duplicate["player"]["inventory"]["stacks"][1]["stack_id"] = "stack_1"
	cases.append(duplicate)
	var lamp: Dictionary = snapshot.duplicate(true)
	lamp["player"]["inventory"]["stacks"][2]["quantity"] = 2
	cases.append(lamp)
	lamp = snapshot.duplicate(true)
	lamp["player"]["inventory"]["stacks"][2]["instance_id"] = ""
	cases.append(lamp)
	duplicate = snapshot.duplicate(true)
	var extra: Dictionary = duplicate["player"]["inventory"]["stacks"][2].duplicate(true)
	extra["stack_id"] = "stack_4"
	duplicate["player"]["inventory"]["stacks"].append(extra)
	duplicate["player"]["inventory"]["next_stack_id"] = 5
	cases.append(duplicate)
	var position: Dictionary = snapshot.duplicate(true)
	position["player"]["position"]["x"] = "136"
	cases.append(position)
	position = snapshot.duplicate(true)
	position["player"]["position"]["y"] = 900
	cases.append(position)
	for index: int in range(cases.size()):
		_expect(not saves.validate(cases[index]).is_empty(), "reject invalid snapshot %d" % index)
		_write_text(directory.path_join("invalid.json"), JSON.stringify(cases[index]))
		_expect(not saves.read_file(directory.path_join("invalid.json"))["ok"], "file boundary rejects invalid snapshot %d" % index)


func _check_game(snapshot: Dictionary) -> void:
	game = load("res://scenes/game.tscn").instantiate() as Game
	game.saves = saves
	root.add_child(game)
	await _frames(2)
	var continue_button: Button = game.get_node("Interface/MainMenu/Continue")
	_expect(not continue_button.disabled, "Continue available for existing save")
	continue_button.pressed.emit()
	_expect(game.world != null and paused and game.save_panel.visible, "Continue loads real game and explains scope")
	_expect(game.player.position == Vector2(136.5, 368.25) and game.player_state.health == 37 and game.player_state.money == 1234567890, "Continue restores player values")
	_expect(game.inventory.save_snapshot() == snapshot["player"]["inventory"], "Continue restores all inventory")
	_expect(game.save_message.text.contains("НЕ сохраняются"), "world limitation visible")
	await _click(game.save_close)
	_expect(not game.save_panel.visible and not paused, "actual close button resumes gameplay")
	await _frames(2)
	game.player_state.money = 55
	await _tap(KEY_F5)
	_expect(paused and game.save_panel.visible and saves.read_file()["data"]["player"]["money"] == 55, "real F5 saves and pauses notification")
	game._close_save_panel()
	game.player_state.money = 7
	await _tap(KEY_F9)
	_expect(game.player_state.money == 55 and paused, "real F9 loads")
	game._close_save_panel()
	await _tap(KEY_ESCAPE)
	var previous: String = FileAccess.get_file_as_string(saves.path)
	game.player_state.money = 99
	await _tap(KEY_F5)
	await _tap(KEY_F9)
	_expect(game.player_state.money == 99 and FileAccess.get_file_as_string(saves.path) == previous and game.pause_menu.visible, "pause menu blocks F5/F9")
	game._resume()
	await _tap(KEY_I)
	await _tap(KEY_F9)
	_expect(game.inventory_ui.visible and game.player_state.money == 99, "inventory modal blocks F9")
	game._close_inventory()
	_write_text(saves.path, "not json")
	var before: Dictionary = saves.capture(game.player.position, game.player_state, game.inventory)
	await _tap(KEY_F9)
	_expect(saves.capture(game.player.position, game.player_state, game.inventory) == before, "invalid F9 changes no player fields")
	_expect(game.save_panel.visible and game.backup_button.visible and game.save_message.text.contains("повреждено"), "error offers explicit valid backup")
	await _click(game.backup_button)
	_expect(game.player_state.money == 1234567890 and saves.read_file()["ok"], "explicit UI backup action restores previous save")
	game._close_save_panel()
	game._return_to_menu()
	DirAccess.remove_absolute(saves.path)
	game._refresh_continue()
	_expect(not continue_button.disabled, "missing primary still allows explicit backup recovery from menu")
	continue_button.pressed.emit()
	_expect(game.world == null and game.save_panel.visible and game.backup_button.visible, "missing primary reports error without silently starting game")
	game._close_save_panel()
	DirAccess.remove_absolute(saves.path + ".bak")
	game._refresh_continue()
	_expect(continue_button.disabled, "Continue disabled when neither primary nor backup exists")
	game.queue_free()
	await _frames(2)


func _write_text(file_path: String, content: String) -> void:
	var file: FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string(content)
	file.close()


func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event, true)
		await _frames(1)


func _tap(key: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(1)


func _frames(count: int) -> void:
	for tick: int in range(count):
		await physics_frame
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
