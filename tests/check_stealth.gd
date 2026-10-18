extends SceneTree

const Patrol = preload("res://scripts/guard_patrol.gd")
const DetectionUI = preload("res://scripts/guard_detection_ui.gd")
var failures: int = 0
var guard: Patrol
var player: CharacterBody2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not InputMap.has_action("sneak"):
		InputMap.add_action("sneak")
	change_scene_to_file("res://scenes/start.tscn")
	await scene_changed
	var world: Node2D = current_scene.get_node("World") as Node2D
	player = world.get_node("Player") as CharacterBody2D
	player.set_physics_process(false)
	guard = Patrol.install(world)[0]
	guard.set_physics_process(false)
	guard.position = Vector2(150, 312)
	guard.facing = Vector2.RIGHT
	guard.route = PackedVector2Array([guard.position, Vector2(220, 312)])
	guard.waypoint_index = 1
	player.position = Vector2(210, 312)
	guard.configure(player)
	guard.set_physics_process(true)
	var ui: Control = DetectionUI.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	current_scene.add_child(ui)
	ui.setup([guard])
	await _frames(8)
	_expect(guard.state == Patrol.State.SUSPICIOUS and guard.suspicion > 0.0, "sight raises suspicion before chase")
	_expect(ui.visible, "detection UI shows suspicion")
	var paused_suspicion: float = guard.suspicion
	var paused_position: Vector2 = guard.position
	paused = true
	await _frames(15)
	_expect(guard.suspicion == paused_suspicion and guard.position == paused_position, "pause freezes detection and movement")
	_expect(not ui.visible, "detection UI hides behind paused modal")
	paused = false
	await _frames(55)
	_expect(guard.state == Patrol.State.CHASE, "sustained sight starts chase")
	var known: Vector2 = guard.last_known_position
	player.position = Vector2(340, 200)
	await _frames(4)
	_expect(guard.last_known_position == known, "hidden relocation never updates remembered position")
	await _frames(260)
	_expect(guard.state == Patrol.State.RETURN or guard.state == Patrol.State.PATROL, "search ends and clears alarm")
	_expect(guard.suspicion == 0.0, "alarm clears after loss")
	await _frames(240)
	_expect(guard.state == Patrol.State.PATROL, "recorded trail returns guard to route")
	guard.set_physics_process(false)
	guard.position = Vector2(244, 200)
	guard.route = PackedVector2Array([guard.position, Vector2(200, 200)])
	guard.waypoint_index = 1
	guard.facing = Vector2.RIGHT
	guard.configure(null)
	guard.report_crime(Vector2(340, 200))
	guard.set_physics_process(true)
	await _frames(20)
	_expect(guard.state == Patrol.State.CHASE, "crime snapshot triggers pursuit without player reference")
	_expect(guard.position.x <= 251.1, "wall blocks chase movement")
	guard.configure(player)
	player.position = Vector2(348, 206)
	await _frames(6)
	_expect(guard.last_known_position == Vector2(340, 200), "wall blocks knowledge updates from configured target")
	await _frames(184)
	_expect(guard.state == Patrol.State.SEARCH, "unreachable snapshot starts bounded search")
	await _frames(250)
	_expect(guard.state == Patrol.State.PATROL, "unreachable snapshot returns without hanging")
	_expect(guard.last_known_position == Vector2(340, 200), "report retains snapshot only")
	await _check_sneak()
	var removed_target: Node2D = Node2D.new()
	world.add_child(removed_target)
	guard.configure(removed_target)
	guard.report_crime(Vector2(340, 200))
	removed_target.free()
	guard.set_physics_process(true)
	await _frames(4)
	_expect(guard.state == Patrol.State.CHASE, "freed player reference leaves snapshot pursuit safe")
	if failures:
		push_error("FAIL: T11 stealth (%d assertions)" % failures)
		quit(1)
	else:
		print("PASS: T11 suspicion, chase, hidden memory, bounded search/return, wall, sneak and noise")
		quit(0)


func _check_sneak() -> void:
	guard.set_physics_process(false)
	player.position = Vector2(100, 312)
	player.set_physics_process(true)
	Input.action_press("move_right")
	await _frames(4)
	var normal_speed: float = player.velocity.length()
	var normal_noise: float = player.get_noise_radius()
	Input.action_press("sneak")
	await _frames(4)
	_expect(player.velocity.length() < normal_speed, "Shift reduces speed")
	_expect(player.get_noise_radius() < normal_noise and player.get_noise_radius() > 0.0, "Shift reduces actual moving footstep radius")
	player.suppress_movement_until_release()
	await _frames(2)
	_expect(not player.is_sneaking(), "held Shift suppressed on modal return")
	Input.action_release("move_right")
	Input.action_release("sneak")
	await _frames(2)
	_expect(player.get_noise_radius() == 0.0, "stationary player has no footsteps")
	Input.action_press("move_right")
	await _frames(2)
	player.position = Vector2(210, 312)
	guard.position = Vector2(180, 312)
	guard.facing = Vector2.LEFT
	guard.configure(player)
	guard.state = Patrol.State.PATROL
	await _frames(1)
	_expect(guard._hears_player(), "nearby normal footsteps heard outside sight sector")
	Input.action_press("sneak")
	await _frames(1)
	_expect(not guard._hears_player(), "sneak radius avoids same guard")
	Input.action_release("sneak")
	player.set_physics_process(false)
	player.position = Vector2(265, 200)
	guard.position = Vector2(244, 200)
	await _frames(2)
	_expect(not guard._hears_player(), "wall blocks even nearby footsteps")
	Input.action_release("move_right")


func _frames(count: int) -> void:
	for tick: int in range(count):
		await physics_frame
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
