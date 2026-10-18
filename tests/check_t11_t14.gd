extends SceneTree

const Game = preload("res://scripts/game.gd")
const CAPTURE_DIR: String = "res://.godot/t11-t14-review"
const MOVE_ACTIONS: Array[StringName] = [&"move_left", &"move_right", &"move_up", &"move_down"]
var game: Game
var failures: int = 0
var capture: bool = false
var witnessed: Array[Dictionary] = []
var had_chase: bool = false
var watching_route: bool = false


func _initialize() -> void:
	capture = "--capture-review" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _run() -> void:
	if capture and DisplayServer.get_name() == "headless":
		push_error("BLOCKED: review capture needs a real renderer")
		quit(1)
		return
	if capture:
		DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	game = current_scene as Game
	_key(KEY_F, true)
	_key(KEY_SHIFT, true)
	await _tap(KEY_ENTER)
	await _frames(5)
	_expect(game.theft != null and game.guards.size() == 3, "new game installs theft and three configured guards")
	_expect(not game.player.is_sneaking() and game.inventory.count_item("lamp") == 0, "menu-held F and Shift do not start an action")
	_release()
	await _frames(3)
	await _check_windows_and_crime()
	if "--interfaces-only" in OS.get_cmdline_user_args():
		print("PASS: T11–T14 interfaces" if failures == 0 else "FAIL: T11–T14 interfaces")
		quit(1 if failures else 0)
		return
	await _restart()
	await _play_route(false, false)
	await _restart()
	await _play_route(true, true)
	await _restart()
	_expect(game.quest.get_stage() == LampQuest.Stage.OFFERED and _lamp_count() == 1, "new game resets order and creates exactly one lamp")
	_expect(game.trades.get_merchant("fence")["budget"] == 55, "new game resets fence budget")
	_release()
	if failures:
		push_error("FAIL: T11–T14 integration (%d assertions)" % failures)
		quit(1)
	else:
		print("PASS: T11–T14 integration — hold, witnesses, snapshot, GUI, trade, both routes, early lamp, reward and reset")
		quit(0)


func _check_windows_and_crime() -> void:
	game.player.position = Vector2(112, 376)
	await _frames(3)
	await _tap(KEY_E)
	_expect(paused and game.fence_ui.visible and not game.trade_ui.visible, "fence E opens only the order window")
	await _save("order-offer")
	var stopped: Vector2 = game.player.position
	_key(KEY_D, true)
	_key(KEY_F, true)
	_key(KEY_SHIFT, true)
	await _click(game.fence_ui.get_node("QuestAction") as Button)
	_expect(game.quest.get_stage() == LampQuest.Stage.ACCEPTED, "real button explicitly accepts the order")
	await _tap(KEY_ESCAPE)
	await _frames(8)
	_expect(not paused and game.player.position == stopped and not game.player.is_sneaking(), "order window suppresses held movement, F and Shift on return")
	_release()
	await _frames(3)
	game.player.position = Vector2(104, 232)
	game.crime.crime_witnessed.connect(func(event: Dictionary, _ids: Array[String]) -> void: witnessed.append(event))
	await _frames(3)
	var target: TheftTarget = game.world.get_node("World/MarketGoods/Interaction") as TheftTarget
	_expect(game.interactions.current_target == target, "hold uses the displayed market container")
	_key(KEY_F, true)
	await _frames(25)
	await _save("theft-progress")
	_key(KEY_F, false)
	await _frames(3)
	_expect(not target.get_loot().is_empty() and witnessed.is_empty(), "release cancels partial hold without loot or crime")
	_key(KEY_F, true)
	await _frames(70)
	_key(KEY_F, false)
	await _frames(2)
	_expect(target.get_loot().is_empty() and game.inventory.count_item("silk") == 2, "completed hold transfers one market lot")
	_expect(witnessed.size() == 1 and witnessed[0]["source_id"] == "market_goods", "actual owner witnesses completed theft exactly once")
	_expect(game.guards[2].state == GuardPatrol.State.CHASE, "actual crime event raises guard alarm")
	await _save("witness-alarm")
	var snapshot: Vector2 = game.guards[2].last_known_position
	game.player.position = Vector2(352, 264)
	await _frames(5)
	_expect(game.guards[2].last_known_position == snapshot, "warehouse wall prevents hidden crime-position tracking")
	game.player.position = Vector2(76, 224)
	await _frames(3)
	await _tap(KEY_E)
	_expect(paused and game.trade_ui.visible, "lawful merchant still opens trading")
	game.trade_ui._switch_mode(false)
	var stolen: Dictionary = _stolen_silk()
	var money: int = game.player_state.money
	await _click(_sale_button(stolen["stack_id"]))
	_expect(game.player_state.money == money and "краденое" in game.trade_ui._message.text, "actual lawful trade button refuses stolen goods with explanation")
	await _save("lawful-refusal")
	await _tap(KEY_ESCAPE)
	game.player.position = Vector2(112, 376)
	await _frames(3)
	await _tap(KEY_E)
	await _click(game.fence_ui.get_node("Trade") as Button)
	_expect(paused and game.trade_ui.visible and not game.fence_ui.visible, "fence order window opens a single paused trade window")
	game.trade_ui._switch_mode(false)
	await _save("fence-offer")
	var price: int = game.trades.get_offer_price("fence", "silk", false)
	await _click(_sale_button(stolen["stack_id"]))
	_expect(game.player_state.money == money + price and game.inventory.count_item("silk") == 1, "actual fence button pays discounted price for exactly one stolen item")
	await _save("fence-sale")
	await _tap(KEY_ESCAPE)
	_expect(not paused and not game.trade_ui.visible and not game.fence_ui.visible, "Esc closes fence trading and resumes world")


func _play_route(stealth: bool, early: bool) -> void:
	had_chase = false
	watching_route = true
	if not early:
		await _walk(Vector2(112, 368), false)
		await _tap(KEY_E)
		await _click(game.fence_ui.get_node("QuestAction") as Button)
		await _tap(KEY_ESCAPE)
	if stealth:
		# The southern wall is cover. Wait for the guard to pass left, then
		# sneak behind him. Actors, timing and visibility remain unmodified.
		for point: Vector2 in [Vector2(240, 368), Vector2(240, 312), Vector2(400, 312), Vector2(400, 224)]:
			await _walk(point, false)
		await _walk(Vector2(504, 224), true)
		await _wait_for_patrol()
		await _save("stealth-cover")
		await _walk(Vector2(504, 176), true)
	else:
		for point: Vector2 in [Vector2(240, 368), Vector2(240, 312), Vector2(504, 312), Vector2(504, 190), Vector2(544, 190), Vector2(544, 176)]:
			await _walk(point, false)
	await _frames(2)
	var source: TheftTarget = game.world.get_node("World/WarehouseLamp/Interaction") as TheftTarget
	_expect(game.interactions.current_target == source, "warehouse route reaches the displayed lamp container")
	_key(KEY_F, true)
	await _frames(70)
	_key(KEY_F, false)
	await _frames(2)
	_expect(game.inventory.count_item("lamp") == 1 and source.get_loot().is_empty() and _lamp_count() == 1, "real hold moves the unique warehouse lamp to player")
	await _save("early-lamp" if early else "lamp-acquired")
	if stealth:
		for point: Vector2 in [Vector2(504, 224), Vector2(400, 224)]:
			await _walk(point, true)
		for point: Vector2 in [Vector2(400, 312), Vector2(240, 312), Vector2(240, 368), Vector2(112, 368)]:
			await _walk(point, false)
	else:
		for point: Vector2 in [Vector2(568, 176), Vector2(568, 136), Vector2(504, 136), Vector2(504, 188), Vector2(504, 312), Vector2(240, 312), Vector2(240, 368), Vector2(112, 368)]:
			await _walk(point, false)
	watching_route = false
	print("INFO: route stealth=%s early=%s had_chase=%s" % [stealth, early, had_chase])
	_expect(not had_chase if stealth else had_chase, "stealth route avoids pursuit" if stealth else "direct route remains completable with alarm")
	# Wait at the fence until the reported-position search has expired.
	await _frames(400)
	for guard: GuardPatrol in game.guards:
		_expect(guard.suspicion == 0.0 and guard.state not in [GuardPatrol.State.CHASE, GuardPatrol.State.SEARCH], "alarm expires after actual escape: " + String(guard.guard_id))
	_expect(_lamp_count() == 1, "lamp remains unique after escape")
	if early:
		_expect(game.quest.get_stage() == LampQuest.Stage.OFFERED, "finding the lamp does not silently accept the order")
	await _tap(KEY_E)
	if early:
		await _click(game.fence_ui.get_node("QuestAction") as Button)
	_expect(game.quest.get_stage() == LampQuest.Stage.READY, "order recognizes lamp obtained before or after acceptance")
	await _save("order-ready")
	var money: int = game.player_state.money
	await _click(game.fence_ui.get_node("QuestAction") as Button)
	_expect(game.quest.get_stage() == LampQuest.Stage.COMPLETED and game.player_state.money == money + LampQuest.REWARD, "real hand-over button grants one reward and terminal stage")
	_expect(game.inventory.count_item("lamp") == 0 and _lamp_count() == 1, "hand-over leaves lamp in only the fence quest record")
	await _save("quest-finale")
	await _tap(KEY_ESCAPE)
	await _tap(KEY_E)
	_expect(game.quest.get_stage() == LampQuest.Stage.COMPLETED and game.player_state.money == money + LampQuest.REWARD, "repeat dialogue cannot repeat payment")
	await _tap(KEY_ESCAPE)
	game.player_state.health = 20
	game.player.reset_combat()
	game.player.receive_damage(20)
	await _frames(3)
	_expect(game.quest.get_stage() == LampQuest.Stage.COMPLETED and _lamp_count() == 1, "defeat retains quest completion and delivered lamp")


func _wait_for_patrol() -> void:
	var guard: GuardPatrol = game.guards[2]
	for tick: int in range(800):
		if guard.position.y > 182.0 and guard.position.x >= 500.0 and guard.position.x <= 515.0 and guard.facing.x < -0.9:
			return
		await _frames(1)
	_expect(false, "warehouse patrol reaches a safe entry phase within a bounded wait")


func _walk(target: Vector2, sneak: bool) -> void:
	var speed: float = 32.0 if sneak else 72.0
	var budget: int = ceili(game.player.position.distance_to(target) / speed * 60.0) + 180
	if sneak:
		Input.action_press("sneak")
	for tick: int in range(budget):
		var offset: Vector2 = target - game.player.position
		if absf(offset.x) <= 1.3 and absf(offset.y) <= 1.3:
			_move_release()
			Input.action_release("sneak")
			await _frames(1)
			return
		_move_release()
		if absf(offset.x) > absf(offset.y):
			Input.action_press("move_right" if offset.x > 0 else "move_left")
		else:
			Input.action_press("move_down" if offset.y > 0 else "move_up")
		await _frames(1)
	_move_release()
	Input.action_release("sneak")
	_expect(false, "route blocked before %s at %s" % [target, game.player.position])


func _stolen_silk() -> Dictionary:
	for stack: Dictionary in game.inventory.get_stacks():
		if stack["item_id"] == "silk" and stack["stolen"]:
			return stack
	return {}


func _sale_button(stack_id: String) -> Button:
	var stacks: Array[Dictionary] = game.inventory.get_stacks()
	for index: int in range(stacks.size()):
		if stacks[index]["stack_id"] == stack_id:
			return game.trade_ui._rows.get_child(index).get_child(1) as Button
	return null


func _lamp_count() -> int:
	var source: TheftTarget = game.world.get_node("World/WarehouseLamp/Interaction") as TheftTarget
	return source.stock.count_item("lamp") + game.inventory.count_item("lamp") + (0 if game.quest.get_delivered_lamp().is_empty() else 1)


func _restart() -> void:
	_release()
	if paused:
		await _tap(KEY_ESCAPE)
	game._return_to_menu()
	await _frames(2)
	await _tap(KEY_ENTER)
	await _frames(3)


func _frames(count: int) -> void:
	for tick: int in range(count):
		await physics_frame
		await process_frame
		if watching_route:
			for guard: GuardPatrol in game.guards:
				if guard.state == GuardPatrol.State.CHASE:
					had_chase = true


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(code: Key) -> void:
	_key(code, true)
	await _frames(1)
	_key(code, false)
	await _frames(2)


func _move_release() -> void:
	for action: StringName in MOVE_ACTIONS:
		Input.action_release(action)


func _release() -> void:
	_move_release()
	Input.action_release("sneak")
	for code: Key in [KEY_F, KEY_SHIFT, KEY_E, KEY_D, KEY_ENTER, KEY_ESCAPE]:
		_key(code, false)


func _click(button: Button) -> void:
	if button == null:
		_expect(false, "expected real GUI button exists")
		return
	# Inventory rows can lie below the viewport. Scroll the real container
	# before clicking, as a player must; hidden rows cannot receive clicks.
	await _frames(2)
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(button)
			await _frames(2)
			break
		ancestor = ancestor.get_parent()
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event, true)
		await _frames(2)


func _save(label: String) -> void:
	if capture:
		await RenderingServer.frame_post_draw
		_expect(root.get_texture().get_image().save_png(CAPTURE_DIR.path_join(label + ".png")) == OK, "capture " + label)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
