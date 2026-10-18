extends SceneTree

const Game = preload("res://scripts/game.gd")
const Player = preload("res://scripts/player.gd")
const CAPTURE_DIR: String = "res://.godot/t05-t10-review"
const KEYS: Array[Key] = [KEY_I, KEY_E, KEY_SPACE, KEY_Q, KEY_D, KEY_ENTER, KEY_ESCAPE]

var game: Game
var failures: int = 0
var capture: bool = false


func _initialize() -> void:
	capture = "--capture-review" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _run() -> void:
	if capture and DisplayServer.get_name() == "headless":
		push_error("BLOCKED: review capture needs a real renderer")
		quit(1)
		return
	if capture and DirAccess.make_dir_recursive_absolute(CAPTURE_DIR) != OK:
		quit(1)
		return
	change_scene_to_file("res://scenes/game.tscn")
	await scene_changed
	game = current_scene as Game
	await _frames(2)
	_key(KEY_SPACE, true)
	_key(KEY_Q, true)
	await _tap(KEY_ENTER)
	await _frames(10)
	_expect(game.player.attack_phase == Player.AttackPhase.IDLE and game.player.dodge_remaining == 0.0, "menu combat input does not start in a new game")
	_release()
	await _frames(3)
	_expect(game.player_state.money == Game.STARTING_MONEY and game.inventory.count_item("bread") == 2, "new game has usable honest supplies")
	var guards: Array[GuardPatrol] = []
	for child: Node in game.world.get_node("World").get_children():
		if child is GuardPatrol:
			guards.append(child as GuardPatrol)
	_expect(guards.size() == 3, "actual game installs three guards")
	await _tap(KEY_I)
	_expect(paused and game.inventory_ui.visible, "I opens a paused inventory")
	await _save("inventory")
	game.inventory_ui.item_list.grab_focus()
	var stopped: Vector2 = game.player.position
	var guard_position: Vector2 = guards[0].position
	_key(KEY_D, true)
	_key(KEY_SPACE, true)
	_key(KEY_Q, true)
	_key(KEY_E, true)
	await _frames(8)
	_expect(game.player.position == stopped and guards[0].position == guard_position, "inventory freezes player and patrols")
	await _tap(KEY_ESCAPE)
	await _frames(8)
	_expect(not paused and not game.inventory_ui.visible, "Esc closes inventory and resumes")
	_expect(game.player.position == stopped and game.player.attack_phase == Player.AttackPhase.IDLE and game.player.dodge_remaining == 0.0, "held movement and combat suppressed after inventory")
	_release()
	await _frames(3)
	game.player.position = Vector2(88, 232)
	await _frames(3)
	await _tap(KEY_E)
	_expect(paused and game.trade_ui.visible and not game.dialogue.visible, "merchant E opens only trading through shared interaction")
	await _save("trade-buy")
	var before_money: int = game.player_state.money
	var transaction_button: Button
	for row: Node in game.trade_ui._rows.get_children():
		for child: Node in row.get_children():
			if child is Button and not (child as Button).disabled:
				transaction_button = child as Button
				break
		if transaction_button != null:
			break
	if transaction_button != null:
		await _click(transaction_button)
	_expect(game.player_state.money < before_money, "real trade button purchases an available item")
	await _save("trade-result")
	_key(KEY_SPACE, true)
	_key(KEY_Q, true)
	_key(KEY_E, true)
	await _tap(KEY_ESCAPE)
	await _frames(8)
	_expect(not paused and not game.trade_ui.visible and not game.dialogue.visible, "Esc closes trade without leaving a modal window")
	_expect(game.player.attack_phase == Player.AttackPhase.IDLE and game.player.dodge_remaining == 0.0, "trade suppresses held attacks and dodge")
	_release()
	await _frames(3)
	await _tap(KEY_E)
	_expect(game.trade_ui.visible and paused, "fresh E reopens trade after release")
	await _tap(KEY_ESCAPE)
	if capture:
		for guard: GuardPatrol in guards:
			game.player.position = guard.position + Vector2(32, 32)
			await _frames(3)
			await _save(String(guard.guard_id))
	game.player.position = Vector2(376, 136)
	await _frames(3)
	await _tap(KEY_SPACE)
	await _frames(4)
	_expect(game.player.attack_phase != Player.AttackPhase.IDLE, "fresh attack works after GUI release")
	await _save("player-attack")
	await _frames(30)
	_key(KEY_D, true)
	await _tap(KEY_Q)
	await _save("player-dodge")
	_release()
	await _frames(45)
	game.player.position = Vector2(532, 344)
	await _frames(3)
	await _save("bandit-windup")
	await _frames(34)
	await _save("bandit-hit")
	await _frames(65)
	game.inventory.add_item("lamp", 1, {"stolen": true, "owner_id": "warehouse", "source_id": "warehouse_lamp"})
	var retained_items: Array[Dictionary] = game.inventory.get_stacks()
	game.player_state.health = 20
	game.player_state.money = 37
	game.player.reset_combat()
	_expect(game.player.receive_damage(20), "lethal damage reaches actual game recovery")
	await _frames(3)
	_expect(game.player.position.is_equal_approx(Vector2(136, 368)) and game.player_state.health == 100 and game.player_state.money == 34, "actual game recovery restores player and deducts ten percent")
	_expect(game.inventory.get_stacks() == retained_items and game.inventory.count_item("lamp") == 1, "actual game recovery preserves quest lamp and provenance")
	await _save("recovered")
	await _tap(KEY_ESCAPE)
	game._return_to_menu()
	await _frames(2)
	await _tap(KEY_ENTER)
	await _frames(3)
	_expect(game.player_state.money == Game.STARTING_MONEY and game.inventory.count_item("bread") == 2, "new game resets economic state")
	_expect(not game.inventory_ui.visible and not game.trade_ui.visible and not paused, "new game starts without discarded modal windows")
	_release()
	if failures:
		push_error("FAIL: T05–T10 integration (%d assertions)" % failures)
		quit(1)
	else:
		print("PASS: T05–T10 integration — real menus, trade button, shared interaction, input isolation, actors and reset")
		quit(0)


func _frames(count: int) -> void:
	for frame: int in range(count):
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


func _release() -> void:
	for code: Key in KEYS:
		_key(code, false)


func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		# GUI rects are viewport coordinates; native windows also apply stretch.
		root.push_input(event, true)
		await _frames(2)


func _save(label: String) -> void:
	if capture:
		await RenderingServer.frame_post_draw
		var result: Error = root.get_texture().get_image().save_png(CAPTURE_DIR.path_join(label + ".png"))
		_expect(result == OK, "capture " + label)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
