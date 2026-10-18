extends SceneTree

const Player = preload("res://scripts/player.gd")
const Dummy = preload("res://scripts/training_dummy.gd")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var player: Player
var front: Dummy
var behind: Dummy
var side: Dummy
var failures: int = 0
var defeats: int = 0
var world: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_register_inputs()
	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.add_child(world)
	player = PLAYER_SCENE.instantiate() as Player
	player.position = Vector2(80, 80)
	player.state = PlayerState.new()
	player.defeated.connect(func() -> void: defeats += 1)
	world.add_child(player)
	front = _dummy(Vector2(100, 80))
	behind = _dummy(Vector2(60, 80))
	side = _dummy(Vector2(80, 100))
	player.facing = Vector2.RIGHT
	await _frames(2)
	_key(KEY_SPACE, true)
	await _frames(2)
	_expect(player.attack_phase == Player.AttackPhase.WINDUP and front.hit_count == 0, "windup delays damage")
	await _frames(7)
	_expect(player.attack_phase == Player.AttackPhase.ACTIVE and front.hit_count == 1, "active phase hits forward target")
	_expect(behind.hit_count == 0 and side.hit_count == 0, "attack excludes rear and side")
	await _frames(7)
	_expect(player.attack_phase == Player.AttackPhase.RECOVERY and front.hit_count == 1, "overlap hits once and recovery has no hit")
	_key(KEY_SPACE, false)
	_key(KEY_SPACE, true)
	await _frames(4)
	_expect(front.hit_count == 1, "recovery rejects new attack")
	await _frames(18)
	_expect(front.hit_count == 1, "held Space does not repeat")
	_key(KEY_SPACE, false)
	await _frames(2)
	_mouse(true)
	await _frames(10)
	_expect(front.hit_count == 2, "left mouse attacks through InputMap")
	_mouse(false)
	await _frames(24)
	var wall: StaticBody2D = _wall(Vector2(90, 77), Vector2(3, 30))
	await _frames(2)
	await _swing()
	_expect(front.hit_count == 2, "wall layer 1 blocks melee ray")
	wall.queue_free()
	await _frames(2)
	# A fresh swing can damage the same target again after recovery.
	await _swing()
	_expect(front.hit_count == 3 and front.total_damage == 3 * Player.ATTACK_DAMAGE, "fresh swing hits again")
	# Continuous collision handles a high-speed dodge into a thin wall.
	wall = _wall(Vector2(100, 77), Vector2(2, 30))
	player.position = Vector2(80, 80)
	_key(KEY_Q, true)
	await _frames(3)
	_expect(player.dodge_remaining > 0.0, "Q starts dodge")
	_expect(not player.receive_damage(10), "dodge grants brief invulnerability")
	await _frames(11)
	_expect(player.position.x <= 94.1 and player.position.x > 80.0, "dodge moves but cannot cross thin wall")
	var stopped: Vector2 = player.position
	_key(KEY_Q, false)
	_key(KEY_Q, true)
	await _frames(3)
	_expect(player.dodge_remaining == 0.0 and player.position.is_equal_approx(stopped), "cooldown rejects second dodge")
	_key(KEY_Q, false)
	wall.queue_free()
	await _frames(32)
	_key(KEY_Q, true)
	await _frames(3)
	_expect(player.dodge_remaining > 0.0 and player.position.x > stopped.x, "dodge is available after cooldown")
	_key(KEY_Q, false)
	await _frames(14)
	_expect(player.receive_damage(10), "damage applies outside dodge")
	_expect(player.state.health == 90 and not player.receive_damage(10), "hurt iframe prevents repeated damage")
	await _frames(25)
	_expect(player.receive_damage(1000) and defeats == 1 and player.state.health == 0, "lethal damage emits defeat once")
	_expect(not player.receive_damage(1) and defeats == 1, "defeat is latched")
	player.state.health = PlayerState.MAX_HEALTH
	player.reset_combat()
	await _frames(2)
	_expect(player.receive_damage(1), "reset permits damage again")
	await _check_pause_and_gui()
	_key(KEY_SPACE, false)
	_key(KEY_Q, false)
	_mouse(false)
	if failures == 0:
		print("PASS: T08 phases, direction, overlap, walls, mouse, dodge cooldown, damage and paused/GUI held input")
	else:
		push_error("FAIL: T08 combat (%d assertions)" % failures)
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)


func _check_pause_and_gui() -> void:
	player.reset_combat()
	player.position = Vector2(80, 80)
	player.facing = Vector2.RIGHT
	await _frames(2)
	_key(KEY_SPACE, true)
	await _frames(2)
	_expect(player.attack_phase == Player.AttackPhase.WINDUP, "pending attack before menu")
	paused = true
	var before: int = front.hit_count
	_key(KEY_Q, true)
	_mouse(true)
	await _frames(20)
	_expect(front.hit_count == before and player.dodge_remaining == 0.0 and not player.receive_damage(10), "pause blocks combat and cancels pending swing")
	player.suppress_combat_until_release()
	paused = false
	await _frames(30)
	_expect(front.hit_count == before and player.dodge_remaining == 0.0, "held Space, mouse and Q cannot activate on resume")
	_key(KEY_SPACE, false)
	_key(KEY_Q, false)
	await _frames(2)
	# Mouse still held: releasing keys alone must not re-arm combat.
	_key(KEY_SPACE, true)
	await _frames(10)
	_expect(front.hit_count == before, "all combat inputs must release before rearming")
	_key(KEY_SPACE, false)
	_mouse(false)
	await _frames(2)
	await _swing()
	_expect(front.hit_count == before + 1, "fresh attack works after release")
	# A real focused GUI consumes Space before Player._unhandled_input.
	var button: Button = Button.new()
	button.position = Vector2(200, 120)
	button.size = Vector2(80, 30)
	root.add_child(button)
	button.grab_focus()
	_key(KEY_SPACE, true)
	await _frames(30)
	_expect(front.hit_count == before + 1, "focused GUI consumes combat key")
	_key(KEY_SPACE, false)
	button.queue_free()


func _register_inputs() -> void:
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = KEY_SPACE
		InputMap.action_add_event("attack", key)
		var mouse: InputEventMouseButton = InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", mouse)
	if not InputMap.has_action("dodge"):
		InputMap.add_action("dodge")
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = KEY_Q
		InputMap.action_add_event("dodge", key)


func _dummy(at: Vector2) -> Dummy:
	var result: Dummy = Dummy.new()
	result.position = at
	world.add_child(result)
	return result


func _wall(at: Vector2, size: Vector2) -> StaticBody2D:
	var result: StaticBody2D = StaticBody2D.new()
	result.position = at
	result.collision_layer = 1
	var collision: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	result.add_child(collision)
	world.add_child(result)
	return result


func _swing() -> void:
	_key(KEY_SPACE, true)
	await _frames(30)
	_key(KEY_SPACE, false)
	await _frames(2)


func _frames(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame


func _key(key: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _mouse(pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = Vector2(300, 160)
	Input.parse_input_event(event)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
