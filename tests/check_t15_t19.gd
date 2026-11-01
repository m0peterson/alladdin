extends SceneTree

# Existing check_t11_t14.gd covers continuous stealth/alarm routes. This
# scenario covers actual UI save/load, full-world rollback and daily refill.
const GAME: PackedScene = preload("res://scenes/game.tscn")
var game: Variant
var failures: int = 0
var save_path: String


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	save_path = "res://.godot/t19-save-%d.json" % Time.get_ticks_usec()
	game = GAME.instantiate()
	# Before _ready: even Continue must never read a normal user save.
	game.saves = WorldSave.new(save_path)
	root.add_child(game)
	current_scene = game
	await _frames(3)
	await _click(game.new_game_button)
	await _frames(3)
	game.player.position = Vector2(112, 376)
	await _frames(3)
	await _tap(KEY_E)
	await _click(game.fence_ui.get_node("QuestAction") as Button)
	_expect(game.quest.get_stage() == LampQuest.Stage.ACCEPTED, "order accepted through real UI")
	await _tap(KEY_ESCAPE)
	game.player.position = Vector2(76, 224)
	await _frames(3)
	await _tap(KEY_E)
	var stock: Dictionary = game.trades.get_merchant("merchantwest")
	var bought_id: String = stock["stacks"][0]["item_id"]
	var before_money: int = game.player_state.money
	await _click(_first_trade_button())
	_expect(game.player_state.money < before_money and game.inventory.count_item(bought_id) > 0, "real purchase changes money and inventory before save")
	await _tap(KEY_ESCAPE)
	await _steal(Vector2(104, 232), "World/MarketGoods/Interaction")
	await _steal(Vector2(504, 176), "World/WarehouseLamp/Interaction")
	_expect(game.quest.get_stage() == LampQuest.Stage.READY and _lamp_count() == 1, "stolen lamp advances order and remains unique")
	var stolen: bool = false
	for stack: Dictionary in game.inventory.get_stacks():
		if stack["stolen"] and stack["source_id"] == "market_goods":
			stolen = true
	_expect(stolen, "ordinary stolen loot retains provenance")
	# Real witnessed theft is covered above and by T13. Explicit report here
	# guarantees an active alarm at the exact save instant.
	game.guards[2].report_crime(game.player.position)
	_expect(game.guards[2].state == GuardPatrol.State.CHASE, "save begins with active alarm")
	_expect(game.clock.restore_snapshot({"day_index": 0, "seconds_in_day": 359.8}), "clock positioned immediately before day boundary")
	await _tap(KEY_F5)
	_expect(game.save_panel.visible and paused, "F5 writes then opens a paused confirmation")
	var read: Dictionary = game.saves.read_file()
	if not _expect(read.get("ok", false), "F5 produced a valid isolated world file"):
		_finish()
		return
	var saved: Dictionary = read["data"]
	_expect(_equal(saved, game.saves.capture_world(game)), "saved snapshot matches frozen live player and world")
	var paused_clock: Dictionary = game.clock.save_snapshot()
	var saved_bytes: String = FileAccess.get_file_as_string(save_path)
	await _frames(30)
	await _tap(KEY_F5)
	await _tap(KEY_F9)
	_expect(game.clock.save_snapshot() == paused_clock, "confirmation pause stops game clock")
	_expect(FileAccess.get_file_as_string(save_path) == saved_bytes, "modal F5/F9 cannot overwrite the save")
	await _click(game.save_close)
	await _frames(30)
	_expect(game.clock.day_index == 1, "live clock crosses saved day boundary")
	for merchant_id: String in game.trades.get_merchant_ids():
		_expect(game.trades.get_merchant(merchant_id)["last_refill_day"] == 1, "merchant restocks once: " + merchant_id)
	var refilled: Dictionary = game.trades.save_snapshot()
	game.clock.advance(0.0)
	_expect(game.trades.save_snapshot() == refilled, "same-day update does not repeat restock")
	_expect(game.quest.hand_over(), "mutation completes ready order before rollback")
	game.player_state.health = 31
	game.player_state.money += 7
	game.player.position = Vector2(136, 368)
	game.guards[2].state = GuardPatrol.State.PATROL
	await _tap(KEY_F9)
	_expect(game.save_panel.visible and paused, "F9 loads through paused confirmation")
	_expect(_equal(saved, game.saves.capture_world(game)), "F9 restores player, origins, empty containers, quest, merchants, alarm and clock")
	_expect(game.quest.get_stage() == LampQuest.Stage.READY and _lamp_count() == 1, "load rolls back reward and does not duplicate lamp")
	await _tap(KEY_F9)
	_expect(_equal(saved, game.saves.capture_world(game)), "repeated modal load leaves restored world unchanged")
	await _click(game.save_close)
	await _tap(KEY_ESCAPE)
	await _click(game.get_node("Interface/PauseMenu/MainMenu") as Button)
	_expect(game.world == null and game.main_menu.visible, "pause-menu button returns to main menu")
	var continue_button: Button = game.get_node("Interface/MainMenu/Continue") as Button
	_expect(not continue_button.disabled, "isolated valid save enables Continue")
	await _click(continue_button)
	_expect(game.world != null and paused and game.save_panel.visible, "Continue recreates the saved game and confirms load")
	_expect(_equal(saved, game.saves.capture_world(game)), "Continue restores the identical full snapshot")
	await _click(game.save_close)
	await _frames(30)
	_expect(game.clock.day_index == 1 and game.trades.save_snapshot() == refilled, "reloading before boundary reproduces one finite restock")
	game.player.position = Vector2(112, 376)
	await _frames(3)
	await _tap(KEY_E)
	var reward_before: int = game.player_state.money
	await _click(game.fence_ui.get_node("QuestAction") as Button)
	_expect(game.quest.get_stage() == LampQuest.Stage.COMPLETED and game.player_state.money == reward_before + LampQuest.REWARD, "real hand-over grants exactly one reward after load")
	await _tap(KEY_ESCAPE)
	await _tap(KEY_F5)
	var final_read: Dictionary = game.saves.read_file()
	if not _expect(final_read.get("ok", false), "final world save is valid"):
		_finish()
		return
	var final_saved: Dictionary = final_read["data"]
	await _click(game.save_close)
	game.player_state.money += 7
	await _tap(KEY_F9)
	_expect(_equal(final_saved, game.saves.capture_world(game)), "load after finale restores settled reward and delivered lamp")
	await _click(game.save_close)
	await _tap(KEY_E)
	_expect(game.quest.get_stage() == LampQuest.Stage.COMPLETED and game.player_state.money == reward_before + LampQuest.REWARD and _lamp_count() == 1, "reopened final dialogue after load cannot repeat reward")
	await _tap(KEY_ESCAPE)
	await _tap(KEY_F9)
	_expect(_equal(final_saved, game.saves.capture_world(game)), "second real load cannot duplicate money, loot or reward")
	_finish()


func _steal(position: Vector2, node_path: String) -> void:
	game.player.position = position
	await _frames(3)
	var target: TheftTarget = game.world.get_node(node_path) as TheftTarget
	_expect(game.interactions.current_target == target, "displayed theft target reached: " + target.target_id)
	_key(KEY_F, true)
	await _frames(70)
	_key(KEY_F, false)
	await _frames(3)
	_expect(target.get_loot().is_empty(), "real hold emptied container: " + target.target_id)


func _first_trade_button() -> Button:
	for row: Node in game.trade_ui._rows.get_children():
		var action: Button = row.get_child(row.get_child_count() - 1) as Button
		if action != null and not action.disabled:
			return action
	return null


func _lamp_count() -> int:
	var source: TheftTarget = game.world.get_node("World/WarehouseLamp/Interaction") as TheftTarget
	return source.stock.count_item("lamp") + game.inventory.count_item("lamp") + (0 if game.quest.get_delivered_lamp().is_empty() else 1)


func _equal(left: Variant, right: Variant) -> bool:
	# JSON may change int/float representation. Preserve all keys/order and
	# tolerate only small numeric serialization differences.
	if (left is int or left is float) and (right is int or right is float):
		return absf(float(left) - float(right)) <= 0.00001
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not _equal(left[key], right[key]):
				print("INFO: snapshot differs at key ", key)
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index: int in left.size():
			if not _equal(left[index], right[index]):
				return false
		return true
	return left == right


func _frames(count: int) -> void:
	for tick: int in range(count):
		await physics_frame
		await process_frame


func _key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(code: Key) -> void:
	_key(code, true)
	await _frames(1)
	_key(code, false)
	await _frames(2)


func _click(button: Button) -> void:
	if not _expect(button != null, "expected real GUI button exists"):
		return
	await _frames(2)
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event, true)
		await _frames(2)


func _expect(condition: bool, message: String) -> bool:
	if condition:
		print("PASS: " + message)
	else:
		failures += 1
		push_error("FAIL: " + message)
	return condition


func _finish() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(save_path + suffix):
			DirAccess.remove_absolute(save_path + suffix)
	if failures:
		push_error("FAIL: T15–T19 integration (%d assertions)" % failures)
		quit(1)
	else:
		print("PASS: T15–T19 integration — real F5/F9/Continue, full world, day boundary, finite restock and final reward")
		quit(0)
