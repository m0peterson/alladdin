extends SceneTree

const Game = preload("res://scripts/game.gd")
const CAPTURE_DIR: String = "res://.godot/t05-review"
const KEYS: Array[Key] = [KEY_E, KEY_D, KEY_ENTER, KEY_ESCAPE]

var game: Game
var fence: InteractionTarget
var chest: InteractionTarget
var failures: int = 0
var completed: int = 0
var last_message: String = ""
var capture: bool = false


func _initialize() -> void:
	capture = "--capture-interaction" in OS.get_cmdline_user_args()
	call_deferred("_run")


func _run() -> void:
	if capture and DisplayServer.get_name() == "headless":
		push_error("BLOCKED: interaction capture needs a real renderer")
		quit(1)
		return
	if capture and DirAccess.make_dir_recursive_absolute(CAPTURE_DIR) != OK:
		push_error("FAIL: cannot create interaction capture directory")
		quit(1)
		return
	if change_scene_to_file("res://scenes/game.tscn") != OK:
		quit(1)
		return
	await scene_changed
	game = current_scene as Game
	await _frames(2)
	game.interactions.interaction_completed.connect(_on_completed)
	_expect(game.main_menu.visible and game.world == null, "starts in main menu")
	await _tap(KEY_E)
	_expect(completed == 0 and not game.dialogue.visible, "E in main menu cannot interact")
	_expect(not game.interaction_hint.visible, "main menu has no target hint")
	# Start while E is held: a menu event must not become a world action.
	_key(KEY_E, true)
	await _tap(KEY_ENTER)
	await _frames(3)
	_expect(game.world != null, "New Game opens the real bazaar")
	if game.world == null:
		quit(1)
		return
	fence = game.world.get_node("World/Fence/Interaction") as InteractionTarget
	chest = game.world.get_node("World/Chest/Interaction") as InteractionTarget
	_expect(fence != null and chest != null, "NPC and chest share InteractionTarget")
	if fence == null or chest == null:
		quit(1)
		return
	_expect(game.interactions.player == game.player, "controller uses current player")
	_expect(game.interactions.process_mode == Node.PROCESS_MODE_PAUSABLE, "world interaction controller pauses")
	_expect(completed == 0 and not chest.opened and not game.dialogue.visible, "held E does not act after New Game")
	_key(KEY_E, true, true)
	await _frames(2)
	_expect(completed == 0, "held E echo cannot bypass startup suppression")
	_release()
	await _frames(2)
	for npc_name: String in ["MerchantWest", "MerchantEast", "Fence"]:
		var target: InteractionTarget = game.world.get_node("World/" + npc_name + "/Interaction") as InteractionTarget
		_expect(target != null and target.kind == 0, npc_name + " uses common NPC target")
	_expect(chest.kind == 1, "container uses common target with container kind")
	await _check_selection()
	await _check_unavailable()
	await _check_distance_boundary()
	await _check_npc_and_modal_input()
	await _check_container()
	await _check_discarded_target()
	await _check_reset()
	_release()
	if failures:
		push_error("FAIL: T05 interaction (%d assertions)" % failures)
		quit(1)
	else:
		print("PASS: T05 interaction — stable nearest target, shared NPC/container action, distance, occlusion and modal input")
		print("INFO: actual interaction captures in .godot/t05-review" if capture else "NOT RUN: rendered hint/dialogue readability; check separately")
		quit(0)


func _check_selection() -> void:
	await _place(Vector2(112, 384))
	_expect(fence.is_available(game.player) and chest.is_available(game.player), "two close targets both available")
	_expect(is_equal_approx(game.player.global_position.distance_to(fence.global_position), game.player.global_position.distance_to(chest.global_position)), "selection fixture has equal distances")
	var expected: InteractionTarget = fence if fence.target_id < chest.target_id else chest
	_expect(game.interactions.current_target == expected, "equal-distance tie uses stable target_id")
	_expect(game.interaction_hint.visible and game.interaction_hint.text == expected.prompt(), "hint describes exactly the selected target")
	var world_objects: Node = game.world.get_node("World")
	var fence_body: Node = fence.get_parent()
	var chest_body: Node = chest.get_parent()
	var fence_index: int = fence_body.get_index()
	var chest_index: int = chest_body.get_index()
	# Reverse target scene order to challenge group traversal order.
	world_objects.move_child(fence_body, 0)
	world_objects.move_child(chest_body, world_objects.get_child_count() - 1)
	fence.remove_from_group("interaction_targets")
	chest.remove_from_group("interaction_targets")
	fence.add_to_group("interaction_targets")
	chest.add_to_group("interaction_targets")
	var targets: Array[Node] = get_nodes_in_group("interaction_targets")
	_expect(targets.find(fence) < targets.find(chest), "first traversal really visits NPC before container")
	game.interactions.refresh_target()
	_expect(game.interactions.current_target == expected, "tie stable with NPC first in scene order")
	world_objects.move_child(chest_body, 0)
	world_objects.move_child(fence_body, world_objects.get_child_count() - 1)
	fence.remove_from_group("interaction_targets")
	chest.remove_from_group("interaction_targets")
	chest.add_to_group("interaction_targets")
	fence.add_to_group("interaction_targets")
	targets = get_nodes_in_group("interaction_targets")
	_expect(targets.find(chest) < targets.find(fence), "second traversal really visits container before NPC")
	for repeat: int in range(4):
		game.interactions.refresh_target()
		_expect(game.interactions.current_target == expected, "tie stable with container first, refresh %d" % repeat)
	world_objects.move_child(fence_body, fence_index)
	world_objects.move_child(chest_body, chest_index)
	await _save("two-targets")
	await _place(Vector2(104, 390))
	_expect(game.interactions.current_target == fence, "walking closer selects NPC")
	_expect(game.interaction_hint.text == fence.prompt(), "NPC hint follows nearest selection")
	await _save("npc-hint")
	await _place(Vector2(138, 402))
	_expect(game.interactions.current_target == chest, "walking closer selects container")
	_expect(game.interaction_hint.text == chest.prompt(), "container hint follows nearest selection")
	await _save("container-hint")


func _check_unavailable() -> void:
	var before: int = completed
	_key(KEY_D, true)
	await _frames(32)
	_key(KEY_D, false)
	await _frames(2)
	_expect(game.interactions.current_target == null and not game.interaction_hint.visible, "walking away with D removes target and hint outside range")
	await _place(Vector2(384, 376))
	_expect(game.interactions.current_target == null and not game.interaction_hint.visible, "leaving range removes target and hint")
	await _tap(KEY_E)
	_expect(completed == before and not game.dialogue.visible, "E outside range does nothing")
	# Availability must be rechecked even if a previously selected target is stale.
	game.interactions.current_target = chest
	game.interactions.try_interact()
	_expect(completed == before and not chest.opened, "stale distant target cannot act")
	await _place(Vector2(104, 390))
	# A changed target must never redirect the pending action to another nearby NPC/container.
	_expect(game.interactions.current_target == fence and chest.is_available(game.player), "stale-hint fixture has a selected NPC and valid alternative")
	fence.enabled = false
	game.interactions.try_interact()
	_expect(completed == before and not chest.opened and game.interactions.current_target == null, "E on stale hint does not silently act on the available alternative")
	game.interactions.refresh_target()
	_expect(game.interactions.current_target == chest, "disabled nearest target is skipped")
	chest.enabled = false
	game.interactions.current_target = fence
	game.interactions.try_interact()
	_expect(completed == before, "stale disabled target cannot act")
	game.interactions.refresh_target()
	_expect(game.interactions.current_target == null, "no enabled target means no selection")
	fence.enabled = true
	(fence.get_parent() as CanvasItem).hide()
	game.interactions.refresh_target()
	_expect(game.interactions.current_target == null, "hidden NPC is unavailable")
	game.interactions.current_target = fence
	game.interactions.try_interact()
	_expect(completed == before, "stale hidden target cannot act")
	(fence.get_parent() as CanvasItem).show()
	# Place a small real collider between nearby feet; distance alone must not allow E.
	await _place(Vector2(116, 384))
	var blocker: StaticBody2D = StaticBody2D.new()
	blocker.position = Vector2(106, 377)
	var collision: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(4, 10)
	collision.shape = shape
	blocker.add_child(collision)
	game.world.get_node("World").add_child(blocker)
	await _frames(2)
	_expect(game.player.global_position.distance_to(fence.global_position) < InteractionTarget.INTERACTION_DISTANCE, "occlusion case remains inside interaction range")
	_expect(not fence.is_available(game.player), "wall blocks nearby NPC interaction")
	game.interactions.current_target = fence
	game.interactions.try_interact()
	_expect(completed == before and not game.dialogue.visible, "stale occluded target cannot act")
	game.interactions.refresh_target()
	_expect(game.interactions.current_target == null and not game.interaction_hint.visible, "occluded target has no hint")
	blocker.queue_free()
	await _frames(2)
	chest.enabled = true


func _check_distance_boundary() -> void:
	await _place(Vector2(384, 376))
	var target: InteractionTarget = InteractionTarget.new()
	target.target_id = "regression_distance_boundary"
	target.display_name = "Граница"
	target.message = "Граничная цель"
	game.world.get_node("World").add_child(target)
	target.global_position = game.player.global_position + Vector2(InteractionTarget.INTERACTION_DISTANCE, 0)
	await _frames(2)
	game.interactions.refresh_target()
	_expect(target.is_available(game.player) and game.interactions.current_target == target, "target at exactly 32 px is available and selected")
	_expect(game.interaction_hint.text == target.prompt(), "boundary target has the matching hint")
	var before: int = completed
	# Move after the displayed selection without a refresh: keypress must revalidate range.
	target.global_position.x += 0.25
	_expect(not target.is_available(game.player), "target just beyond 32 px is unavailable")
	game.interactions.try_interact()
	_expect(completed == before and not game.dialogue.visible and game.interactions.current_target == null, "target moving beyond range after its hint cannot act")
	game.interactions.refresh_target()
	_expect(not game.interaction_hint.visible, "out-of-range boundary target leaves no hint")
	target.queue_free()
	await _frames(2)


func _check_npc_and_modal_input() -> void:
	await _place(Vector2(104, 390))
	var before: int = completed
	var health_before: int = game.player_state.health
	var money_before: int = game.player_state.money
	await _tap(KEY_E)
	_expect(completed == before + 1 and last_message == fence.message, "E acts on NPC named in hint")
	_expect(paused and game.dialogue.visible and not game.pause_menu.visible, "NPC opens modal dialogue and pauses world")
	_expect(game.dialogue_text.text == last_message and not last_message.is_empty(), "dialogue shows result of selected NPC")
	_expect(not game.interaction_hint.visible, "dialogue hides interaction hint")
	await _save("npc-dialogue")
	var stopped: Vector2 = game.player.position
	await _tap(KEY_E)
	_expect(game.dialogue.visible and completed == before + 1, "E neither closes dialogue nor acts behind it")
	_expect(game.player.position == stopped, "dialogue keeps world stationary")
	# Hold E across Enter closing, including echoed presses after resume.
	_key(KEY_E, true)
	await _tap(KEY_ENTER)
	_expect(not paused and not game.dialogue.visible, "Enter closes dialogue and resumes world")
	_key(KEY_E, true, true)
	await _frames(3)
	_expect(completed == before + 1 and not game.dialogue.visible, "held E and echo do not reopen dialogue after closing")
	_release()
	await _frames(2)
	await _tap(KEY_E)
	_expect(completed == before + 2 and game.dialogue.visible, "fresh E works after release")
	await _tap(KEY_ESCAPE)
	_expect(not paused and not game.dialogue.visible and not game.pause_menu.visible, "Esc closes dialogue without opening pause menu")
	await _tap(KEY_ESCAPE)
	_expect(paused and game.pause_menu.visible, "Esc opens normal pause after dialogue")
	before = completed
	await _tap(KEY_E)
	_expect(completed == before and not game.dialogue.visible and not chest.opened, "E in pause cannot interact")
	_expect(not game.interaction_hint.visible, "pause hides interaction hint")
	_key(KEY_E, true)
	await _tap(KEY_ESCAPE)
	_expect(not paused and not game.pause_menu.visible, "Esc resumes ordinary pause")
	_key(KEY_E, true, true)
	await _frames(3)
	_expect(completed == before and not game.dialogue.visible, "held E cannot act after pause resumes")
	_release()
	await _frames(2)
	_expect(game.player_state.health == health_before and game.player_state.money == money_before, "NPC conversation does not change health or money")


func _check_container() -> void:
	await _place(Vector2(138, 402))
	var before: int = completed
	var health_before: int = game.player_state.health
	var money_before: int = game.player_state.money
	_expect(game.interactions.current_target == chest and not chest.opened, "unopened nearby container is selected")
	await _tap(KEY_E)
	_expect(chest.opened and completed == before + 1, "E opens the selected container through shared controller")
	_expect(game.dialogue.visible and not last_message.is_empty() and game.dialogue_text.text == last_message, "container displays its action result")
	await _save("container-opened")
	await _click(game.dialogue_close)
	_expect(not paused and not game.dialogue.visible, "dialogue close button works while world is paused")
	await _frames(2)
	_expect(game.interaction_hint.visible and game.interaction_hint.text == chest.prompt(), "opened container hint stays synchronized")
	await _save("container-inspected")
	await _tap(KEY_E)
	_expect(completed == before + 2 and chest.opened and game.dialogue.visible, "repeat container action remains safe and usable")
	_expect(not game.dialogue_text.text.is_empty(), "repeat container action explains its result")
	_expect(game.player_state.health == health_before and game.player_state.money == money_before, "container does not grant health or money")
	await _tap(KEY_ESCAPE)


func _check_discarded_target() -> void:
	var target: InteractionTarget = game.world.get_node("World/MerchantEast/Interaction") as InteractionTarget
	await _place(Vector2(192, 288))
	_expect(game.interactions.current_target == target, "real merchant target can be selected")
	var before: int = completed
	# Free the currently selected target before a refresh can clear its reference.
	target.free()
	game.interactions.try_interact()
	game.interactions.refresh_target()
	_expect(completed == before and game.interactions.current_target == null, "freed target cannot execute and is cleared safely")
	_expect(not game.interaction_hint.visible, "freed target leaves no stale hint")


func _check_reset() -> void:
	var before: int = completed
	await _tap(KEY_ESCAPE)
	game._return_to_menu()
	await _frames(2)
	_expect(game.world == null and game.main_menu.visible and not paused, "return to main menu removes interaction world")
	_expect(game.interactions.current_target == null and not game.interaction_hint.visible, "return clears target and hint")
	await _tap(KEY_E)
	_expect(completed == before and not game.dialogue.visible, "E after return cannot use discarded targets")
	await _tap(KEY_ENTER)
	await _frames(2)
	chest = game.world.get_node("World/Chest/Interaction") as InteractionTarget
	_expect(not chest.opened, "New Game resets container opened state")
	_expect(game.player_state.health == 100 and game.player_state.money == 0, "interaction did not alter new game defaults")
	await _save("new-game-reset")


func _on_completed(message: String) -> void:
	completed += 1
	last_message = message


func _place(position: Vector2) -> void:
	game.player.global_position = position
	game.player.velocity = Vector2.ZERO
	await _frames(2)
	game.interactions.refresh_target()
	await process_frame


func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event, true)
		await _frames(1)


func _tap(key: Key) -> void:
	_key(key, true)
	await _frames(1)
	_key(key, false)
	await _frames(1)


func _key(key: Key, pressed: bool, echo: bool = false) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)


func _release() -> void:
	for key: Key in KEYS:
		_key(key, false)


func _frames(count: int) -> void:
	for tick: int in range(count):
		await physics_frame
		await process_frame


func _save(label: String) -> void:
	if not capture:
		return
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(CAPTURE_DIR + "/" + label + ".png") != OK:
		_expect(false, "save interaction capture: " + label)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
