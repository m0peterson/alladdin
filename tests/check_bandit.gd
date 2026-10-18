extends SceneTree

const Bandit = preload("res://scripts/bandit.gd")
const Recovery = preload("res://scripts/defeat_recovery.gd")
const Player = preload("res://scripts/player.gd")
var player: Player
var enemy: Bandit
var state: PlayerState
var recovery: Recovery
var failures: int = 0
var world: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	for action: StringName in [&"attack", &"dodge"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var scene: Node = load("res://scenes/start.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	world = scene.get_node("World")
	world.get_node("Bandit").free()
	player = world.get_node("Player") as Player
	state = PlayerState.new()
	player.state = state
	enemy = load("res://scenes/bandit.tscn").instantiate() as Bandit
	enemy.position = Vector2(552, 344)
	world.add_child(enemy)
	enemy.configure(player)
	recovery = Recovery.new()
	world.add_child(recovery)
	recovery.configure(player, state, Vector2(136, 368), enemy)
	await _frames(3)
	player.position = Vector2(500, 344)
	var original: Vector2 = enemy.position
	await _frames(18)
	_expect(enemy.position.x < original.x - 5, "bandit approaches within arena")
	await _until_phase(Bandit.Phase.WINDUP, 90)
	_expect(state.health == 100, "windup gives warning before damage")
	var remaining: float = enemy.phase_time
	_expect(remaining > 0.45, "readable half-second windup")
	if "--capture-bandit" in OS.get_cmdline_user_args():
		await _capture("bandit_windup")
	if "--capture-bandit" in OS.get_cmdline_user_args():
		await _until_phase(Bandit.Phase.ACTIVE, 90)
		await _capture("bandit_active")
	await _until_phase(Bandit.Phase.RECOVERY, 90)
	_expect(state.health == 80, "one hit changes health once")
	_expect(player.sprite.modulate != Color.WHITE, "player damage has visible hit feedback")
	_expect(enemy.phase_time > 0.55, "recovery leaves counterattack window")
	if "--capture-bandit" in OS.get_cmdline_user_args():
		await _capture("bandit_hit_player")
	await _frames(10)
	_expect(state.health == 80, "no repeat damage during recovery")

	# Pause freezes the telegraph, movement and damage.
	enemy.reset_duel()
	player.reset_combat()
	player.position = Vector2(532, 344)
	await _until_phase(Bandit.Phase.WINDUP, 20)
	var paused_time: float = enemy.phase_time
	paused = true
	await _frames(20)
	_expect(is_equal_approx(enemy.phase_time, paused_time), "pause freezes enemy windup")
	_expect(not enemy.receive_damage(20), "paused enemy rejects damage")
	paused = false

	# Dodge the locked direction just as the windup ends.
	await _frames(25)
	player.facing = Vector2.UP
	_press(&"dodge")
	await _frames(2)
	_expect(player.dodge_remaining > 0.0, "real player dodge starts during warning")
	await _frames(28)
	_expect(state.health == 80, "dodge escapes bandit strike")

	# Thin obstacle blocks the duel, not merely the visual marker.
	enemy.reset_duel()
	player.reset_combat()
	player.position = Vector2(532, 344)
	var wall: StaticBody2D = StaticBody2D.new()
	wall.collision_layer = 1
	var collider: CollisionShape2D = CollisionShape2D.new()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = Vector2(4, 48)
	collider.shape = shape
	wall.add_child(collider)
	wall.position = Vector2(542, 340)
	world.add_child(wall)
	await _frames(85)
	_expect(state.health == 80 and enemy.phase != Bandit.Phase.ACTIVE, "wall prevents aggro and melee damage")
	_expect(enemy.position.distance_to(enemy.home) < 1.0, "enemy stays behind obstacle")
	wall.queue_free()
	await _frames(3)

	player.position = Vector2(136, 368)
	await _frames(90)
	_expect(enemy.position.distance_to(enemy.home) < 1.0 and enemy.phase == Bandit.Phase.IDLE, "duel stays near bandit home")

	# Three actual directed swings defeat the enemy.
	for swing: int in range(3):
		player.reset_combat()
		player.position = enemy.position + Vector2(-20, 0)
		player.facing = Vector2.RIGHT
		await _frames(2)
		_press(&"attack")
		await _frames(10)
		_expect(enemy.hit_flash > 0.0, "bandit damage has visible hit feedback")
		if swing == 0 and "--capture-bandit" in OS.get_cmdline_user_args():
			await _capture("bandit_hit_feedback")
		await _frames(16)
		_expect(enemy.health == maxi(0, 60 - (swing + 1) * 20), "player swing %d hits once" % swing)
	_expect(enemy.phase == Bandit.Phase.DEFEATED, "duel can be won")
	_expect(not enemy.is_in_group("damageable"), "defeated bandit leaves combat targets")
	var before: int = state.health
	await _frames(100)
	_expect(state.health == before, "defeated bandit stops attacking")
	if "--capture-bandit" in OS.get_cmdline_user_args():
		await _capture("bandit_defeated")

	await _check_recovery()
	print("PASS: T09 bandit, duel, dodge, obstacle, pause and recovery" if failures == 0 else "FAIL: T09 (%d assertions)" % failures)
	quit(1 if failures else 0)


func _check_recovery() -> void:
	var inventory: RefCounted
	var inventory_before: Array = []
	if ResourceLoader.exists("res://scripts/item_inventory.gd"):
		var inventory_script: GDScript = load("res://scripts/item_inventory.gd") as GDScript
		if inventory_script == null or not inventory_script.can_instantiate():
			_expect(false, "inventory fixture script loads; import project before tests")
			return
		inventory = inventory_script.new()
		_expect(inventory.add_item("bread", 2), "inventory fixture adds food")
		_expect(inventory.add_item("lamp", 1, {"instance_id": "quest_lamp", "stolen": true, "owner_id": "warehouse", "source_id": "warehouse_lamp"}), "inventory fixture adds unique lamp")
		inventory_before = inventory.get_stacks()
	else:
		print("NOT RUN: actual inventory/lamp fixture requires T06 integration")
	for money: int in [37, 9, 0, 101]:
		state.money = money
		state.health = 20
		player.reset_combat()
		player.position = Vector2(500, 344)
		_expect(player.receive_damage(20, enemy.position), "lethal hit accepted")
		await _frames(3)
		_expect(state.health == PlayerState.MAX_HEALTH, "defeat restores max health")
		_expect(state.money == money - floori(money * 0.1), "defeat deducts floor ten percent")
		_expect(player.position.is_equal_approx(Vector2(136, 368)), "defeat returns to start")
		_expect(player.attack_phase == Player.AttackPhase.IDLE and player.dodge_remaining == 0.0, "defeat clears combat state")
		if inventory != null:
			_expect(inventory.get_stacks() == inventory_before and inventory.count_item("lamp") == 1, "defeat retains inventory and unique lamp provenance")
	if "--capture-bandit" in OS.get_cmdline_user_args():
		await _capture("bandit_recovered")


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	# Script-mode input injection is dispatched before the next physics frame.
	call_deferred("_release", action)


func _release(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)


func _until_phase(wanted: int, limit: int) -> void:
	for tick: int in range(limit):
		if enemy.phase == wanted:
			return
		await _frames(1)
	_expect(false, "phase %d reached before timeout" % wanted)


func _frames(count: int) -> void:
	for tick: int in range(count):
		await physics_frame
		await process_frame


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT RUN: capture requires actual renderer")
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var destination: String = OS.get_environment("T09_CAPTURE_DIR")
	if destination.is_empty():
		destination = "res://work/t09-captures"
	DirAccess.make_dir_recursive_absolute(destination)
	var error: Error = root.get_texture().get_image().save_png(destination.path_join(label + ".png"))
	_expect(error == OK, "capture " + label)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
