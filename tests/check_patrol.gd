extends SceneTree

const Patrol = preload("res://scripts/guard_patrol.gd")
const Sight = preload("res://scripts/visibility_query.gd")
var failures: int = 0
var guards: Array[Patrol] = []
var world: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if change_scene_to_file("res://scenes/start.tscn") != OK:
		push_error("FAIL: cannot open real bazaar")
		quit(1)
		return
	await scene_changed
	world = current_scene.get_node("World") as Node2D
	var old_marker: Node = world.get_node_or_null("Guard")
	if old_marker != null:
		old_marker.free()
	guards = Patrol.install(world)
	await _frames(2)
	_expect(guards.size() == 3, "three guards installed")
	_expect(Patrol.install(world) == guards, "installation preserves actors and stable IDs")
	var ids: Dictionary = {}
	for guard: Patrol in guards:
		_expect(not ids.has(guard.guard_id), "unique stable guard ID")
		ids[guard.guard_id] = true
		_expect(guard.get_meta("world_id") == String(guard.guard_id), "persistent world ID")
		_expect(guard.get_node("CollisionShape2D") is CollisionShape2D, "guard has foot collisions")
	await _check_visibility()
	await _check_pause()
	# No teleports or synthetic arena: every waypoint of each installed actor
	# must be reached through CharacterBody movement in the actual bazaar.
	for tick: int in range(3000):
		await _frames(1)
		var finished: bool = true
		for guard: Patrol in guards:
			finished = finished and guard.completed_loops >= 3
			_expect(_on_route(guard), "guard remains on its walkable route: " + String(guard.guard_id))
		if finished:
			break
	for guard: Patrol in guards:
		_expect(guard.completed_loops >= 3, "%s completes three loops (actual %d)" % [guard.guard_id, guard.completed_loops])
		_expect(guard.reached_waypoints >= 12, "all four waypoints reached in each loop")
		print("INFO: %s loops=%d waypoints=%d position=%s" % [guard.guard_id, guard.completed_loops, guard.reached_waypoints, guard.position])
	await _check_collision()
	if failures > 0:
		push_error("FAIL: T10 patrol/visibility (%d assertions)" % failures)
		quit(1)
	else:
		print("PASS: T10 three real-bazaar patrols, collisions, pause and shared visibility geometry")
		print("NOT RUN: visual patrol review; use actual renderer separately")
		quit(0)


func _check_visibility() -> void:
	var query: Sight = Sight.new()
	var observer: Node2D = Node2D.new()
	world.add_child(observer)
	# Both targets are 100 px to the right. Divider occupies x=256..336,
	# y=96..264: the first ray crosses it; the second passes south of it.
	observer.position = Vector2(240, 200)
	_expect(not query.can_see(observer, Vector2(340, 200), Vector2.RIGHT), "same 100 px distance occluded by actual Divider")
	observer.position = Vector2(240, 312)
	_expect(query.can_see(observer, Vector2(340, 312), Vector2.RIGHT), "same 100 px distance visible without wall")
	_expect(not query.can_see(observer, Vector2(340, 312), Vector2.LEFT), "target outside facing sector")
	_expect(not query.can_see(observer, Vector2(360, 312), Vector2.RIGHT), "target outside configured distance")
	query.max_distance = 130.0
	_expect(query.can_see(observer, Vector2(360, 312), Vector2.RIGHT), "witness can reuse query with a different distance")
	query.sector_degrees = 360.0
	_expect(query.can_see(observer, Vector2(140, 312), Vector2.RIGHT), "witness can reuse full-circle sector")
	query.sector_degrees = 60.0
	_expect(not query.can_see(observer, Vector2(300, 372), Vector2.RIGHT), "narrow witness sector excludes diagonal")
	query.sector_degrees = 100.0
	_expect(query.can_see(observer, Vector2(300, 372), Vector2.RIGHT), "wider witness sector includes same diagonal")
	var guard: Patrol = guards[0]
	_expect(guard.can_see(guard.global_position + guard.facing * 20), "guard uses common query and excludes its own collider")
	observer.free()


func _check_pause() -> void:
	var positions: Array[Vector2] = []
	var waypoints: Array[int] = []
	for guard: Patrol in guards:
		positions.append(guard.position)
		waypoints.append(guard.reached_waypoints)
	paused = true
	await _frames(12)
	for index: int in range(guards.size()):
		_expect(guards[index].position == positions[index], "pause stops guard movement")
		_expect(guards[index].reached_waypoints == waypoints[index], "pause stops patrol progress")
	paused = false
	await _frames(2)
	for index: int in range(guards.size()):
		_expect(guards[index].position != positions[index], "resume continues patrol")


func _check_collision() -> void:
	var guard: Patrol = guards[0]
	guard.set_physics_process(false)
	# Deliberately aim into the existing Divider; body movement must stop at
	# the western surface (256), with a 5 px half-width foot collider.
	guard.position = Vector2(244, 200)
	await _frames(2)
	for tick: int in range(30):
		guard.velocity = Vector2(100, 0)
		guard.move_and_slide()
		await _frames(1)
	_expect(guard.position.x <= 251.1 and guard.position.x >= 250.8, "guard collides with actual wall instead of crossing")
	_expect(guard.get_slide_collision_count() > 0, "guard reports wall collision")


func _on_route(guard: Patrol) -> bool:
	for index: int in range(guard.route.size()):
		var start: Vector2 = guard.route[index]
		var end: Vector2 = guard.route[(index + 1) % guard.route.size()]
		if Geometry2D.get_closest_point_to_segment(guard.position, start, end).distance_to(guard.position) < 0.2:
			return true
	return false


func _frames(count: int) -> void:
	for tick: int in range(count):
		await physics_frame
		await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("FAIL: " + message)
